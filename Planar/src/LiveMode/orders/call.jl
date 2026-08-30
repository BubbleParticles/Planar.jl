using .st: NoMarginStrategy, MarginStrategy
using .Executors: AnyLimitOrder, AnyMarketOrder

@doc """ Places a limit order and synchronizes the cash balance.

$(TYPEDSIGNATURES)

This function initiates a limit order through the `_live_limit_order` function.
Once the order is placed, it synchronizes the cash balance in the live strategy to reflect the transaction.
It returns the trade information once the transaction is complete.

"""
function call!(
    s::NoMarginStrategy{Live},
    ii,
    t::Type{<:AnyLimitOrder};
    amount,
    price=lastprice(s, ii, t),
    waitfor=Second(5),
    synced=true,
    skipchecks=false,
    kwargs...,
)::Union{<:Trade,Nothing,Missing}
    @timeout_start
    @lock ii begin
        order_kwargs = withoutkws(:fees; kwargs)
        trade = _live_limit_order(
            s, ii, t; skipchecks, amount, price, waitfor, synced, kwargs=order_kwargs
        )
        if synced && trade isa Trade
            live_sync_cash!(s, ii; since=trade.date, waitfor=@timeout_now)
        end
        trade
    end
end

@doc """ Places a limit order and synchronizes the cash balance (margin).

$(TYPEDSIGNATURES)

Same as `NoMarginStrategy` but for margin strategies.

"""
function call!(
    s::MarginStrategy{Live},
    ii,
    t::Type{<:AnyLimitOrder};
    amount,
    price=lastprice(s, ii, t),
    waitfor=Second(5),
    synced=true,
    skipchecks=false,
    kwargs...,
)::Union{<:Trade,Nothing,Missing}
    @timeout_start
    @lock ii begin
        order_kwargs = withoutkws(:fees; kwargs)
        trade = _live_limit_order(
            s, ii, t; skipchecks, amount, price, waitfor, synced, kwargs=order_kwargs
        )
        if synced && trade isa Trade
            live_sync_cash!(s, ii; since=trade.date, waitfor=@timeout_now)
        end
        trade
    end
end

@doc """ Places a market order and synchronizes the cash balance.

$(TYPEDSIGNATURES)

This function initiates a market order through the `_live_market_order` function.
Once the order is placed, it synchronizes the cash balance in the live strategy to reflect the transaction.
It returns the trade information once the transaction is complete.

"""
function call!(
    s::NoMarginStrategy{Live},
    ii,
    t::Type{<:AnyMarketOrder};
    amount,
    waitfor=Second(5),
    synced=true,
    skipchecks=false,
    kwargs...,
)
    @timeout_start
    @lock ii begin
        order_kwargs = withoutkws(:fees; kwargs)
        trade = _live_market_order(
            s, ii, t; skipchecks, amount, synced, waitfor, kwargs=order_kwargs
        )
        if synced && trade isa Trade
            waitorder(s, ii, trade.order; waitfor=@timeout_now)
            live_sync_cash!(s, ii; since=trade.date, waitfor=@timeout_now)
        end
        trade
    end
end

@doc """ Places a market order and synchronizes the cash balance (margin).

$(TYPEDSIGNATURES)

Same as `NoMarginStrategy` but for margin strategies.

"""
function call!(
    s::MarginStrategy{Live},
    ii,
    t::Type{<:AnyMarketOrder};
    amount,
    waitfor=Second(5),
    synced=true,
    skipchecks=false,
    kwargs...,
)
    @timeout_start
    @lock ii begin
        order_kwargs = withoutkws(:fees; kwargs)
        trade = _live_market_order(
            s, ii, t; skipchecks, amount, synced, waitfor, kwargs=order_kwargs
        )
        if synced && trade isa Trade
            waitorder(s, ii, trade.order; waitfor=@timeout_now)
            live_sync_cash!(s, ii; since=trade.date, waitfor=@timeout_now)
        end
        trade
    end
end

@doc """ Cancels all live orders of a certain type and synchronizes the cash balance.

$(TYPEDSIGNATURES)

This function cancels all live orders of a certain side (buy/sell) through the `live_cancel` function.
Once the orders are canceled, it waits for confirmation of the cancelation and then synchronizes the cash balance in the live strategy to reflect the cancelations.
It returns a boolean indicating whether the cancellation was successful.

"""
function call!(
    s::Strategy{Live},
    ii::InstrumentInstance,
    ::CancelOrders;
    t::Type{<:OrderSide}=BuyOrSell,
    waitfor=Second(10),
    confirm=false,
    synced=true,
    ids=(),
)
    @timeout_start
    @lock ii begin
        if !hasorders(s, ii, t) && !confirm
            @debug "call cancel orders: no local open orders" _module = LogCancelOrder ii t
            return true
        end
        watch_orders!(s, ii)
        if live_cancel(s, ii; ids, side=t, confirm)::Bool
            success = waitordclose(s, ii, @timeout_now; t)
            if success
                if synced
                    @debug "call cancel orders: syncing cash" ii t _module =
                        LogCancelOrder
                    live_sync_cash!(s, ii; waitfor=@timeout_now)
                end
            else
                @debug "call cancel orders: failed syncing open orders" ii t _module =
                    LogCancelOrder
                live_sync_open_orders!(s, ii, exec=true)
            end
            @debug "call cancel orders: " ii t success _module = LogCancelOrder
            success
        else
            @debug "call cancel orders: failed" ii t success _module = LogCancelOrder
            false
        end
    end
end
