using .Executors: AnyLimitOrder

@doc """ Places a limit order and synchronizes the cash balance.

$(TYPEDSIGNATURES)

This function initiates a limit order through the `_live_limit_order` function.
Once the order is placed, it synchronizes the cash balance in the live strategy to reflect the transaction.
It returns the trade information once the transaction is complete.

"""
function call!(
    s::NoMarginStrategy{Live},
    ai,
    t::Type{<:AnyLimitOrder};
    amount,
    price=lastprice(s, ai, t),
    waitfor=Second(5),
    synced=true,
    skipchecks=false,
    kwargs...,
)::Union{<:Trade,Nothing,Missing}
    @timeout_start
    @lock ai begin
        order_kwargs = withoutkws(:fees; kwargs)
        trade = _live_limit_order(
            s, ai, t; skipchecks, amount, price, waitfor, synced, kwargs=order_kwargs
        )
        if synced && trade isa Trade
            live_sync_cash!(s, ai; since=trade.date, waitfor=@timeout_now)
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
    ai,
    t::Type{<:AnyMarketOrder};
    amount,
    waitfor=Second(5),
    synced=true,
    skipchecks=false,
    kwargs...,
)
    @timeout_start
    @lock ai begin
        order_kwargs = withoutkws(:fees; kwargs)
        trade = _live_market_order(
            s, ai, t; skipchecks, amount, synced, waitfor, kwargs=order_kwargs
        )
        if synced && trade isa Trade
            waitorder(s, ai, trade.order; waitfor=@timeout_now)
            live_sync_cash!(s, ai; since=trade.date, waitfor=@timeout_now)
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
    ai::AssetInstance,
    ::CancelOrders;
    t::Type{<:OrderSide}=BuyOrSell,
    waitfor=Second(10),
    confirm=false,
    synced=true,
    ids=(),
)
    @timeout_start
    @lock ai begin
        if !hasorders(s, ai, t) && !confirm
            @debug "call cancel orders: no local open orders" _module = LogCancelOrder ai t
            return true
        end
        watch_orders!(s, ai)
        if live_cancel(s, ai; ids, side=t, confirm)::Bool
            success = waitordclose(s, ai, @timeout_now; t)
            if success
                if synced
                    @debug "call cancel orders: syncing cash" ai t _module =
                        LogCancelOrder
                    live_sync_cash!(s, ai; waitfor=@timeout_now)
                end
            else
                @debug "call cancel orders: failed syncing open orders" ai t _module =
                    LogCancelOrder
                live_sync_open_orders!(s, ai, exec=true)
            end
            @debug "call cancel orders: " ai t success _module = LogCancelOrder
            success
        else
            @debug "call cancel orders: failed" ai t success _module = LogCancelOrder
            false
        end
    end
end
