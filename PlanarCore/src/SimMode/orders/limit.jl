using ..Lang: @deassert, @posassert, Lang, @ifdebug
using ..OrderTypes
using ..Executors.Checks: cost, withfees
using ..Executors: AnyFOKOrder, AnyIOCOrder, AnyGTCOrder, AnyPostOnlyOrder
import ..Executors: priceat, unfilled, isqueued
import ..OrderTypes: order!, FOKOrderType, IOCOrderType
using ..Simulations: Simulations as sml
using ..Strategies: Strategies as st, MarginStrategy
using ..Misc: DFT

@doc """ Creates a simulated limit order.

$(TYPEDSIGNATURES)

This function creates a limit order in a simulated environment. It takes a strategy `s`, an order type `t`, and an asset `ii` as inputs, along with an `amount` and an optional `skipcommit` flag. If the order is valid, it is queued for execution.
"""
function create_sim_limit_order(s, t, ii; amount, skipcommit=false, kwargs...)
    @debug "create_sim_limit_order: kwargs" kwargs
    o = limitorder(s, ii, amount; type=t, skipcommit, kwargs...)
    isnothing(o) && return nothing
    queue!(s, o, ii; skipcommit) || return nothing
    @deassert skipcommit || abs(committed(o)) > DFT(0.0)
    return o
end

@doc """ The price at a particular date for an order.

$(TYPEDSIGNATURES)

This function returns the price at a particular date for an order. It takes a strategy `s`, an order type, an asset `ii`, and a date as inputs.
"""
function priceat(s::Strategy{Sim}, ::Type{<:Order}, ii, date)
    tick = get(s.attrs, :sim_current_tick, nothing)
    tick isa TradeTick && tick.asset === ii && return tick.price
    st.openat(ii, date)
end
priceat(s::Strategy{Sim}, ::T, args...) where {T<:Order} = priceat(s, T, args...)
function priceat(s::MarginStrategy{Sim}, ::T, args...) where {T<:Order}
    priceat(s, T, args...)
end

@doc """ Determines if a buy limit order is triggered.

$(TYPEDSIGNATURES)

This function checks if a buy limit order `o` is triggered at a given `date` for an asset `ii`. It returns a boolean indicating whether the order is triggered.
"""
_istriggered(o::AnyLimitOrder{Buy}, date, ii) = begin
    pbs = _pricebyside(o, date, ii)
    pbs, (pbs <= o.price)
end

@doc """ Determines if a sell limit order is triggered.

$(TYPEDSIGNATURES)

This function checks if a sell limit order `o` is triggered at a given `date` for an asset `ii`. It returns a boolean indicating whether the order is triggered.
"""
_istriggered(o::AnyLimitOrder{Sell}, date, ii) = begin
    pbs = _pricebyside(o, date, ii)
    pbs, pbs >= o.price
end

@doc "Progresses a simulated limit order."
function order!(
    s::NoMarginStrategy{Sim}, o::Order{<:LimitOrderType}, date::DateTime, ii; kwargs...
)
    @deassert abs(committed(o)) > DFT(0.0) o
    limitorder_ifprice!(s, o, date, ii; kwargs...)
end

@doc "Progresses a simulated limit order for a margin strategy."
function order!(
    s::MarginStrategy{Sim}, o::Order{<:LimitOrderType}, date::DateTime, ii; kwargs...
)
    @deassert abs(committed(o)) > DFT(0.0) (pricetime(o), o)
    t = limitorder_ifprice!(s, o, date, ii; kwargs...)
    @deassert gtxzero(s.cash_committed, atol=2s.cash_committed.precision) s.cash_committed.value
    t
end

function limitorder_ifprice!(s::Strategy{Sim}, o::AnyLimitOrder, date, ii; kwargs...)
    ds = get(s.attrs, :sim_debug_state, nothing)
    !isnothing(ds) && (ds.price_checks[] += 1)
    pbs, triggered = _istriggered(o, date, ii)
    if triggered
        # Order might trigger on high/low, but execution uses the *close* price.
        limitorder_ifvol!(s, o, date, ii; kwargs...)
    elseif o isa Union{AnyFOKOrder,AnyIOCOrder}
        if cancel!(s, o, ii; err=NotMatched(o.price, pbs, DFT(0.0), DFT(0.0)))
            nothing
        end
    else
        nothing
    end
end

@doc """ Determines if a trade should succeed based on the volume of the candle compared to the order amount.

$(TYPEDSIGNATURES)

This function calculates the ratio of the volume of the candle (`cdl_vol`) to the order amount.
Depending on the ratio, it determines if the trade should succeed and returns a boolean indicating the result along with the actual amount that can be filled.
"""
function _fill_happened(
    rng, amount, cdl_vol, depth=1; initial_amount=amount, max_depth=4, max_reduction=0.1
)
    # The higher the volume of the candle compared to the order amount
    # the more likely the trade will succeed
    Lang.@posassert amount cdl_vol depth initial_amount max_depth max_reduction
    if amount <= DFT(0.0)
        # Zero amount means trivially filled with zero amount
        return true, DFT(0.0)
    end
    if cdl_vol <= DFT(0.0)
        return false, DFT(0.0)
    end
    ratio = cdl_vol / amount
    if ratio > DFT(100.0)
        true, amount
    elseif ratio > DFT(10.0)
        # log10(ratio)/2: for ratio=100 -> log10(100)/2 = 1.0 (100%), ratio=10 -> log10(10)/2 = 0.5 (50%)
        # min with 1.0 ensures probability never exceeds 100%
        rand(rng) < min(DFT(1.0), log10(ratio) / DFT(2.0)), amount
    elseif depth < max_depth # Only try a small number of times with reduced amount
        reduced_amount = amount / DFT(2.0)
        if reduced_amount > initial_amount * max_reduction
            _fill_happened(rng, reduced_amount, cdl_vol, depth + 1; initial_amount)
        else
            false, DFT(0.0)
        end
    else
        false, DFT(0.0)
    end
end

@doc """ Executes a limit order at a particular time according to volume.

$(TYPEDSIGNATURES)

This function executes a limit order `o` at a given `date` for an asset `ii` based on the volume of the candle compared to the order amount. It checks if the trade should succeed and performs the trade if conditions are met.
"""
function limitorder_ifvol!(s::Strategy{Sim}, o::AnyLimitOrder, date, ii; kwargs...)
    ds = get(s.attrs, :sim_debug_state, nothing)
    !isnothing(ds) && (ds.vol_checks[] += 1)
    ans::Union{Nothing,Trade} = nothing
    cdl_vol = st.volumeat(ii, date)
    amount = unfilled(o)
    @deassert amount > DFT(0.0)
    if o isa AnyFOKOrder # check for full fill
        # FOK can only be filled with max amount, so use max_depth=1
        rng = s.attrs[:sim_rng]
        triggered, actual_amount = _fill_happened(rng, amount, cdl_vol; max_depth=1)
        if triggered
            @deassert amount == actual_amount
            ans = trade!(s, o, ii; price=o.price, date, actual_amount, kwargs...)
        else
            if cancel!(
                s, o, ii; err=NotMatched(o.price, priceat(s, o, ii, date), amount, cdl_vol)
            )
                ans = nothing
            end
        end
        @deassert !isqueued(o, s, ii)
    else
        # GTC and IOC can be partially filled so allow for amount reduction (max_depth=4)
        rng = s.attrs[:sim_rng]
        triggered, actual_amount = _fill_happened(
            rng, amount, cdl_vol; max_depth=4, max_reduction=DFT(0.1)
        )
        if triggered
            @deassert actual_amount > amount * DFT(0.1)
            ans = if o isa AnyPostOnlyOrder && o.date == date
                cancel!(s, o, ii; err=OrderCanceled(o))
                nothing
            else
                trade!(s, o, ii; price=o.price, date, actual_amount, kwargs...)
            end
        else
            # Cancel IOC orders if partially filled
            if o isa AnyIOCOrder &&
                !isfilled(ii, o) &&
                cancel!(s, o, ii; err=NotFilled(amount, cdl_vol))
                ans = nothing
            end
        end
        @deassert o isa AnyGTCOrder || !isqueued(o, s, ii)
    end
    ans
end