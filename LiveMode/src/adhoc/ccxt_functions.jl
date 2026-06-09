

function ccxt_orders_func!(a, exc::Exchange{ExchangeID{:bybit}})
    a[:live_orders_func] = if has(exc, :fetchOrder)
        fetch_func = first(exc, :fetchOrderWs, :fetchOrder)
        @assert has(exc, (:fetchOpenOrders, :fetchClosedOrders))
        fetch_open_func = first(exc, :fetchOpenOrdersWs, :fetchOpenOrders)
        fetch_closed_func = first(exc, :fetchClosedOrdersWs, :fetchClosedOrders)
        (ai; ids=(), side=BuyOrSell, kwargs...) -> begin
            sym = raw(ai)
            if isempty(ids)
                out = []
                @sync begin
                    @async append!(out, _fetch_orders(ai, fetch_open_func; side, kwargs...))
                    @async append!(out, _fetch_orders(ai, fetch_closed_func; side, kwargs...))
                end
            else
                out = []
                @sync for id in ids
                    @async push!(out, _execfunc(fetch_func, id, sym; kwargs...))
                end
            end
            out
        end
    else
        @warn "ccxt funcs: fetch orders not supported" exchange = nameof(exc)
    end
end

_phemex_ispending(o) =
    let info = isdict(o) ? get(o, "info", Dict{String,Any}()) : Dict{String,Any}()
        status = get(info, "execStatus", nothing)
        status isa AbstractString && occursin("Pending", string(status))
    end

@doc "Sets up the [`fetch_open_orders`](@ref) or [`fetch_closed_orders`](@ref) closure for the ccxt exchange instance. (phemex)"
function ccxt_open_orders_func!(a, exc::Exchange{ExchangeID{:phemex}}; open=true)
    names = _func_syms(open)
    orders_func = first(exc, names.ws, names.fetch)
    eid = typeof(exchangeid(exc))
    a[names.key] = if !isnothing(orders_func)
        if open
            (ai; kwargs...) -> begin
                ans = _fetch_orders(ai, orders_func; eid, kwargs...)
                @debug "open/closed orders phemex: " ans
                if isnothing(ans)
                    return []
                else
                    removefrom!(_phemex_ispending, ans)
                end
            end
        else
            open_names = _func_syms(true)
            open_orders_func = first(exc, open_names.ws, open_names.fetch)
            (ai; kwargs...) -> begin
                ot, ct = @sync begin
                    (@async _fetch_orders(ai, open_orders_func; eid, kwargs...)),
                    (@async _fetch_orders(ai, orders_func; eid, kwargs...))
                end
                canceled_ords = removefrom!(
                    _phemex_ispending,
                    @something(fetch(ot), [])
                )
                closed_ords = @something fetch(ct) []
                append!(closed_ords, canceled_ords)
                closed_ords
            end
        end
    else
        fetch_func = get(a, :live_orders_func, nothing)
        @assert !isnothing(fetch_func) "`live_orders_func` must be set before `live_$(oc)_orders_func`"
        eid = typeof(exchangeid(exc))
        pred_func = o -> string(resp_order_status(o, eid)) == "open"
        status_pred_func = if open
            (o) -> pred_func(o) && !_phemex_ispending(o)
        else
            !pred_func
        end
        (ai; kwargs...) -> begin
            out = []
            all_orders = fetch_func(ai; kwargs...)
            for o in all_orders
                status_pred_func(o) && push!(out, o)
            end
            out
        end
    end
end
