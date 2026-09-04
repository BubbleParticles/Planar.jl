import .PaperMode: SimMode
using .Executors: filled_amount, orderscount, orders
using .Executors: isfilled as isorder_filled
using .Instances: ltxzero, gtxzero
using .OrderTypes: ReduceOnlyOrder
using ...PaperMode.SimMode: @maketrade

# TODO: `watch_orders!` and `watch_trades!` currently operate on one symbol only.
# This could be improved by batching new tasks called within a short amount time
# and use the `...ForSymbols` functions from ccxt.

"""
Initialize necessary tasks and variables for watching orders.
"""
function initialize_watch_tasks!(s::LiveStrategy, ii)
    stop_delay = Ref(s.watch_idle_timeout)
    return stop_delay
end

"""
Defines the functions used for watching orders based on the exchange capabilities.
"""
function define_loop_funct(s::LiveStrategy, ii; exc_kwargs=(;))
    watch_func = first(exchange(ii), :watchOrders)
    _, func_kwargs = splitkws(:since; kwargs=exc_kwargs)
    sym = raw(ii)
    has_watch_orders = !isnothing(first(exchange(ii), :watchOrders, :watchOrdersForSymbols))
    iswatch = has_watch_orders && s[:is_watch_orders]
    if iswatch
        init_handler() = begin
            buf = Vector{Any}()
            buf_subject = Rocket.Subject(Any)
            sizehint!(buf, s[:live_buffer_size])
            task_local_storage(:buf, buf)
            task_local_storage(:buf_subject, buf_subject)
            since = dtstamp(attr(s, :is_start, TimeTicks.now()))
            h = @lget! task_local_storage() :handler begin
                coro_func() = watch_func(sym; since, func_kwargs...)
                errors = Ref(0)
                f_push(v) = begin
                    push!(buf, v)
                    Rocket.next!(buf_subject, v)
                    maybe_backoff!(errors, v)
                end
                stream_handler(coro_func, f_push)
            end
            start_handler!(h)
        end
        function get_from_buffer()
            buf = let b = get(@something(current_task().storage, (;)), :buf, nothing)
                if isnothing(b)
                    init_handler()
                    task_local_storage(:buf)
                else
                    b
                end
            end
            buf_subject = task_local_storage(:buf_subject)
            result = Ref{Any}()
            Rocket.subscribe!(buf_subject |> Rocket.take(1), Rocket.lambda(
                on_next = v -> result[] = v,
                on_error = e -> @warn("orders watcher: buf subscription error", exception = (e, catch_backtrace()))
            ))
            while !isassigned(result)
                !@istaskrunning() && return
            end
            result[]
        end
        (get_from_buffer, true)
    else
        since = Ref(attr(s, :is_start, TimeTicks.now()))
        since_start = since[]
        eid = exchangeid(ii)
        function get_from_call()
            since[] == since_start || sleep(1)
            resp = fetch_orders(s, ii; since=dtstamp(since[]) + 1, func_kwargs...)
            if islist(resp) && !isempty(resp)
                since[] = @something pytodate(resp[-1], eid) TimeTicks.now()
            end
            resp
        end
        (get_from_call, false)
    end
end

"""
Manages the order updates by continuously fetching and processing new orders.
"""
function manage_order_updates!(s::LiveStrategy, ii, stop_delay, loop_func, iswatch)
    events = get_events(s)
    asset_cond = condition(ii)
    strategy_cond = condition(s)
    orders_byid = active_orders(ii)
    idle_timeout = Second(s.watch_idle_timeout)
    try
        while @istaskrunning()
            try
                @debug "watchers orders: loop func" _module = LogWatchOrder
                updates = loop_func()
                send_orders!(
                    s, ii, updates; events, orders_byid, asset_cond, strategy_cond, iswatch
                )
                stop_delay[] = idle_timeout
            catch e
                handle_order_updates_errors!(e, ii, iswatch)
            end
        end
    finally
        h = get(task_local_storage(), :handler, nothing)
        if !isnothing(h)
            stop_handler!(h)
        end
    end
end

"""
Processes updates for orders, including fetching new orders and updating existing ones.
"""
function send_orders!(s, ii, updates; orders_byid, events, asset_cond, strategy_cond, iswatch)
    if updates isa Exception
        if updates isa InterruptException
            throw(updates)
        else
            @ifdebug (updates isa InvalidStateException) ||
                @debug "watch orders: fetching error" _module = LogWatchOrder ii updates
            if !iswatch
                sleep(1)
            end
        end
    else
        for resp in updates
            date = resp_order_timestamp(resp, exchangeid(ii))
            func = () -> handle_order!(s, ii, orders_byid, resp)
            sendrequest!(ii, date, func; events)
            Rocket.next!(asset_cond, nothing)
            Rocket.next!(strategy_cond, nothing)
        end
    end
end

"""
Handles errors that occur during the order watching process.
"""
function handle_order_updates_errors!(e, ii, iswatch)
    if e isa InterruptException || e isa InvalidStateException
        rethrow(e)
    else
        @error "watch orders: error (task termination?)" exception = (e, catch_backtrace()) _module = LogWatchOrder raw(ii)
    end
    if !iswatch
        sleep(1)
    end
end

"""
Monitors conditions for stopping the watch tasks and performs cleanup.
"""
function monitor_stop_conditions!(s::LiveStrategy, ii, task, stop_delay, tasks)
    task_local_storage(:sleep, 10)
    task_local_storage(:running, true)
    cond = task.storage[:notify]
    sub = Rocket.subscribe!(cond, Rocket.lambda(
        on_next = _ -> begin
            @istaskrunning() || return
            sleep(stop_delay[])
            stop_delay[] = Second(0)
            @inlock ii if orderscount(s, ii) == 0 && !isactive(s, ii)
                task_local_storage(:running, false)
                try
                    @debug "Stopping orders watcher for $(raw(ii))@($(nameof(s)))" _module =
                        LogWatchOrder current_task()
                    @lock tasks.lock begin
                        stop_watch_orders!(s, ii)
                        if hasmytrades(exchange(ii))
                            @debug "Stopping trades watcher for $(raw(ii))@($(nameof(s)))" _module =
                                LogWatchTrade
                            stop_watch_trades!(s, ii)
                        end
                    end
                finally
                    Rocket.unsubscribe!(sub)
                end
            end
        end,
        on_error = e -> @warn("orders watcher: stop condition error", exception = (e, catch_backtrace()))
    ))
end
function watch_orders!(s::LiveStrategy, ii; exc_kwargs=(;))
    @debug "watch orders: get task" ii islocked(s) _module = LogTasks2
    tasks = asset_tasks(ii)
    @debug "watch orders: locking" ii islocked(s) _module = LogTasks2
    @lock tasks.lock begin
        @deassert tasks.byname === asset_tasks(ii).byname
        let task = asset_orders_task(tasks.byname)
            if istaskrunning(task)
                @debug "watch orders: task running" ii islocked(s) _module = LogTasks2
                return task
            end
        end
        # Call the top-level functions
        stop_delay = initialize_watch_tasks!(s, ii)
        loop_func, iswatch = define_loop_funct(s, ii; exc_kwargs)
        task = @start_task IdDict() manage_order_updates!(
            s, ii, stop_delay, loop_func, iswatch
        )
        stop_task = @start_task IdDict() begin
            try
                monitor_stop_conditions!(s, ii, task, stop_delay, tasks)
            catch e
                e isa InterruptException && rethrow(e)
                @error "watch orders: stop condition monitor failed" ii exception = (e, catch_backtrace())
            end
        end

        tasks.byname[:orders_task] = task
        tasks.byname[:orders_stop_task] = stop_task
        @debug "watch orders: new task" ii islocked(s) _module = LogTasks2
        return task
    end
end

asset_orders_task(tasks) = get(tasks, :orders_task, nothing)
@doc """ Retrieves the orders task for a given asset instance.

$(TYPEDSIGNATURES)

This function retrieves the orders task for a given asset instance `ii` from the live strategy `s`. The orders task is responsible for watching and updating orders for the asset instance.

"""
asset_orders_task(s, ii) = @something asset_task(ii, :orders_task) watch_orders!(s, ii)
asset_orders_stop_task(tasks) = get(tasks, :orders_stop_task, nothing)
@doc """ Retrieves the orders stop task for a given asset instance.

$(TYPEDSIGNATURES)

This function retrieves the orders stop task for a given asset instance `ii` from the live strategy `s`. The orders stop task is responsible for stopping the watching and updating of orders for the asset instance.

"""
asset_orders_stop_task(s, ii) = asset_orders_stop_task(asset_tasks(ii).byname)

@doc """ Generates a unique enough hash for an order. """
function _order_kv_hash(resp, eid::EIDType)
    p1 = resp_order_price(resp, eid, Any)
    p2 = resp_order_timestamp(resp, eid, Any)
    p3 = resp_order_stop_price(resp, eid)
    p4 = resp_order_trigger_price(resp, eid)
    p5 = resp_order_amount(resp, eid, Any)
    p6 = resp_order_cost(resp, eid, Any)
    p7 = resp_order_average(resp, eid, Any)
    p8 = resp_order_filled(resp, eid, Any)
    p9 = resp_order_remaining(resp, eid, Any)
    p10 = resp_order_status(resp, eid)
    p11 = resp_order_loss_price(resp, eid)
    p12 = resp_order_profit_price(resp, eid)
    p13 = resp_order_lastupdate(resp, eid)
    hash((p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11, p12, p13))
end

@doc """ Stops the orders watcher for an asset instance. """
function stop_watch_orders!(s::LiveStrategy, ii)
    waitfor = attr(s, :live_stop_timeout, Second(3))
    @timeout_start
    tasks = (asset_orders_task(s, ii), asset_orders_stop_task(s, ii))
    for task in tasks
        stop_task(task)
    end
    for task in tasks
        if !istaskdone(task)
            sto = task.storage
            if !isnothing(sto)
                sub = get(sto, :buf_subject, nothing)
                if !isnothing(sub)
                    Rocket.complete!(sub)
                end
            end
            this_task = task
            waitforcond(() -> !istaskdone(this_task), @timeout_now())
            if !istaskdone(this_task)
                kill_task(this_task)
            end
        end
    end
end

@doc """ Generates a unique enough hash for an order, preferably based on the last update, or the order info otherwise. """
order_update_hash(resp, eid) = begin
    last_update = resp_order_lastupdate(resp, eid)
    if isnothing(last_update)
        info = resp_order_info(resp, eid)
        if isnothing(info)
            _order_kv_hash(resp, eid)
        else
            hash(info)
        end
    else
        hash(last_update)
    end
end

@doc """ Updates an existing order in the system.

$(TYPEDSIGNATURES)

This function updates the state of an order in the system based on the new information received.
It locks the state and updates the hash of the order.
If the order is still open, it emulates the trade.
If the order is filled or not open anymore, it finalizes the order, waits for trades to be processed if necessary, and removes it from the active orders map.
If the order did not complete, it sends an error and cancels the order.
"""
function update_order!(s, ii, eid; resp, state)
    @debug "update ord: locking state" _module = LogWatchOrder id = state.order.id isownable(
        ii.lock
    ) isownable(state.lock) f = @caller()
    @inlock ii @lock state.lock begin
        @debug "update ord: locked" _module = LogWatchOrder id = state.order.id islocked(ii)
        this_hash = order_update_hash(resp, eid)
        state.update_hash[] == this_hash && return nothing
        # always update hash on new data
        state.update_hash[] = this_hash
        # only emulate trade if trade watcher task
        # is not running
        mytrades_flag = hasmytrades(exchange(ii))
        if !mytrades_flag
            @debug "update ord: emulate trade" _module = LogWatchOrder ii isownable(ii.lock) side = posside(
                state.order
            ) id = state.order.id
            if isopen(ii, state.order)
                t = emulate_trade!(s, state.order, ii; state.average_price, resp)
                @debug "update ord: emulated trade" _module = LogWatchOrder trade = t id =
                    state.order.id
            end
        end
        # if order is filled remove it from the task orders map.
        # Also remove it if the order is not open anymore (closed, canceled, expired, rejected...)
        order_open = _ccxtisopen(resp, eid)
        order_closed = _ccxtisclosed(resp, eid)
        order_trades = trades(state.order)
        order_filled = isorder_filled(ii, state.order)

        if order_filled || !order_open
            # Wait for trades to be processed if trades are not emulated
            @debug "update ord: finalizing" _module = LogWatchOrder id = state.order.id is_synced = isorder_synced(
                state.order, ii, resp
            ) n_trades = length(order_trades) last_trade = if isempty(order_trades)
                nothing
            else
                last(order_trades).date
            end resp_date = pytodate(resp, exchangeid(ii)) local_filled = filled_amount(
                state.order
            ) resp_filled = resp_order_filled(resp, eid) local_trades = length(
                trades(state.order)
            ) remote_trades = length(resp_order_trades(resp, eid)) status = resp_order_status(
                resp, eid
            )

            if mytrades_flag
                trades_count = length(order_trades)
                if (order_filled && trades_count == 0) ||
                    !isorder_synced(state.order, ii, resp)
                    @debug "update ord: waiting for trade events" _module = LogWatchOrder id =
                        state.order.id
                    reschedule() = begin
                        func = () -> update_order!(s, ii, eid; resp, state)
                        date = resp_order_timestamp(resp, eid)
                        sendrequest!(ii, date, func)
                    end
                    if pending_trades(ii) > 0
                        @debug "update ord: waiting for trade events" _module = LogWatchOrder id =
                            state.order.id
                        reschedule()
                        return
                    elseif length(order_trades) == trades_count
                        t = @inlock ii if isopen(ii, state.order)
                            @warn "update ord: falling back to emulation." locked = islocked(
                                ii
                            ) trades_count
                            @debug "update ord: emulating trade" _module = LogWatchOrder id =
                                state.order.id
                            t = emulate_trade!(
                                s, state.order, ii; state.average_price, resp
                            )
                            @debug "update ord: emulation done" _module = LogWatchOrder trade =
                                t id = state.order.id
                            t
                        end
                    end
                end
            end
            # Order did not complete, send an error
            if !order_closed
                cancel!(
                    s,
                    state.order,
                    ii;
                    err=OrderFailed(resp_order_status(resp, eid, String)),
                )
            else
                event!(
                    ii, InstrumentEvent, :order_closed, s; order=state.order, state.average_price
                )
            end
            @debug "update ord: de activating order" _module = LogWatchOrder id =
                state.order.id ii = raw(ii) order_filled
            clear_order!(s, ii, state.order)
            @ifdebug if hasorders(s, ii, state.order.id)
                @warn "update ord: order should already have been removed from local state, \
                possible emulation problem" id = state.order.id order_trades = trades(
                    state.order
                )
            end
        end
    end
    @debug "update ord: handled" _module = LogWatchOrder ii id = state.order.id filled = filled_amount(
        state.order
    ) f = @caller(10)
    Rocket.next!(asset_orders_task(s, ii).storage[:notify], nothing)
end

function _default_ordertype(islong::Bool, bs::BySide, args...)
    oside = orderside(bs)
    if islong
        MarketOrder{oside}
    else
        ShortMarketOrder{opposite(oside)}
    end
end
function _default_ordertype(s, ii::MarginInstance, resp)
    flag = islong(ii)
    oside = if resp_order_reduceonly(resp, exchangeid(ii))
        ifelse(flag, Sell, Buy)
    else
        ifelse(flag, Buy, Sell)
    end
    _default_ordertype(flag, oside, resp)
end
_default_ordertype(s, ii::NoMarginInstance, _) = MarketOrder{cash(ii) > 0.0 ? Sell : Buy}

@doc """ Re-activates a previously active order.

$(TYPEDSIGNATURES)

This function attempts to re-activate an order that was previously active in the system.
If the order is still open, it updates the order state.
If the order cannot be found or re-created, it cancels the order from the exchange and removes it from the local state if present.

"""
function re_activate_order!(s, ii, id; eid, resp)
    function docancel(o=nothing)
        @error "reactivate ord: could not re-create order, cancelling from exchange" id exc = nameof(
            exchange(ii)
        )
        live_cancel(s, ii; ids=(id,), confirm=false)
        if o isa Order && hasorders(s, ii, o.id)
            cancel!(
                s,
                o,
                ii;
                err=OrderFailed("Dangling order $id found in local state ($(raw(ii)))."),
            )
        end
    end

    o = findorder(s, ii; resp, id)
    # This should practically never happen
    if o isa Order && isopen(ii, o)
        state = set_active_order!(s, ii, o)
        @warn "reactivate ord: re-activation done" id exc = nameof(exchange(ii))
        if state isa LiveOrderState
            update_order!(s, ii, eid; resp, state)
        else
            docancel(o)
        end
    else
        @warn "reactivate order: re-creating" _module = LogCreateOrder id resp
        o = create_live_order(
            s,
            ii,
            resp;
            t=_default_ordertype(s, ii, resp),
            price=missing,
            amount=missing,
            synced=false,
            tag="reactivate",
        )
        if o isa Order
            state = get_order_state(active_orders(ii), o.id; s, ii)
            if !(state isa LiveOrderState)
                docancel(o)
            end
        else
            docancel()
        end
    end
end

@doc "Stores an order in the recently orders cache."
record_order_update!(s::LiveStrategy, ii, resp) =
    let lru = recent_orders(s, ii)
        @debug "record order update: " _module = LogWatchOrder lru = typeof(lru) order_update_hash(
            resp, exchangeid(ii)
        )
        lru[order_update_hash(resp, exchangeid(ii))] = nothing
    end
function isprocessed_order_update(s::LiveStrategy, ii, resp)
    order_update_hash(resp, exchangeid(ii)) ∈ keys(recent_orders(s, ii))
end

@doc """Manages the lifecycle of an order event.

$(TYPEDSIGNATURES)

The function extracts an order id from the `resp` object and based on the status of the order, it either updates, re-activates, or cancels the order.
"""
function handle_order!(s, ii, orders_byid, resp)
    try
        eid = exchangeid(ii)
        id = resp_order_id(resp, eid, String)
        @debug "handle ord: processing" _module = LogWatchOrder id resp
        @inlock ii begin
            if isprocessed_order(s, ii, id) || isprocessed_order_update(s, ii, resp)
                return nothing
            end
            record_order_update!(s, ii, resp)
        end
        @debug "handle ord: this event" _module = LogWatchOrder id = id status = resp_order_status(
            resp, eid
        )
        if isempty(id) || resp_event_type(resp, eid) != Order
            @debug "handle ord: missing order id" _module = LogWatchOrder
            return nothing
            # NOTE: when an order request is rejected by the exchange
            # a local order is never stored
        elseif _ccxtisstatus(resp, "rejected", eid)
            @debug "handle ord: rejected order" _module = LogWatchOrder
            return nothing
        else
            try
                state = get_order_state(orders_byid, id; s, ii)
                if state isa LiveOrderState
                    @debug "handle ord: updating" _module = LogWatchOrder id ii = raw(ii)
                    update_order!(s, ii, eid; resp, state)
                elseif _ccxtisopen(resp, eid)
                    @debug "handle ord: re-activating (open) order" _module = LogWatchOrder id ii = raw(
                        ii
                    )
                    re_activate_order!(s, ii, id; eid, resp)
                else
                    for o in values(s, ii) # ensure order is not stored locally
                        if o.id == id
                            @debug "handle ord: cancelling local order since non open remotely" _module =
                                LogWatchOrder id ii = raw(ii) s = nameof(s)
                            cancel!(
                                s,
                                o,
                                ii;
                                err=OrderFailed(
                                    "Dangling order $id found in local state ($(raw(ii)))."
                                ),
                            )
                            break # do not expect duplicates
                        end
                    end
                end
            finally
                Rocket.next!(asset_orders_task(s, ii).storage[:notify], nothing)
            end
        end
    catch e
        e isa InterruptException && rethrow(e)
        @ifdebug LogWatchOrder isdefined(Main, :e) && (Main.e[] = e)
        @debug_backtrace LogWatchOrder
        (e isa InvalidStateException) || @error e
    end
end

@doc """Emulates a trade based on order and response objects.

$(TYPEDSIGNATURES)

This function checks if an order is open, validates the order details (type, symbol, id, side), and calculates the filled amount.
If the filled amount has changed, it computes the new average price and checks if it's within the limits.
It then emulates the trade and updates the order state.
"""
function emulate_trade!(
    s::LiveStrategy, o, ii; resp, average_price=nothing, exec=true
)::Union{Trade,Missing,Nothing}
    eid = exchangeid(ii)
    if !isopen(ii, o) || _ccxtisstatus(resp_order_status(resp, eid), "canceled", "rejected")
        @debug "emu trade: closed/canceled order" _module = LogCreateTrade o.id
        return nothing
    end
    if !isordertype(ii, o, resp, eid) ||
        !isordersymbol(ii, o, resp, eid) ||
        !isorderid(ii, o, resp, eid; getter=resp_order_id)
        return nothing
    end
    side = _ccxt_sidetype(resp, eid; o)
    if !isorderside(side, o)
        return nothing
    end
    ignore_cost = isnocost(o)
    new_filled = resp_order_filled(resp, eid)
    prev_filled = filled_amount(o)
    actual_amount = new_filled - prev_filled
    if !ignore_cost && actual_amount < ii.limits.amount.min
        @debug "emu trade: fill status unchanged" _module = LogCreateTrade o.id prev_filled new_filled actual_amount
        return nothing
    end
    if isnothing(average_price)
        average_price = let ap = resp_order_average(resp, eid)
            iszero(ap) ? o.price : ap
        end |> Ref
    end
    prev_cost = average_price[] * prev_filled
    (net_cost, actual_price) = let ap = resp_order_average(resp, eid)
        if ap > zero(ap)
            net_cost = let c = resp_order_cost(resp, eid)
                iszero(c) ? ap * actual_amount : c
            end
            this_price = (ap - prev_cost) / actual_amount
            average_price[] = ap
            (net_cost, this_price)
        else
            this_cost = resp_order_cost(resp, eid)
            if iszero(this_cost)
                @error "emu trade: unavailable fields (average or cost)" ii ii.exchange o.id resp
                (0.0, 0.0)
            else
                prev_cost = average_price[] * prev_filled
                net_cost = this_cost - prev_cost
                if net_cost < ii.limits.cost.min && !ignore_cost
                    @error "emu trade: net cost below min" ii net_cost o
                    (0.0, 0.0)
                else
                    average_price[] = (prev_cost + net_cost) / new_filled
                    (net_cost, net_cost / actual_amount)
                end
            end
        end
    end

    isorderprice(s, ii, actual_price, o; resp)
    inlimits(actual_price, ii, :price)
    if !ignore_cost &&
        (!inlimits(net_cost, ii, :cost) || !inlimits(actual_amount, ii, :amount))
        return nothing
    end

    @debug "emu trade: emulating" _module = LogCreateTrade o.id
    _warn_cash(s, ii, o; actual_amount)
    date = @something pytodate(resp, eid) TimeTicks.now()
    fees_quote, fees_base = _tradefees(
        resp, orderside(o), ii; actual_amount=actual_amount, net_cost=net_cost
    )
    size = _addfees(net_cost, fees_quote, o)
    trade = @maketrade
    if exec
        queue = asset_queue(ii)
        try
            inc!(queue)
            trade!(
                s,
                o,
                ii;
                resp,
                trade,
                date=nothing,
                price=nothing,
                actual_amount=nothing,
                fees=nothing,
                slippage=false,
            )
            event!(ii, InstrumentEvent, :trade_created_emulated, s; trade, avgp=average_price)
            trade
        finally
            dec!(queue)
        end
    else
        trade
    end
end
