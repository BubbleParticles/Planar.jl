function condition(ii::InstrumentInstance)
    @lget! ii :event_cond Threads.Condition()
end

function condition(s::LiveStrategy)
    @lget! s :event_cond Threads.Condition()
end

function sync_condition(ii::InstrumentInstance)
    @lget! ii :sync_cond Threads.Condition()
end

function sync_condition(s::LiveStrategy)
    @lget! s :sync_cond Threads.Condition()
end

function lasteventrun!(obj::Union{Strategy,InstrumentInstance}, date::DateTime)
    obj[:last_event_date] = date
end

function lasteventrun!(obj::Union{Strategy,InstrumentInstance})
    @lget! obj :last_event_date DateTime(0)
end

const SyncRequest1 = NamedTuple{(:date, :func),Tuple{DateTime,<:Function}}
function get_events(s::LiveStrategy)
    @lget! s :events begin
        lasteventrun!(s)
        condition(s)
        SortedArray(Vector{SyncRequest1}(); by=erq -> erq.date)
    end
end

function get_events(ii::InstrumentInstance)
    @lget! ii :events begin
        lasteventrun!(ii)
        condition(ii)
        SortedArray(Vector{SyncRequest1}(); by=erq -> erq.date)
    end
end

# Lock for synchronizing access to event queues
function events_lock(obj)
    @lget! attrs(obj) :events_lock Threads.ReentrantLock()
end

function notify_request(ii::InstrumentInstance)
    safenotify(condition(ii))
end

function notify_request(s::LiveStrategy)
    safenotify(condition(s))
end

function notify_sync(ii::InstrumentInstance)
    safenotify(sync_condition(ii))
end

function notify_sync(s::LiveStrategy)
    safenotify(sync_condition(s))
end

function sendrequest!(obj, date::DateTime, f::Function; events=get_events(obj))
    if !get(obj, :stopping_handler, false)
        h = get_handler!(obj)
        if istaskrunning(h)
            func() = begin
                f()
                notify_sync(obj)
            end
            lock(events_lock(obj)) do
                push!(events, (; date, func))
            end
            notify_request(obj)
            nothing
        else
            @warn "events: request unscheduled, event handler not running" date @caller(10)
        end
    end
end

function sendrequest!(
    obj, date::DateTime, f::Function, waitfor::Period; events=get_events(obj)
)
    if !get(obj, :stopping_handler, false)
        h = get_handler!(obj)
        if istaskrunning(h)
            done = Ref(false)
            ans = Ref{Any}(nothing)
            func() = begin
                ans[] = f()
                notify_sync(obj)
                done[] = true
            end
            lock(events_lock(obj)) do
                push!(events, (; date, func))
            end
            notify_request(obj)
            waitforcond(() -> done[], waitfor)
            ans[]
        else
            @warn "events: request unscheduled, event handler not running" date @caller(10)
        end
    end
end

function handle_events(obj, events=get_events(obj), cond=condition(obj))
    # Track async sleep tasks for cleanup
    sleep_tasks = @lget! attrs(obj) :handler_sleep_tasks Vector{Task}()
    while true
        # Atomically check and retrieve the next due event
        req = lock(events_lock(obj)) do
            if isempty(events)
                return nothing
            end

            next_req = first(events)
            diff = next_req.date - TimeTicks.now()

            if diff <= Second(0)
                # Event is ready, pop it and return
                return popfirst!(events)
            else
                # Event is in the future, schedule a wakeup and signal no work for now
                @debug "events: waiting for the future" _module = LogEvents next_req.date
                sleep_task = @start_task IdDict() begin
                    try
                        # Use interruptible sleep
                        remaining = abs(diff)
                        while remaining > Millisecond(0)
                            sleep_time = min(remaining, Second(1))
                            sleep(sleep_time)
                            remaining -= sleep_time
                            if !istaskrunning(current_task())
                                break
                            end
                        end
                        if istaskrunning(current_task())
                            safenotify(cond)
                        end
                    catch e
                        e isa InterruptException && rethrow(e)
                        @error "event handler: wakeup failed" exception = (e, catch_backtrace())
                    end
                end
                push!(sleep_tasks, sleep_task)
                return nothing
            end
        end

        if isnothing(req)
            break
        end

        _execute_event(obj, req)
    end
end

get_handler!(obj) = @lget! attrs(obj) :event_handler @lock obj _start_handler!(obj)
get_handler(obj) = attr(obj, :event_handler, nothing)

# TODO: handlers should stop after a while (similar to watch_orders and watch_trades)
function _start_handler!(obj)
    t = attr(obj, :event_handler, nothing)
    if !istaskrunning(t)
        events = get_events(obj)
        cond = condition(obj)
        obj[:event_handler] = @start_task IdDict() begin
            obj[:stopping_handler] = false
            # Protect the initial call to handle_events to avoid the task
            # terminating if handle_events raises an unexpected exception.
            try
                handle_events(obj, events, cond)
            catch e
                e isa InterruptException && rethrow(e)
                @warn "handler: initial handle_events failed" exception = e obj = obj
                @debug_backtrace LogEvents
            end
            while @istaskrunning()
                if obj[:stopping_handler]
                    break
                else
                    waitforcond(cond, Second(1))
                end
                try
                    handle_events(obj, events, cond)
                catch e
                    e isa InterruptException && rethrow(e)
                    @warn "handler: error during handle_events loop" exception = e obj = obj
                    @debug_backtrace LogEvents
                end
            end
        end
    end
end

function start_handlers!(s::LiveStrategy)
    _start_handler!(s)
    for ii in snapshot(universe(s))
        _start_handler!(ii)
    end
end

function delete_handler!(obj)
    delete!(attrs(obj), :event_handler)
end

function _stop_handler!(obj)
    t = get_handler(obj)
    if !isnothing(t)
        try
            obj[:stopping_handler] = true
            # Notify the condition to wake up the handler task if it's waiting
            notify_request(obj)
            notify_sync(obj)
            # Stop the task first - this will break the loop due to stopping_handler flag
            stop_task(t)
            # Wait for the task to finish with a timeout
            waitforcond(t.donenotify, Second(5))
            if !istaskdone(t)
                @warn "handler: task did not stop in time, killing" obj = obj
                kill_task(t)
            end
            # Clean up any pending sleep tasks
            sleep_tasks = get(obj.attrs, :handler_sleep_tasks, nothing)
            if !isnothing(sleep_tasks)
                for task in sleep_tasks
                    if istaskrunning(task)
                        stop_task(task)
                        waitforcond(task.donenotify, Second(1))
                        if !istaskdone(task)
                            kill_task(task)
                        end
                    end
                end
                empty!(sleep_tasks)
            end
            delete_handler!(obj)
        finally
            obj[:stopping_handler] = false
        end
    end
    t
end

function stop_handlers!(s::LiveStrategy)
    s_task = _stop_handler!(s)
    ai_tasks = [_stop_handler!(ii) for ii in snapshot(universe(s))]
    @debug "handlers: waiting termination" _module = LogEvents
    if istaskrunning(s_task)
        waitforcond(() -> !istaskrunning(s_task), Second(5))
        if istaskrunning(s_task)
            @warn "handlers: strategy handler task did not terminate" _module = LogEvents
        end
    end
    for (i, ii) in enumerate(snapshot(universe(s)))
        t = ai_tasks[i]
        if istaskrunning(t)
            waitforcond(() -> !istaskrunning(t), Second(5))
            if istaskrunning(t)
                @warn "handlers: asset handler task did not terminate" ii = raw(ii) _module = LogEvents
            end
        end
    end
    @debug "handlers: handlers terminated" _module = LogEvents
end

function reset_events!(s::LiveStrategy)
    empty!(get_events(s))
    foreach(empty!, (get_events(ii) for ii in snapshot(universe(s))))
end

function restart_handlers!(s::LiveStrategy)
    reset_events!(s)
    stop_handlers!(s)
    start_handlers!(s)
end

function _execute_event(obj, req::SyncRequest1)
    try
        req.func()
    catch e
        e isa InterruptException && rethrow(e)
        @error "handler: execute event failed" exception = (e, catch_backtrace()) _module = LogEvents
    end
    lasteventrun!(obj, req.date)
end
