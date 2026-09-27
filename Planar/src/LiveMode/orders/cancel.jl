import .Executors: cancel!
@doc """ Cancels live orders on an exchange.

$(TYPEDSIGNATURES)

The function cancels either all live orders or specified ones based on the side (buy/sell).
It can optionally confirm if the cancellation was successful.
If the confirmation fails or if any error occurs during the process, a warning is issued and the function returns false.

"""
function live_cancel(s, ii; ids=(), side=BuyOrSell, confirm=false, since=nothing)
    eid = exchangeid(ii)
    all = isempty(ids)
    (func, kwargs) = if side === BuyOrSell && all
        (cancel_all_orders, (;))
    else
        (
            cancel_orders,
            (;
                ids=if all
                    (resp_order_id(resp, eid) for resp in fetch_open_orders(s, ii; side))
                else
                    ids
                end,
                side,
            ),
        )
    end
    done = try
        resp = func(s, ii; kwargs...)
        if resp isa Exception
@error "live cancel: failed" ii = raw(ii) resp @caller
            false
        elseif isnothing(resp)
            # An empty response from the exchange is ambiguous: the cancel
            # may have succeeded, or the request may have been dropped.
            # Returning `true` here caused callers to treat a possibly-
            # failed cancel as success, leaving stale open orders on the
            # exchange. Report failure so the caller can retry or fetch.
            @error "live cancel: empty response (treating as failure)" ii = raw(ii) @caller
            false
        elseif isdict(resp)
            if resptobool(exchange(ii), resp)
                true
            else
@error "live cancel: failed (wrong status code)" ii = raw(ii) resp
                false
            end
        elseif islist(resp)
            true
        else
@error "live cancel: failed (unhandled response)" ii = raw(ii) resp
            false
        end
    catch e
        e isa InterruptException && rethrow(e)
@error "live cancel: failed (exception)" ii = raw(ii)
        @debug_backtrace LogCancelOrder
        return false
    end
    if done && confirm
        open_orders = fetch_open_orders(s, ii; since=if !isnothing(since)
            dtstamp(since)
        end)
        if side === BuyOrSell
            isempty(open_orders) || begin
@error "live cancel: confirm failed (both sides)"
                return false
            end
        else
            side_str = _ccxtorderside(side)
            for o in open_orders
                string(resp_order_side(o, eid)) == side_str && begin
@error "live cancel: confirm failed" side
                    return false
                end
            end
        end
    end
    done
end

function cancel!(s::LiveStrategy, o::Order, ii; err, kwargs...)
    if isqueued(o, s, ii) || ordertype(o) <: MarketOrderType
        decommit!(s, o, ii, true)
        delete!(s, ii, o)
        st.call!(s, o, err, ii)
        event!(ii, InstrumentEvent, :order_local_cancel, s; order=o, err)
    end
end
