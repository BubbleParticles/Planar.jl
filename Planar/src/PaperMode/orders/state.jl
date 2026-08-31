import .Executors: aftertrade!

@doc """ Cancels an order in PaperMode with a given error.

$(TYPEDSIGNATURES)

The function attempts to cancel the order by invoking the `cancel!` function with the given strategy, order, and asset.
If the order is associated with a task in the `:paper_order_tasks` attribute of the simulation, the task is marked as not alive and removed from the tasks.

"""
function Executors.cancel!(s::Strategy{Paper}, o::Order, ii::T; err::OrderError) where {T}
    try
        invoke(Executors.cancel!, Tuple{Strategy,Order,T}, s, o, ii; err)
    finally
        _remove_paper_order_task!(s, ii, o)
        volrelease!(s, ii; amount=o.amount)
    end
end

@doc """ Creates a paper market order with volume capped to the daily limit.

$(TYPEDSIGNATURES)

The function first checks if the order volume exceeds the daily limit using the `volumecap!` function.
If the volume is within the limit, it fetches the appropriate side of the orderbook using the `orderbook_side` function.
If the price is not provided, it sets the price to the first price in the orderbook.
Finally, it creates a simulated market order using the `create_sim_market_order` function.

"""
function create_paper_market_order(s, t, ii; amount, date, price, kwargs...)
    if volumecap!(s, ii; amount)
    else
        @debug "paper market order: overcapacity" ii = raw(ii) amount liq = _paper_liquidity(
            s, ii
        )
        return nothing
    end
    obside = try
        orderbook_side(ii, t)
    catch e
        e isa InterruptException && rethrow(e)
        @debug "paper market order: orderbook fetch failed" exception=e raw(ii) t
        Any[]
    end
    if isempty(obside)
        @debug "paper market order: empty OB (using provided price)" ii = raw(ii) t price
        # Fallback: if a finite price was supplied, create the order without an orderbook.
        # This keeps Paper Sim functional in unit tests / offline envs where the gateway
        # orderbook is unavailable. VWAP simulation is skipped; we trade at the given price.
        if isfinite(price) && !isnan(price) && price > 0
            o = create_sim_market_order(s, t, ii; amount, date, price, kwargs...)
            isnothing(o) && (volrelease!(s, ii; amount); return nothing)
            # empty obside sentinel: marketorder! will handle the fallback path
            return o, Any[]
        else
            @debug "paper market order: empty OB and no price" ii = raw(ii) t
            volrelease!(s, ii; amount)
            return nothing
        end
    end
    if isnan(price)
        price = first(obside)[1]
    end
    o = create_sim_market_order(s, t, ii; amount, date, price, kwargs...)
    o, obside
end
@doc """ Executes a market order in PaperMode.

$(TYPEDSIGNATURES)

The function executes the order by invoking the `from_orderbook` function with the given strategy, order, asset, and orderbook side.
If the trade is not successful, it cancels the order.
If the trade is successful, it starts tracking the order.

"""
function SimMode.marketorder!(s::PaperStrategy, o, ii; date, obside)
    # Empty obside means the orderbook was unavailable; fall back to a direct
    # sim fill at the order price (price was already validated in create_paper_market_order).
    if isempty(obside)
        trade = SimMode.trade!(s, o, ii; date, price=o.price, actual_amount=o.amount, slippage=false)
        if isnothing(trade)
            cancel!(s, o, ii; err=OrderCanceled(o))
            volrelease!(s, ii; amount=o.amount)
            return nothing
        else
            hold!(s, ii, o)
            return trade
        end
    end
    _, _, trade = from_orderbook(obside, s, ii, o; o.amount, date)
    if isnothing(trade)
        cancel!(s, o, ii; err=OrderCanceled(o))
        volrelease!(s, ii; amount=o.amount)
        nothing
    else
        hold!(s, ii, o)
        trade
    end
end

@doc """ Handles the actions to be taken after a trade in PaperMode.

$(TYPEDSIGNATURES)

The function logs the details of the trade including the date, strategy, order type, order side, amount, asset, price, and size.
It then invokes the `aftertrade!` function with the given strategy, asset, and order.
Finally, it updates the position with the trade.

"""
function aftertrade!(
    s::MarginStrategy{Paper}, ii::A, o::O, t=nothing
) where {A,O<:Union{AnyFOKOrder,AnyIOCOrder,AnyMarketOrder}}
    @info "($(t.date), $(nameof(s))) $(nameof(ordertype(t))) $(nameof(orderside(t))) $(t.amount) of $(t.order.asset) at $(t.price)($(t.size) $(ii.asset.qc))"
    invoke(aftertrade!, Tuple{Strategy,A,<:O,typeof(t)}, s, ii, o, t)
end

function aftertrade!(s::MarginStrategy{Paper}, ii::A, o::O, t=nothing) where {A,O<:AnyLimitOrder}
    invoke(aftertrade!, Tuple{Strategy,A,O,typeof(t)}, s, ii, o, t)
end
