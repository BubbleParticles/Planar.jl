using ..OrderTypes.ExchangeTypes: ExchangeID
using ..OrderTypes: PositionSide, PositionTrade, LiquidationType, ReduceOnlyOrder
using ..Strategies.Instruments.Derivatives: Derivative
using ..Executors.Instances: leverage_tiers, tier, position
import ..Executors.Instances: Position, MarginInstance
using ..Executors: withtrade!, maintenance!, orders, isliquidatable, LIQUIDATION_FEES, hasorders
using ..Instances: PositionOpen, PositionUpdate, PositionClose
using ..Instances: margin, maintenance, status, posside, ishedged, isopen, iszero, isdust, cash, value, raw
using ..Strategies: lowat, highat
using ..Misc: DFT, Long, Short, marginmode, CrossMargin
import ..Executors: position!

"""
Open a position in `s` with `ii` using `t`.

$(TYPEDSIGNATURES)

The function opens a position in the specified strategy using the given margin instance and position trade.
"""
function open_position!(
    s::MarginStrategy, ii::MarginInstance, t::PositionTrade{P};
) where {P<:PositionSide}
    # NOTE: Order of calls is important
    po = position(ii, P)
    if !ishedged(ii)
        @deassert cash(ii, opposite(P())) == DFT(0.0) (cash(ii, opposite(P()))),
        status(ii, opposite(P()))
    end
    @deassert !isopen(po)
    @deassert notional(po) == DFT(0.0)
    # Cash should already be updated from trade construction
    @deassert abs(cash(po)) == abs(cash(ii, P())) >= abs(t.amount)
    withtrade!(po, t)
    # Notional should never be above the trade size
    # unless fees are negative
    @deassert notional(po) < abs(t.size) ||
        minfees(ii) < DFT(0.0) ||
        abs(t.amount) < abs(cash(ii, P()))
    # finalize
    status!(ii, P(), PositionOpen())
    @deassert status(po) == PositionOpen()
    call!(s, ii, t, po, PositionOpen())
end

@doc """Force exit a position.

$(TYPEDSIGNATURES)

This function cancels all orders associated with the specified position and updates the position with a forced order. The function also handles cases where the position is already closed or has zero committed funds.

"""
function force_exit_position(s::Strategy, ii, p, date::DateTime; kwargs...)
    @ifdebug @assert !hasorders(s, ii, p)
    @ifdebug @deassert isempty(collect(values(s, ii, p)))
    @ifdebug @deassert iszero(committed(ii, p)) committed(ii, p)
    ot = ReduceOnlyOrder(p)
    price = priceat(s, ot, ii, date)
    amount = abs(nondust(ii, ot, price))
    if amount > DFT(0.0)
        prevcash = s.cash.value
        t = call!(s, ii, ot; amount, date, price, kwargs...)
        if !isnothing(t)
            @debug "force exit position: " amount price t.price s.cash.value - prevcash t.value
            @ifdebug @deassert let o = t.order
                (
                    t isa Trade &&
                    o.date == date &&
                    isapprox(o.amount, amount; atol=ii.precision.amount)
                )
            end
            @ifdebug @deassert isdust(ii, price, p)
            return true
        else
            @warn "force_exit_position: close trade failed, position state kept" ii = raw(ii) side = p amount price date
            return false
        end
    end
    return true
end

"""
Closes a leveraged position.

$(TYPEDSIGNATURES)

When a date is given, this function closes pending orders and sells the remaining cash.
It then resets the position, deletes it from the holdings, and checks that the position is closed and no funds are committed.

"""
function close_position!(s::MarginStrategy, ii, p::PositionSide, date=nothing; kwargs...)
    # when a date is given we should close pending orders and sell remaining cash
    if !isnothing(date)
        # A failed force-exit (no price, dust-reject, order construction
        # failure) must not zero position state: keep the position and report
        # failure so the `PositionClose` caller can surface it.
        force_exit_position(s, ii, p, date; kwargs...) || return false
    end
    reset!(ii, p)
    # In hedged mode, the opposite side may still be open — only remove from holdings when both sides are closed.
    iszero(ii) && delete!(s.holdings, ii)
    @ifdebug @deassert !isopen(ii, p) && iszero(ii, p)
    true
end

# TODO: Implement updating margin of open positions
# function update_margin!(pos::Position, qty::Real)
#     p = posside(pos)
#     price = entryprice(pos)
#     lev = leverage(pos)
#     size = notional(pos)
#     prev_additional = margin(pos) - size / lev
#     @deassert prev_additional >= DFT(0.0) && qty >= DFT(0.0)
#     additional = prev_additional + qty
#     liqp = liqprice(p, price, lev, mmr(pos); additional, size)
#     liqprice!(pos, liqp)
#     # margin!(pos, )
# end

@doc """ Liquidates a position at a particular date.

$(TYPEDSIGNATURES)

`fees`: the fees for liquidating a position (usually higher than trading fees.)
`actual_price/amount`: the price/amount to execute the liquidation market order with (for paper mode).

"""
function liquidate!(
    s::MarginStrategy, ii::MarginInstance, p::PositionSide, date, fees=LIQUIDATION_FEES;
)
    pos = position(ii, p)
    ords = collect(values(s, ii, p))
    for o in ords
        @ifdebug @deassert o isa Order
        cancel!(s, o, ii; err=LiquidationOverride(o, liqprice(pos), date, p))
    end
    amount = abs(cash(pos).value)
    price = liqprice(pos)
    t = call!(s, ii, LiquidationOrder{liqside(p),typeof(p)}; amount, date, price, fees)
    isnothing(t) || begin
        @ifdebug @deassert t.order.date == date && DFT(0.0) < abs(t.amount) <= abs(t.order.amount)
    end
    @ifdebug @deassert isdust(ii, price, p) (notional(ii, p), cash(ii, p), cash(ii, p) * price, p)
    close_position!(s, ii, p)
end

@doc """ Check whether a cross-margin account covers total maintenance margin.

$(TYPEDSIGNATURES)

Cross-margin positions share the strategy-level QC pool as collateral: the
exchange liquidates the *account*, not the position. A position breaching its
standalone liquidation price must therefore not liquidate while account equity
(`s.cash` + position values at `date` candle prices) still covers the total
maintenance margin of all open cross positions. Returns `false` (fall back to
per-position liquidation) when prices are unavailable, e.g. Paper dates with
no loaded candle.
"""
function _cross_account_covered(s::MarginStrategy, date::DateTime)
    equity = try
        s.cash.value
    catch
        return false
    end
    tot_maint = zero(DFT)
    for ii in s.holdings
        marginmode(ii) isa CrossMargin || continue
        for p in (Long(), Short())
            isopen(ii, p) || continue
            cp = try
                p isa Long ? lowat(s, ii, date) : highat(s, ii, date)
            catch
                return false
            end
            equity += value(ii, p; current_price=cp)
            tot_maint += maintenance(ii, p)
        end
    end
    equity >= tot_maint
end

@doc """
Checks asset positions for liquidations and executes them (Non hedged mode, so only the currently open position).

$(TYPEDSIGNATURES)

If a position is open and liquidatable, it is liquidated using the `liquidate!` function.
The liquidation is performed on the asset positions in `ii` on the specified `date`.
Cross-margin positions additionally require the whole account to be under
water (see `_cross_account_covered`): shared collateral absorbs a single
position's excursion past its standalone liquidation price.

"""
function _maybe_liquidate_positions!(s::MarginStrategy, ii::MarginInstance, date::DateTime)
    if marginmode(ii) isa CrossMargin && _cross_account_covered(s, date)
        return nothing
    end
    if ishedged(ii)
        for p in (Long(), Short())
            if isopen(ii, p) && isliquidatable(s, ii, p, date)
                liquidate!(s, ii, p, date)
            end
        end
    else
        pos = position(ii)
        isnothing(pos) && return nothing
        p = posside(pos)
        isliquidatable(s, ii, p, date) && liquidate!(s, ii, p, date)
    end
end

function maybe_liquidate!(s::MarginStrategy, ii::MarginInstance, date::DateTime)
    _maybe_liquidate_positions!(s, ii, date)
end

# Rate-limit live liquidation checks: `isliquidatable(::Strategy{Live}, ...)`
# calls `lastprice(ii)` which hits the gateway. Checking on every trade would
# produce O(trades × open_positions) HTTP calls — gate to once per minute,
# tracked per instance so one busy instrument doesn't suppress the rest.
const _LIQ_CHECK_INTERVAL = Minute(1)
function maybe_liquidate!(s::MarginStrategy{Live}, ii::MarginInstance, date::DateTime)
    checks = @lget! s.attrs :live_last_liq_check Dict{UInt,DateTime}()
    key = objectid(ii)
    last = get(checks, key, nothing)
    if !isnothing(last) && tt.now() - last < _LIQ_CHECK_INTERVAL
        return nothing
    end
    checks[key] = tt.now()
    _maybe_liquidate_positions!(s, ii, date)
end
@doc """Updates the position by applying a position trade.

$(TYPEDSIGNATURES)

Applies the position trade `t` to the margin strategy `s` and the margin instance `ii`.
"""
function update_position!(
    s::MarginStrategy, ii, t::PositionTrade{P}
) where {P<:PositionSide}
    # NOTE: Order of calls is important
    po = position(ii, P)
    @ifdebug @deassert notional(po) != DFT(0.0)
    # Cash should already be updated from trade construction
    withtrade!(po, t)
    # position is still open
    call!(s, ii, t, po, PositionUpdate())
end

@doc """ Updates or opens a position based on a given trade.

$(TYPEDSIGNATURES)

This function checks if a position is open. If it is, it either updates the position with the given trade or closes it if the position is dust.
If the position is not open, it opens a new position with the given trade.
After updating or opening the position, it checks if the position needs to be liquidated.

"""
function position!(
    s::MarginStrategy, ii::MarginInstance, t::PositionTrade{P}; check_liq=true
) where {P<:PositionSide}
    @ifdebug @deassert exchangeid(s) == exchangeid(t)
    @ifdebug @deassert t.order.asset == ii.asset
    pos = position(ii, P)
    if isopen(pos)
        if isdust(ii, t.price, P())
            close_position!(s, ii, P())
        else
            @ifdebug @deassert !iszero(cash(pos)) || t isa ReduceTrade
            @debug "position update" pos.entryprice[] t.value t.price
            update_position!(s, ii, t)
        end
    elseif t isa IncreaseTrade
        @debug "position open" cash(ii, t) t
        open_position!(s, ii, t)
    end
    if check_liq
        maybe_liquidate!(s, ii, t.date)
    end
end

@doc """ Updates a margin position in `Sim`/`Paper` mode from a new candle.

$(TYPEDSIGNATURES)

This function checks if a position is open and updates the timestamp.
If the position is liquidatable, it is liquidated.
Otherwise, the position remains open and a `PositionUpdate` is pinged.

Paper shares Sim liquidation/position-update semantics (candle prices),
so the Paper method delegates to the Sim implementation.

"""
function _date_position!(s::MarginStrategy, ii, date::DateTime, pos::Position)
    # NOTE: Order of calls is important
    @ifdebug @deassert isopen(pos)
    p = posside(pos)
    @ifdebug @deassert notional(pos) != DFT(0.0)
    timestamp!(pos, date)
    if isliquidatable(s, ii, p, date)
        liquidate!(s, ii, p, date)
    else
        # position is still open
        call!(s, ii, date, pos, PositionUpdate())
    end
end
function position!(s::MarginStrategy{Sim}, ii, date::DateTime, pos::Position=position(ii))
    _date_position!(s, ii, date, pos)
end
function position!(s::MarginStrategy{Paper}, ii, date::DateTime, pos::Position=position(ii))
    _date_position!(s, ii, date, pos)
end

_checkorders(s) = begin
    for (_, ords) in s.buyorders
        for (_, o) in ords
            @ifdebug @assert abs(committed(o)) > DFT(0.0)
        end
    end
    for (_, ords) in s.sellorders
        for (_, o) in ords
            @ifdebug @assert abs(committed(o)) > DFT(0.0)
        end
    end
end

""" Updates all open positions in a margin strategy for a specific date.

$(TYPEDSIGNATURES)

This function is used to update the state of all active asset holdings within the provided instance of `MarginStrategy` for a specified date.
Execution updates include the maintenance of position and order records and accounting for any change of asset state to reflect liquidations or trade updates.

"""
function positions!(s::MarginStrategy{<:Union{Paper,Sim}}, date::DateTime)
    @ifdebug _checkorders(s)
    # Collect holdings first to avoid mutation during iteration (liquidate! -> close_position! -> delete!(s.holdings, ii))
    holdings_copy = collect(s.holdings)
    for ii in holdings_copy
        @ifdebug @deassert isopen(ii) || hasorders(s, ii) ii
        if ishedged(ii)
            for p in (Long(), Short())
                if isopen(ii, p)
                    position!(s, ii, date, position(ii, p))
                end
            end
        else
            if isopen(ii)
                position!(s, ii, date)
            end
        end
    end
    @ifdebug _checkorders(s)
    for ii in universe(s)
        if !ishedged(ii)
            @ifdebug @deassert !(isopen(ii, Short()) && isopen(ii, Long()))
        end
        if ishedged(ii)
            for p in (Long(), Short())
                po = position(ii, p)
                if isopen(po)
                    @ifdebug @deassert ii ∈ s.holdings && !iszero(cash(po)) && isopen(po)
                else
                    @ifdebug @deassert iszero(cash(ii, p))
                end
            end
        else
            po = position(ii)
            if !isnothing(po)
                @ifdebug @deassert ii ∈ s.holdings && !iszero(cash(po)) && isopen(po)
            else
                @ifdebug @deassert iszero(cash(ii, Long())) &&
                    iszero(cash(ii, Short())) &&
                    !isopen(ii, Long()) &&
                    !isopen(ii, Short())
            end
        end
    end
end

@doc """ Warn if a `MarginStrategy` mode has no `positions!` method."""
positions!(s::MarginStrategy, args...; kwargs...) =
    @warn "`positions!` not implemented for $(typeof(s))"

positions!(args...; kwargs...) = nothing