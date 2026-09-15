using ..PaperMode.SimMode: _lev_value, leverage!, leverage, position!, singlewaycheck
using .Lang: splitkws
using .st: MarginStrategy, NoMarginStrategy
using .Executors: hasorders, orders, update_leverage!, CancelOrders
using .st: exchange
using .Executors.Instances: raw, MarginInstance
using .Instances: ishedged
using ..PaperMode.OrderTypes: postoside, BuyOrSell
using PlanarCore.OrderTypes: orderside, Buy, Sell
import .Executors: call!

@doc """ Updates leverage or places an order in a live trading strategy.

$(TYPEDSIGNATURES)

This function either updates the leverage of a position or places an order in a live trading strategy.
It first checks if the position is open or has pending orders.
If not, it updates the leverage on the exchange and then synchronizes the position.
If an order is to be placed, it checks for any open positions on the opposite side and places the order if none exist.
The function returns the trade or leverage update status.

"""
function Executors.call!(
    s::MarginStrategy{Live},
    ii::MarginInstance,
    lev,
    ::UpdateLeverage;
    pos::PositionSide,
    synced=false,
    atol=1e-1,
    force=false,
)::Bool
    @lock ii if isopen(ii, pos) || hasorders(s, ii, pos)
        @warn "call leverage: can't update leverage when position is open or has pending orders" ii s n_orders = orderscount(s, ii) isopen(ii, pos)
        false
    else
        new_lev = _lev_value(lev)
        since = TimeTicks.now()
        this_pos = position(ii, pos)
        prev_lev = leverage(this_pos)
        issameval = isapprox(prev_lev, new_lev; atol)
        # First update on exchange
        if (force || !issameval) &&
            leverage!(exchange(ii), new_lev, raw(ii); timeout=throttle(s))
            leverage!(this_pos, new_lev)
            event!(ii, LeverageUpdated(:leverage_updated, s, this_pos; from_value=prev_lev))
            if synced
                # wait for lev update from watcher
                live_position(s, ii, pos; since, synced=true, force)
                isapprox(leverage(ii, pos), new_lev; atol)
            else
                true
            end
        else
            issameval
        end
    end
end
@doc """ Checks for open positions on the opposite side in an isolated strategy.

$(TYPEDSIGNATURES)

This macro checks if there are any open positions on the opposite side in an isolated trading strategy.
If an open position is found, it issues a warning and returns `nothing`.
The check is performed for the current trade type `t` and the associated asset instance `ii`.

"""
macro isolated_position_check()
    ex = quote
        p = positionside(t)
        if !singlewaycheck(s, ii, t)
            @debug "call: double direction order in non hedged mode" ii position(ii) order_type =
                t
            return nothing
        end
        if !ishedged(ii)
            side_dict = get_positions(s, opposite(p))
            pup = get(side_dict, raw(ii), nothing)
            if !isnothing(pup)
                if !pup.read[]
                    waitsync(ii)
                end
                if pup.date >= timestamp(ii, opposite(p)) &&
                    !pup.closed[] &&
                    _ccxt_isposopen(pup.resp, exchangeid(ii))
                    @warn "call: double direction order in non hedged mode (from resp)" position(ii) order_type = t
                    @debug "call: isolated check" _module = LogPos resp = pup.resp
                    return nothing
                end
            end
        end
    end
    esc(ex)
end

_warnpos(p) = @warn "$p Orders are not allowed, other pos ($(opposite(p))) is still open."

@doc """ Executes a limit order in a live trading strategy.

$(TYPEDSIGNATURES)

This function executes a limit order in a live trading strategy, given a strategy `s`, an asset instance `ii`, and a trade type `t`.
It checks for open positions on the opposite side and places the order if none exist.
The function returns the trade or leverage update status.

"""
function Executors.call!(
    s::MarginStrategy{Live},
    ii::MarginInstance,
    t::Type{<:AnyLimitOrder};
    amount,
    price=lastprice(s, ii, t),
    waitfor=Second(5),
    skipchecks=false,
    synced=true,
    kwargs...,
)
    @lock ii begin
        skipchecks || @isolated_position_check
        @timeout_start
        order_kwargs = withoutkws(:fees; kwargs)
        trade = _live_limit_order(
            s, ii, t; skipchecks, amount, price, waitfor, synced, kwargs=order_kwargs
        )
        if synced && trade isa Trade
            @debug "call margin limit order: syncing" ii t
            waitsync(ii; since=trade.date, waitfor=@timeout_now)
            live_sync_position!(
                s, ii, posside(trade); force=true, since=trade.date, waitfor=@timeout_now
            )
        end
        trade
    end
end

@doc """ Executes a market order in a live trading strategy.

$(TYPEDSIGNATURES)

This function executes a market order in a live trading strategy, given a strategy `s`, an asset instance `ii`, and a trade type `t`.
It checks for open positions on the opposite side and places the order if none exist.
The function returns the trade or leverage update status.

"""
function Executors.call!(
    s::MarginStrategy{Live},
    ii::MarginInstance,
    t::Type{<:AnyMarketOrder};
    amount,
    price=lastprice(s, ii, t),
    waitfor=Second(5),
    skipchecks=false,
    synced=true,
    kwargs...,
)
    @lock ii begin
        skipchecks || @isolated_position_check
        @timeout_start
        order_kwargs = withoutkws(:fees; kwargs)
        trade = _live_market_order(
            s, ii, t; skipchecks, amount, price, synced, waitfor, kwargs=order_kwargs
        )
        if synced && trade isa Trade
            waitsync(ii, since=trade.date, waitfor=@timeout_now)
            live_sync_position!(
                s, ii, posside(trade); since=trade.date, waitfor=@timeout_now
            )
        end
        trade
    end
end

_close_order_bypos(::Short) = ShortMarketOrder{Buy}
_close_order_bypos(::Long) = MarketOrder{Sell}
function _posclose_cancel(s, ii, pside, waitfor)
    @debug "call pos close: cancel orders" _module = LogPosClose ii pside
    if hasorders(s, ii, pside)
        # Position-scoped cancel on the exchange side: ccxt `cancel_orders`
        # filters by ORDER side (buy/sell), so a single `postoside(pside)`
        # call only cancels one leg of this position (Long-Buy, leaving
        # Long-Sell reduce orders live, and vice versa). Cancel BOTH legs
        # that belong to this position; the opposite position's orders are
        # untouched because `orders(s, ii, pside, side)` filters by posside.
        ok = true
        for side in (Buy, Sell)
            isempty(collect(orders(s, ii, pside, side))) && continue
            ok &= call!(s, ii, CancelOrders(); t=side, synced=true, waitfor)
        end
        ok || @warn "call pos close: failed to cancel orders" ii pside
    end
end

function _posclose_maybesync(s, ii, pside, waitfor)
    @debug "call pos close: sync position" _module = LogPosClose ii pside
    @timeout_start
    update = live_position(s, ii, pside; since=timestamp(ii, pside) - Millisecond(1), waitfor=@timeout_now)
    if isnothing(update)
        # Indeterminate: the gateway dropped the fetch while the remote state
        # is unknown. Even when local is flat, the remote may still hold the
        # position — never report success here; the caller returns `false`
        # so the close is retried instead of falsely confirmed.
        @warn "call pos close: no position update (remote unknown)" ii pside isopen = isopen(ii, pside)
        return (update, false)
    end
    # ensure the last update is read
    if !(update.read[])
        @warn "call pos close: outdated position state (syncing)." amount = resp_position_contracts(
            update.resp, exchangeid(ii)
        )
        waitsync(ii; since=update.date, waitfor=@timeout_now)
        live_sync_position!(s, ii, pside, update)
    end
    return (update, false)
end

function _posclose_waitsync(s, ii, pside, waitfor)
    # Position-scoped wait: `hasorders(s, ii, pside)` covers both Buy/Sell
    # legs of this position, so the wait must too — a single-order-side
    # wait would return immediately while the position's reduce-leg orders
    # (Long-Sell / Short-Buy) are still pending, racing the close trade.
    if hasorders(s, ii, pside)
        for side in (Buy, Sell)
            isempty(collect(orders(s, ii, pside, side))) && continue
            if !waitordclose(s, ii, waitfor; t=side)
                @error "call pos close: orders still pending for position $pside" ii orderscount(s, ii, pside) committed(ii, pside)
            end
        end
    end
    # with no orders in flight the local state should be up to date
    return if !isopen(ii, pside)
        @warn "call pos close: not open locally" ii pside
        true
    else
        false
    end
end

function _posclose_amount(s, ii, pside; amount=nothing, kwargs...)
    # Prefer the exchange truth when a fresh position update is available:
    # local `cash(ii, pside)` can diverge mid-sync, and a wrong-size
    # reduce-only close leaves dust (partial close) or gets rejected
    # (over-size). The @deassert below is stripped in production, so verify.
    amt = if isnothing(amount)
        pup = live_position(s, ii, pside)
        if !isnothing(pup) && !pup.closed[]
            remote_amt = resp_position_contracts(pup.resp, exchangeid(ii))
            local_amt = abs(cash(ii, pside))
            if !isapprox(local_amt, remote_amt; rtol=1e-3)
                @warn "call pos close: local/remote amount mismatch, using remote" ii pside local_amt remote_amt
            end
            remote_amt
        else
            abs(cash(ii, pside))
        end
    else
        abs(amount)
    end
    @debug "call pos close: get amount" _module = LogPosClose ii pside amt
    _, this_kwargs = splitkws(:reduce_only, :tag; kwargs)
    return amt, this_kwargs
end

function _posclose_trade(s, ii; t, pside, amount, waitfor, this_kwargs)
    @debug "call pos close: trade" _module = LogPosClose ii pside t
    @timeout_start
    close_trade = call!(
        s, ii, t; amount, reduce_only=true, tag="position_close", waitfor, this_kwargs...
    )
    if close_trade isa Trade
        (close_trade.date, false)
    elseif isnothing(close_trade)
        # check sync again
        pup = live_position(s, ii, pside; force=true, waitfor=@timeout_now)
        (
            DateTime(0),
            if !isopen(ii, pside)
                @deassert isnothing(pup) || pup.closed[]
                true
            else
                @error "call pos close: failed to reduce position to zero" ii pside t
                false
            end,
        )
    else
        @warn "call pos close: closing order delay" orders = collect(
            values(s, ii, orderside(t))
        ) ii t
        (timestamp(ii, pside) + Millisecond(1), false)
    end
end
function _posclose_margin_warn(s, ii)
    # Warn-only: terminal close status is reported by the caller. Returning the
    # margin result as the close result would flip a fully-closed position to
    # `false` on a transient `marginmode!` failure.
    ok = ensure_marginmode(s, ii)
    ok || @warn "call pos close: margin mode mismatch" ii = raw(ii) mm = marginmode(ii)
    nothing
end
function _posclose_order(s, ii, pside, since, waitfor)
    @debug "call pos close: order" _module = LogPosClose ii pside
    @timeout_start
    if !waitposclose(s, ii, pside; waitfor=@timeout_now, force=true)
        @debug "call pos close: timedout" _module = LogPosClose pside ii
    end
    waitsync(ii; since, waitfor=@timeout_now)
    live_sync_position!(s, ii, pside; since, overwrite=true, waitfor=@timeout_now)
    if @lock ii isopen(ii, pside)
        pup = live_position(s, ii, pside; since, waitfor=@timeout_now)
        @debug "call pos close: still open (local) position" _module = LogPosClose since pside date = get(
            pup, :date, nothing
        )
        _posclose_margin_warn(s, ii)
        return false
    else
        _posclose_margin_warn(s, ii)
        return true
    end
end
function _posclose_lastcheck(s, ii, pside, t, since, waitfor)
    @debug "call pos close: last check" _module = LogPosClose ii pside
    @timeout_start
    # trade still pending
    if @lock ii isopen(ii, pside)
        waitsync(ii; since, waitfor=@timeout_now)
        waitsync(s; since, waitfor=@timeout_now())
        return if isopen(ii, pside)
            @error "call pos close: still open orders (not a market order?)" ii pside t
            _posclose_margin_warn(s, ii)
            false
        else
            _posclose_margin_warn(s, ii)
            true
        end
    else
        _posclose_margin_warn(s, ii)
        return true
    end
end

@doc """ Closes a leveraged position in a live trading strategy.

$(TYPEDSIGNATURES)

This function cancels any pending orders and checks the position status.
If the position is open, it places a closing trade and waits for it to be executed.
The function returns `true` if the position is successfully closed, `false` otherwise.

"""
function call!(
    s::MarginStrategy{Live},
    ii::MarginInstance,
    ::ByPos{P},
    date,
    ::PositionClose;
    t=_close_order_bypos(P()),
    waitfor=Second(15),
    kwargs...,
) where {P<:PositionSide}
    @lock ii begin
        pside = P()
        @timeout_start

        # cancel standing orders
        _posclose_cancel(s, ii, t, pside, @timeout_now)
        # `_posclose_maybesync` never reports success on a missing remote
        # update (indeterminate): fall through to the local checks below;
        # terminal returns reflect local flatness (`!isopen`).
        update, isclosed = _posclose_maybesync(s, ii, pside, @timeout_now)
        if isclosed
            _posclose_margin_warn(s, ii)
            return !isopen(ii, pside)
        end
        # ensure no more orders are pending and return if pos is closed
        if _posclose_waitsync(s, ii, pside, @timeout_now)
            _posclose_margin_warn(s, ii)
            return !isopen(ii, pside)
        end
        # if still open, close manually with a reduce only order
        # get the amount necessary to close the position
        amount, this_kwargs = _posclose_amount(s, ii, pside; kwargs)
        if iszero(amount)
            # Position closed after last check
            _posclose_margin_warn(s, ii)
            return !isopen(ii, pside)
        end
        since, isclosed = _posclose_trade(
            s, ii; t, pside, amount, waitfor=@timeout_now(), this_kwargs
        )
        # another check for close in case of failing trade
        if isclosed
            _posclose_margin_warn(s, ii)
            return !isopen(ii, pside)
        end
        # trade exec success, wait for completion
        # Scope the wait to the close order's side: the default `BuyOrSell`
        # wait would burn the shared `waitfor` on the opposite position's
        # orders in hedged mode (deliberately preserved), then fall into
        # `_posclose_lastcheck` even though this position's close succeeded.
        if waitordclose(s, ii, @timeout_now; t=orderside(t))
            # terminal check after closing trade
            _posclose_order(s, ii, pside, since, @timeout_now)
        else
            # closing trade still pending
            _posclose_lastcheck(s, ii, pside, t, since, @timeout_now)
        end
    end
end

@doc "Closes a leveraged position."
function call!(
    s::NoMarginStrategy{Live},
    ii::NoMarginInstance,
    side::ByPos,
    date,
    ::PositionClose;
    kwargs...,
)::Bool
    # Same contract as Sim/Paper: cancel pending spot orders so a
    # "close all" never reports success while orders stay live.
    @deassert !isopen(ii, side) "NoMarginStrategy should not have open positions"
    call!(s, ii, CancelOrders(); t=BuyOrSell)
end
@doc "Closes all strategy positions (live)."
function call!(
    s::MarginStrategy{Live},
    side::ByPos,
    date,
    ::PositionClose;
    kwargs...,
)
    # Snapshot: single-close syncs delete from `s.holdings` on last-side
    # close — same mutation hazard as Sim/Paper bulk close.
    LittleDict(
        ii => call!(s, ii, side, date, PositionClose(); kwargs...) for ii in collect(s.holdings)
    )
end
@doc "Closes all strategy positions (live, no margin)."
function call!(
    s::NoMarginStrategy{Live},
    side::ByPos,
    date,
    ::PositionClose;
    kwargs...,
)
    LittleDict(
        ii => call!(s, ii, side, date, PositionClose(); kwargs...) for ii in s.universe
    )
end
