using ...PaperMode.SimMode: trade!
using .Lang: splitkws

using LRUCache

@doc """ Determines the date from which trades should be watched on startup.

$(TYPEDSIGNATURES)

This function determines the date from which trades should be watched when the live strategy `s` starts up. The date is calculated as the current time minus a specific `offset`.

"""
function startup_watch_since(s::LiveStrategy, offset=Millisecond(1))
    last_date = DateTime(0)
    for o in values(s)
        otrades = trades(o)
        if isempty(otrades)
            if o.date > last_date
                last_date = o.date
            end
        else
            date = last(otrades).date
            if date > last_date
                last_date = date
            end
        end
    end
    if last_date == DateTime(0)
        TimeTicks.now()
    else
        last_date + offset
    end
end

@doc """ Determines if the exchange has the `fetchMyTrades` method. """
hasmytrades(exc) = has(exc, :fetchMyTrades, :fetchMyTradesWs, :watchMyTrades)
@doc """ Starts tasks to watch the exchange for trades for an asset instance.

$(TYPEDSIGNATURES)

This function starts tasks in a live strategy `s` that watch the exchange for trades for an asset instance `ii`. It constantly checks and updates the trades based on the latest data from the exchange.

"""
function watch_trades!(s::LiveStrategy, ii; exc_kwargs=(;))
    @debug "watch trades: get tasks" _module = LogTasks2 isownable(ii.lock) isownable(
        s.lock
    ) @caller(20)
    tasks = asset_tasks(ii)
    @debug "watch trades: locking" _module = LogTasks2 ii
    @lock tasks.lock begin
        @deassert tasks.byname === asset_tasks(ii).byname
        let task = asset_trades_task(tasks.byname)
            if istaskrunning(task)
                @debug "watch trades: task running" _module = LogTasks2 ii
                return task
            end
        end
        exc, stop_delay = initialize_watch_trades_tasks!(s, ii)
        if !hasmytrades(exc)
            @error "watch trades: trades monitoring is not supported" exc ii
            return nothing
        end
        loop_func, iswatch = define_trades_loop_funct(s, ii, exc; exc_kwargs)
        task = @start_task IdDict() manage_trade_updates!(
            s, ii, stop_delay, loop_func, iswatch
        )
        tasks.byname[:trades_task] = task
        @debug "watch trades: new task" _module = LogTasks2 ii task istaskstarted(task) first(
            keys(task.storage)
        )
        while !istaskstarted(task)
            sleep(0.01)
        end
        return task
    end
end

function initialize_watch_trades_tasks!(s::LiveStrategy, ii)
    exc = exchange(ii)
    stop_delay = Ref(Second(60))
    return exc, stop_delay
end

function define_trades_loop_funct(s::LiveStrategy, ii, exc; exc_kwargs=(;))
    watch_func = first(exc, :watchMyTrades)
    _, func_kwargs = splitkws(:since; kwargs=exc_kwargs)
    sym = raw(ii)
    buf_subject = @lget! ii :trades_buf_subject Rocket.Subject(Any)
    buf = @lget! ii :trades_buf Vector{Any}()
    sizehint!(buf, s[:live_buffer_size])
    has_watch_trades = !isnothing(first(exc, :watchMyTrades, :watchMyTradesForSymbols))
    iswatch = has_watch_trades && s[:is_watch_mytrades]
    if iswatch
        init_handler() = begin
            task_local_storage(:buf_subject, buf_subject)
            task_local_storage(:buf, buf)
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
            sto = task_local_storage()
            this_buf = @something get(sto, :buf, nothing) begin
                init_handler()
                sto[:buf]
            end
            subj = task_local_storage(:buf_subject)
            result = Ref{Any}()
            Rocket.subscribe!(subj |> Rocket.take(1), Rocket.lambda(
                on_next = v -> result[] = v,
                on_error = e -> @warn("mytrades watcher: buf subscription error", exception = (e, catch_backtrace()))
            ))
            while !isassigned(result)
                !@istaskrunning() && return
            end
            result[]
        end
        (get_from_buffer, true)
    else
        last_date = isempty(ii.history) ? attr(s, :is_start, TimeTicks.now()) : last(ii.history).date
        since = Ref(last_date)
        startup = Ref(true)
        eid = exchangeid(ii)
        function flush_buf_subject()
            if !isempty(buf)
                ans = similar(buf)
                append!(ans, buf)
                empty!(buf)
                return ans
            end
        end
        function get_from_call()
            if !startup[]
                sleep(1)
            end
            updates = @something flush_buf_subject() fetch_my_trades(
                s, ii; since=dtstamp(since[]) + 1, func_kwargs...
            ) missing
            if islist(updates) && !isempty(updates)
                since[] = resp_trade_timestamp(updates[-1], eid, DateTime)
            elseif startup[]
                startup[] = false
            end
            updates
        end
        (get_from_call, false)
    end
end

function manage_trade_updates!(s::LiveStrategy, ii, stop_delay, loop_func, iswatch)
    idle_timeout = Second(s.watch_idle_timeout)
    events = get_events(ii)
    asset_cond = condition(ii)
    strategy_cond = condition(s)
    orders_byid = active_orders(ii)
    try
        while @istaskrunning()
            try
                @debug "watchers trades: loop func" _module = LogWatchTrade
                updates = loop_func()
                send_trades!(
                    s,
                    ii,
                    updates;
                    orders_byid,
                    events,
                    asset_cond,
                    strategy_cond,
                    iswatch,
                )
                stop_delay[] = idle_timeout
            catch e
                handle_trade_updates_errors!(e, ii, iswatch)
            end
        end
    finally
        h = get(task_local_storage(), :handler, nothing)
        if !isnothing(h)
            stop_handler!(h)
        end
    end
end

function send_trades!(
    s, ii, updates; orders_byid, events, asset_cond, strategy_cond, iswatch
)
    if updates isa Exception
        if updates isa InterruptException
            throw(updates)
        else
            @ifdebug (updates isa InvalidStateException) ||
                @debug "watch trades: fetching error" _module = LogWatchTrade ii updates
            if !iswatch
                sleep(1)
            end
        end
    elseif islist(updates)
        @debug "watch trades: resp" _module = LogWatchTrade2 updates
        for resp in updates
            date = resp_trade_timestamp(resp, exchangeid(ii), DateTime)
            func = () -> handle_trade!(s, ii, orders_byid, resp)
            sendrequest!(ii, date, func; events)
            Rocket.next!(asset_cond, nothing)
            Rocket.next!(strategy_cond, nothing)
        end
    else
        date = resp_trade_timestamp(updates, exchangeid(ii), DateTime)
        func = () -> handle_trade!(s, ii, orders_byid, updates)
        sendrequest!(ii, date, func; events)
        Rocket.next!(asset_cond, nothing)
        Rocket.next!(strategy_cond, nothing)
    end
end

function handle_trade_updates_errors!(e, ii, iswatch)
    if e isa InterruptException || (iswatch && e isa InvalidStateException)
        rethrow(e)
    else
        @error "watch trades: error (task termination?)" exception = (e, catch_backtrace()) _module = LogWatchTrade raw(ii)
    end
    if !iswatch
        sleep(1)
    end
end

asset_trades_task(tasks::AbstractDict) = get(tasks, :trades_task, nothing)
@doc """ Retrieves the asset trades task for a given asset instance.

$(TYPEDSIGNATURES)

This function retrieves the asset trades task for a given asset instance `ii` from the live strategy `s`. The asset trades task is responsible for watching the exchange for trades for the asset instance.

"""
function asset_trades_task(s::Strategy, ii::InstrumentInstance)
    @something get(asset_tasks(ii).byname, :trades_task, nothing) watch_trades!(s, ii)
end
@doc """ Generates a minimal hash for a trade response. """
_trade_kv_hash(resp, eid::EIDType) = begin
    p1 = resp_trade_price(resp, eid, Any)
    p2 = resp_trade_timestamp(resp, eid)
    p3 = resp_trade_amount(resp, eid, Any)
    p4 = resp_trade_side(resp, eid)
    p5 = resp_trade_type(resp, eid)
    p6 = resp_trade_tom(resp, eid)
    hash((p1, p2, p3, p4, p5, p6))
end

@doc """ Uses the trade id to generate a hash, otherwise uses the trade info. """
function trade_hash(resp, eid)
    id = resp_trade_id(resp, eid)
    if isnothing(id)
        info = resp_trade_info(resp, eid)
        if isnothing(info)
            _trade_kv_hash(resp, eid)
        else
            hash(info)
        end
    else
        hash(id)
    end
end

@doc """ Retrieves the state of an order with a specific ID.

$(TYPEDSIGNATURES)

This function retrieves the state of an order with a specific `id` from a collection of orders `orders_byid`. If the state is not immediately available, the function waits for a specified duration `waitfor` before trying again.

"""
function get_order_state(orders_byid, id; s, ii, file=@__FILE__, line=@__LINE__)
    os = @something(
        get(orders_byid, id, nothing)::Union{Nothing,LiveOrderState}, findorder(s, ii; id),
    missing)
    if !(os isa LiveOrderState)
        @debug "get ord state: order not found active" _module = LogWatchOrder id _file =
            file _line = line f = @caller(10)
    end
    os
end

@doc "Stores a trade in the recently orders cache."
function record_trade_update!(s::LiveStrategy, ii, resp)
    lrt = recent_trade_update(s, ii)
    lrt[trade_hash(resp, exchangeid(ii))] = nothing
end
function delete_trade_update!(s::LiveStrategy, ii, resp)
    lrt = recent_trade_update(s, ii)
    delete!(lrt, trade_hash(resp, exchangeid(ii)))
end
function isprocessed_trade_update(s, ii, resp)
    trade_hash(resp, exchangeid(ii)) ∈ keys(recent_trade_update(s, ii))
end

@doc """ Handles a trade for a live strategy with an asset instance.

$(TYPEDSIGNATURES)

This function manages a trade for a live strategy `s` with an asset instance `ii`. It looks at the collection of orders `orders_byid` and the response `resp` from the exchange to update the state of the trade.
It first checks if the trade is already present in `orders_byid`. If it is, the function updates the existing order with the new information from `resp`. If the trade is not present in `orders_byid`, the function creates a new order and adds it to `orders_byid`.
It then checks if the trade has been completed. If it has, the function updates the state of the order in `orders_byid` to reflect this.
A semaphore `sem` is used to ensure that only one thread is updating `orders_byid` at a time, to prevent data races.

"""
function handle_trade!(s, ii, orders_byid, resp)
    try
        eid = exchangeid(ii)
        id = resp_trade_order(resp, eid, String)
        if resp_event_type(resp, eid) != ot.Trade ||
            isprocessed_order(s, ii, id) ||
            isprocessed_trade_update(s, ii, resp)
            return nothing
        end
        record_trade_update!(s, ii, resp)
        @debug "handle trade: new event" _module = LogWatchTrade order = id n_keys = length(
            resp
        )
        if isempty(id)
            @debug "handle trade: missing order id" _module = LogWatchTrade
            return nothing
        else
            try
                state = get_order_state(orders_byid, id; s, ii)
                if state isa LiveOrderState
                    @debug "handle trade: locking state" _module = LogWatchTrade id resp isownable(
                        ii.lock
                    ) isownable(state.lock)
                    @inlock ii @lock state.lock begin
                        @debug "handle trade: STATE LOCKED" _module = LogWatchTrade id resp
                        this_hash = trade_hash(resp, eid)
                        this_hash ∈ state.trade_hashes || begin
                            push!(state.trade_hashes, this_hash)
                            @debug "handle trade: exec trade" _module = LogWatchTrade ii id isownable(
                                ii.lock
                            )
                            t = begin
                                @debug "handle trade: before trade exec" _module =
                                    LogWatchTrade ii open = if ismissing(state)
                                    missing
                                else
                                    isopen(ii, state.order)
                                end state isa LiveOrderState
                                if isopen(ii, state.order)
                                    queue = asset_queue(ii)
                                    inc!(queue)
                                    try
                                        @debug "handle trade: trade!" _module =
                                            LogWatchTrade
                                        t = trade!(
                                            s,
                                            state.order,
                                            ii;
                                            resp,
                                            date=nothing,
                                            price=nothing,
                                            actual_amount=nothing,
                                            fees=nothing,
                                            slippage=false,
                                        )
                                            if !isnothing(t)
                                                event!(
                                                    ii,
                                                    InstrumentEvent,
                                                    :trade_created,
                                                    s;
                                                    trade=t,
                                                    avgp=state.average_price,
                                                )
                                            else
                                                @debug "handle trade: failed from resp" _module = LogCreateTrade ii state.order resp
                                            end
                                        t
                                    finally
                                        dec!(queue)
                                    end
                                end
                            end
                            @debug "handle trade: after exec" _module = LogWatchTrade trade =
                                t cash = cash(ii) side = if isnothing(t)
                                get_position_side(s, ii)
                            else
                                posside(t)
                            end
                        end
                    end
                else
                    reschedule() = begin
                        delete_trade_update!(s, ii, resp) # otherwise it will be skipped
                        func = () -> handle_trade!(s, ii, orders_byid, resp)
                        date = TimeTicks.now() + Millisecond(500)
                        sendrequest!(ii, date, func)
                    end
                    # NOTE: give id directly since the _resp is for a trade and not an order
                    o = @inlock ii findorder(s, ii; resp, id)
                    if o isa Order
                        this_filled = isfilled(ii, o)
                        if this_filled && length(trades(o)) > 0
                            amount = resp_trade_amount(resp, eid)
                            last_amount = last(trades(o)).amount
                            if abs(last_amount) != amount
                                @warn "handle trade: late trade not matching last trade (wrong emu?)" ii id emulated = last_amount exchange = amount
                            end
                        elseif this_filled
                            @error "handle trade: filled order without executed trades" ii id
                        else
                            @warn "handle trade: no matching live order state (rescheduling)" ii id s resp
                            reschedule()
                        end
                    else
                        @warn "handle trade: no matching order nor state (rescheduling)" id ii resp o
                        reschedule()
                    end
                end
            finally
                Rocket.next!(asset_trades_task(s, ii).storage[:notify], nothing)
            end
        end
    catch e
        e isa InterruptException && rethrow(e)
        @ifdebug LogWatchTrade isdefined(Main, :e) && (Main.e[] = e)
        @debug_backtrace LogWatchTrade
        (e isa InvalidStateException) || @error e
    end
end

@doc """ Stops the watcher for trades for a specific asset instance in a live strategy.

$(TYPEDSIGNATURES)
"""
function stop_watch_trades!(s::LiveStrategy, ii)
    waitfor = attr(s, :live_stop_timeout, Second(3))
    @timeout_start
    t = asset_trades_task(s, ii)
    if istaskrunning(t)
        stop_task(t)
        if !istaskdone(t)
            sto = t.storage
            if !isnothing(sto)
                subj = get(sto, :buf_subject, nothing)
                if !isnothing(subj)
                    Rocket.complete!(subj)
                end
            end
            cleanup_task = @start_task IdDict() begin
                try
                    waitforcond(() -> !istaskdone(t), @timeout_now())
                    if !istaskdone(t)
                        kill_task(t)
                    end
                catch e
                    e isa InterruptException && rethrow(e)
                    @error "mytrades: cleanup task failed" exception = (e, catch_backtrace())
                end
            end
            wait(cleanup_task)
        end
    end
end

@doc """ Forces a fetch trades operation for a specific order in a live strategy with an asset instance.

$(TYPEDSIGNATURES)

This function forces a fetch trades operation for a specific order `o` in a live strategy `s` with an asset instance `ii`. This function is typically used when the normal fetch trades operation did not return the expected results and a forced fetch is necessary.

"""
function _force_fetchtrades(s, ii, o)
    @lock s let a = s.attrs
        _trades_resp_cache(a, ii) |> empty!
        _order_trades_resp_cache(a, ii) |> empty!
    end
    ordersby_id = active_orders(ii)
    state = get_order_state(ordersby_id, o.id; s, ii)
    @debug "force fetch trades: " _module = LogTradeFetch locked =
        state isa LiveOrderState ? isownable(state.lock) : nothing ii f = @caller(10)
    function handler()
        @debug "force fetch trades: fetching" _module = LogTradeFetch o.id
        trades_resp = fetch_order_trades(s, ii, o.id)
        if trades_resp isa Exception
            @ifdebug ispyminor_error(trades_resp) ||
                @debug "force fetch trades: error fetching trades" _module =
                LogTradeFetch trades_resp
        elseif islist(trades_resp) || trades_resp isa Vector
            @debug "force fetch trades: trades task" _module = LogTradeFetch length(trades_resp)
            task = watch_trades!(s, ii)
            waitforcond(() -> haskey(task.storage, :buf), Second(1))
            buf = task.storage[:buf]
            append!(buf, trades_resp)
            Rocket.next!(task.storage[:buf_subject], nothing)
        else
            @error "force fetch trades: invalid response " trades_resp
        end
    end

    if state isa LiveOrderState
        prev_count = length(trades(o))
        waslocked = islocked(state.lock)
        @debug "force fetch trades: locking state" _module = LogTradeFetch id = o.id waslocked isownable(
            state.lock
        ) f = @caller(10)
        @lock state.lock if waslocked && length(trades(o)) != prev_count
            @debug "force fetch trades: skipping after lock" _module = LogTradeFetch
            return nothing
        else
            # NOTE: only lock asset *after* state.lock not avoid deadlocks
            handler()
        end
    else
        handler()
    end
end
