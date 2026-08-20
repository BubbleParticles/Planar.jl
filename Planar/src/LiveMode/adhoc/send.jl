
function live_send_order(
    s::LiveStrategy{N,ExchangeID{:phemex}},
    ii::InstrumentInstance,
    t::Type{<:Order},
    args...;
    amount,
    price=lastprice(s, ii, t),
    stop_trigger=nothing,
    profit_trigger=nothing,
    stop_loss::Option{TriggerOrderTuple}=nothing,
    take_profit::Option{TriggerOrderTuple}=nothing,
    kwargs...,
) where {N}
    @price! ii stop_loss stop_trigger price profit_trigger take_profit
    if t <: ReduceOnlyOrder
        amount = min(ii.limits.amount.max, amount)
    else
        @amount! ii amount
    end
    invoke(live_send_order, Tuple{LiveStrategy,InstrumentInstance,Type{<:Order}}, s, ii, t, args...; amount, price, stop_trigger, profit_trigger, stop_loss, take_profit, kwargs...)
end

function create_order_func(exc::Exchange{ExchangeID{:binance}}, func, args...; params=LittleDict{Any,Any}(), kwargs...)
    postOnly = "postOnly"
    timeInForce = "timeInForce"
    if haskey(params, postOnly)
        if pop!(params, postOnly, false)
            params[timeInForce] = "PO"
        end
    end
    _execfunc(func, args...; params, kwargs...)
end
