using .Executors: AnyLimitOrder, committment, unfillment
using .PaperMode: create_sim_limit_order
using .PaperMode.SimMode: construct_order_func
using .Executors.Instruments: AbstractInstrument
using .OrderTypes: ordertype, MarketOrderType, GTCOrderType, ForcedOrderType, Order, Trade
using .Lang: filterkws

function isactive(s::Strategy, ii::InstrumentInstance, resp, eid::EIDType; fetched=false)
    isopen, status = _ccxtisopen(resp, eid, Val(:status))
    hasfill = resp_order_filled(resp, eid) > 0.0
    oid = resp_order_id(resp, eid, String)
    hasid = !isempty(oid)

    @debug "create order: isopen" _module = LogCreateOrder isopen hasfill oid hasid
    if !isopen && !hasfill && !hasid
        @warn "create order: refusing" ii oid isopen hasfill hasid
        return false, resp
    else
        status = resp_order_status(resp, eid)
        if (!_ccxtisstatus(resp, eid) && !fetched)
            if isprocessed_order(s, ii, oid)
                fetched_resp = fetch_orders(s, ii; ids=(oid,))
                if hasels(fetched_resp)
                    this_resp = first(fetched_resp)
                    return if resp_order_id(this_resp, eid) != oid
                        @error "create order: wrong id" oid this_resp
                        false, this_resp
                    else
                        isactive(s, ii, this_resp, eid; fetched=true)
                    end
                else
                    @debug "create order: order not found on exchange (canceled?)" _module = LogCreateOrder ii oid hasfill hasid fetched_resp
                    return false, resp
                end
            else
                @warn "create order: unknown status" ii oid hasfill hasid resp status
                return hasid, resp
            end
        elseif _ccxtisstatus(status, "canceled", "rejected", "expired") || fetched
            @warn "create order: $status" ii oid hasfill hasid
            return false, resp
        end
    end
    return true, resp
end

@doc """ Creates a live order.

$(TYPEDSIGNATURES)

This function is designed to create a live order on a given strategy and asset instance.
It verifies the response from the exchange and constructs the order with the provided parameters.
If the order fails to construct and is marked as synced, it attempts to synchronize the strategy and universe cash, and then retries order creation.
Finally, if the order is marked as active, the function sets it as the active order.
"""
function _create_live_order(
    s::LiveStrategy,
    ii::InstrumentInstance,
    resp;
    t,
    price,
    amount,
    synced=true,
    activate=true,
    skipcommit=false,
    kwargs...,
)
    if isnothing(resp)
        @warn "create order: empty response ($(raw(ii)))"
        return nothing
    end

    eid = side = type = loss = profit = date = id = nothing
    try
        eid = exchangeid(ii)
        status = resp_order_status(resp, eid)
        side = @something _orderside(resp, eid) orderside(t)
        @debug "create order: parsing" _module = LogCreateOrder status filled =
            resp_order_filled(resp, eid) > 0.0 id = resp_order_id(resp, eid) side
        isopen_flag, resp = isactive(s, ii, resp, eid)
        if !isopen_flag
            return nothing
        end
        this_order_type(ot) = begin
            pos = @something posside(t) posside(ii) Long()
            Order{ot{side},<:AbstractInstrument,<:ExchangeID,typeof(pos)}
        end
        type = let ot = ordertype_fromccxt(resp, eid)
            if isnothing(ot)
                if t isa Type{<:Order}
                    t
                else
                    @something ordertype_fromtif(resp, eid) (
                        if _ccxtisstatus(resp, "closed", eid)
                            MarketOrderType
                        else
                            GTCOrderType
                        end |> this_order_type
                    )
                end
            else
                this_order_type(ot)
            end
        end
        amount = resp_order_amount(resp, eid, amount, Val(:amount); ii)
        price = resp_order_price(resp, eid, price, Val(:price); ii)
        loss = resp_order_loss_price(resp, eid)
        profit = resp_order_profit_price(resp, eid)
        date = let this_date = @something pytodate(resp, eid) TimeTicks.now()
            # ensure order pricetime doesn't clash
            while haskey(s, ii, (; price, time=this_date), side)
                this_date += Millisecond(1)
            end
            this_date
        end
        id = @something _orderid(resp, eid) begin
            @warn "create order: missing id (default to pricetime hash)" ii = raw(ii) s = nameof(
                s
            )
            string(hash((price, date)))
        end
    catch e
        e isa InterruptException && rethrow(e)
        @error "create order: parsing failed" resp
        @debug_backtrace LogCreateOrder
        return nothing
    end
    o = let f = construct_order_func(type)
        function create(; skipcommit)
            @debug "create order: local" _module = LogCreateOrder ii id amount date type price leverage(
                ii
            ) loss profit @caller(20)
            f(
                s,
                type,
                ii;
                id,
                amount,
                date,
                type,
                price,
                loss,
                profit,
                skipcommit,
                kwargs...,
            )
        end
        o = create(; skipcommit)
        if isnothing(o) && synced
            o = findorder(s, ii; resp, side)
            if isnothing(o)
                @warn "create order: can't construct (back-tracking)" id = resp_order_id(
                    resp, eid
                ) resp_order_status(resp, eid) ii = raw(ii) cash(ii) s = nameof(s) t
            end
        end
        if isnothing(o)
            @debug "create order: retrying (no commits)" _module = LogCreateOrder ii = raw(ii) side = posside(t)
            o = @inlock ii create(skipcommit=true)
        end
        # Fallback: if still nothing but exchange reports filled/closed, construct a minimal Order bypassing cost checks
        if isnothing(o) && (status == "closed" || resp_order_filled(resp, eid) > 0.0)
            try
                @warn "create order: fallback constructing order from exchange response" id = id ii = raw(ii) resp = resp
                # compute committed and unfilled
                # Prefer exchange-provided cost when available for closed/filled orders
                resp_cost = try resp_order_cost(resp, eid) catch e; e isa InterruptException && rethrow(e); nothing end
                if !isnothing(resp_cost) && resp_cost != 0.0
                    committed_val = resp_cost
                else
                    committed_val = try
                        committment(type, ii, price, amount)
                    catch err
                        err isa InterruptException && rethrow(err)
                        @warn "create order: committment failed in fallback" err = err
                        # fallback to price*abs(amount)
                        price * abs(amount)
                    end
                end
                committed_ref = Ref(committed_val)
                unfilled_ref = Ref(unfillment(type, amount))
                attrs = (take = profit, stop = loss, committed = committed_ref, unfilled = unfilled_ref, trades = Trade[])
                o = Order(ii, type; date = date, price = price, amount = amount, id = id, attrs = attrs)
                push!(s, ii, o)
            catch err
                err isa InterruptException && rethrow(err)
                @warn "create order: fallback construction failed" err = err
            end
        end
        o
    end
    if isnothing(o)
        @error "create order: failed to sync" id ii = raw(ii) cash(ii) amount s = nameof(s) type
        @debug "create order: failed sync response" _module = LogCreateOrder resp
        return nothing
    elseif activate
        @debug "create order: activating order" _module = LogCreateOrder id resp_order_status(resp, eid) resp_order_filled(resp, eid) resp_order_remaining(resp, eid) resp_order_type(resp, eid)
        state = set_active_order!(s, ii, o; ap=resp_order_average(resp, eid))
        # Perform a trade if the order has been filled instantly
        function not_filled()
            !isequal(ii, resp_order_filled(resp, eid), filled_amount(o), Val(:amount))
        end
        if not_filled()
            @debug "create order: scheduling emulation" _module = LogCreateOrder resp_order_filled(resp, eid) filled_amount(o) not_filled()
            func() =
                if not_filled()
                    t = @inlock ii emulate_trade!(s, o, ii; state.average_price, resp)
                end
            sendrequest!(ii, resp_order_timestamp(resp, eid), func)
        end
    end
    event!(
        ii,
        InstrumentEvent,
        :order_created,
        s;
        order=o,
        req_type=t,
        req_price=price,
        req_amount=amount,
    )
    @debug "create order: done" _module = LogCreateOrder committed(o) o.amount ordertype(o)
    return o
end

@doc """ Sends and constructs a live order.

$(TYPEDSIGNATURES)

This function sends a live order using the provided parameters and constructs it based on the response received.

"""
function _create_live_order(
    s::LiveStrategy,
    ii::InstrumentInstance,
    args...;
    t,
    amount,
    price=lastprice(s, ii, t),
    exc_kwargs=(),
    skipchecks=false,
    kwargs...,
)
    @debug "create order: sending request" _module = LogCreateOrder ii t price amount f = @caller
    resp = try
        live_send_order(
            s,
            ii,
            t,
            args...;
            skipchecks,
            amount,
            price,
            withoutkws(:date; kwargs=exc_kwargs)...,
        )
    catch e
        e isa InterruptException && rethrow(e)
        @debug_backtrace LogCreateOrder
        @error "create order: send failed" ii t amount price
        return nothing
    end
    if resp isa Exception
        @error "create order: send failed" ii t amount price exception = resp
    else
        @debug "create order: after request" _module = LogCreateOrder ii t price amount f = @caller() resp
        _create_live_order(s, ii, resp; amount, price, t, kwargs...)
    end
end

function create_live_order(s, ii, args...; waitfor=Second(15), kwargs...)
    ans = Ref{Union{Order,Nothing,Exception}}(nothing)
    func() = (ans[] = (@inlock ii _create_live_order(s, ii, args...; kwargs...)))
    sendrequest!(ii, TimeTicks.now(), func, waitfor)
    ans[]
end
