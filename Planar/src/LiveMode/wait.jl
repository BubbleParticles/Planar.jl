## TRADES
@doc """ Waits for a trade in a live strategy with a specific asset instance.

$(TYPEDSIGNATURES)

This function waits for a trade in a live strategy `s` with a specific asset instance `ii`. It continues to wait for a specified duration `waitfor` until a trade occurs.

"""
function waittrade(s::LiveStrategy, ii; waitfor=Second(5))
    if !hasmytrades(exchange(ii))
        @error "wait for trade: not supported"
        return 0
    end
    tt = try
        asset_trades_task(s, ii)
    catch e
        e isa InterruptException && rethrow(e)
        @error "wait for trade: failed to get trades task" exception = (e, catch_backtrace()) _module = LogWaitTrade
        return 0
    end
    if !(tt isa Task)
        @error "wait for trade: task not running (strategy stopped?)"
        return 0
    end
    timeout = Millisecond(waitfor).value
    cond = tt.storage[:notify]
    this_trades = trades(ii)
    prev_count = length(this_trades)
    slept = 0
    while slept < timeout
        if istaskrunning(tt)
            slept += waitforcond(cond, timeout - slept)
            if length(this_trades) != prev_count
                break
            end
        else
            @debug "wait for trades: trades task is not running, restarting" _module =
                LogWaitTrade ii
            tt = watch_trades!(s, ii)
            if !istaskrunning(tt)
                @error "wait for trade: failed to restart task" ii
                break
            end
        end
    end
    slept
end

@doc """ Waits for a specific order to trade in a live strategy with a specific asset instance.

$(TYPEDSIGNATURES)

This function waits for a specific order `o` to trade in a live strategy `s` with a specific asset instance `ii`. It continues to wait for a specified duration `waitfor` until the order is traded.

"""
function waittrade(s::LiveStrategy, ii, o::Order; waitfor=Second(5), force=true)
    if !hasmytrades(exchange(ii))
        @error "wait for trade: not supported"
        return 0
    end
    if isfilled(ii, o)
        return true
    end
                order_trades = trades(o)
    this_count = prev_count = length(order_trades)
    timeout = Millisecond(waitfor).value
    slept = 0
    side = orderside(o)
    pt = pricetime(o)
    actord = active_orders(ii)
    _force() =
                if force
            @debug "wait for trade:" _module = LogWaitTrade id = o.id f = @caller
            # TODO: ensure this lock doesn't cause deadlocks
                    _force_fetchtrades(s, ii, o)
            length(order_trades) > prev_count
        else
            false
        end
    @debug "wait for trade:" _module = LogWaitTrade id = o.id timeout = timeout current_trades =
        this_count
        while true
            try
                if slept >= timeout
                    @debug "wait for trade: timedout" _module = LogWaitTrade id = o.id f = @caller 7
                    return _force()
end
                if !isactive(s, ii, o; pt, actord)
                    @debug "wait for trade: order not present" _module = LogWaitTrade id = o.id f = @caller
                    return _force()
end
                @debug "wait for trade: " _module = LogWaitTrade isfilled(ii, o) length(
                    order_trades
)
                slept += let time = waittrade(s, ii; waitfor=timeout - slept)
                    if iszero(time)
                        break
end
                    time
end
                # After asset-level trade signal, refresh order_trades and try to force-fetch order trades
                order_trades = trades(o)
                this_count = length(order_trades)
                if this_count > prev_count
return true
                end
                # If no new trades yet, attempt a forced fetch if allowed
                if force
            try
                    _force_fetchtrades(s, ii, o)
                    catch e
                        if e isa InterruptException
                            rethrow(e)
                        end
                        @error "wait trades: force fetch trades failed" exception = (e, catch_backtrace()) _module = LogWaitTrade
                end
                order_trades = trades(o)
                this_count = length(order_trades)
                if this_count > prev_count
return true
                end
                end
            catch e
                e isa InterruptException && rethrow(e)
                @error "waittrade: error" exception=(e, catch_backtrace()) ii o.id
return false
end
            end
    this_count > prev_count
end

## ORDERS
##
function waitordertask(s, ii; waitfor)
    local aot
    slept = 0
    timeout = Millisecond(waitfor).value
    while slept < timeout
        aot = @something asset_orders_task(s, ii) missing
        if !ismissing(aot)
            break
        end
        sleep(Millisecond(100))
        slept += 100
    end
    return (slept, aot)
end

@doc """Waits for any order event to happen on the specified asset.

$(TYPEDSIGNATURES)

This function waits for a specified amount of time or until an order event happens.
It keeps track of the number of orders and checks if any new order has been added during the wait time.
If the task is not running, it stops waiting and returns the time spent waiting.
"""
function waitorder(s::LiveStrategy, ii; waitfor=Second(3))
    aot_slept, aot = waitordertask(s, ii; waitfor)
    @debug "wait for order: any" _module = LogWaitOrder aot aot_slept
    !(aot isa Task) && return aot_slept
    timeout = Millisecond(waitfor).value
    cond = aot.storage[:notify]
    prev_count = orderscount(s, ii)
    slept = aot_slept
    @debug "wait for order: loop" _module = LogWaitOrder ii waitfor
    while slept < timeout
        if istaskrunning(aot)
            slept += waitforcond(cond, timeout - slept)
            if orderscount(s, ii) != prev_count
                @debug "wait for order: new event" _module = LogWaitOrder ii = raw(ii) slept
                break
            end
        else
            @debug "wait for order: orders task is not running, restarting" _module =
                LogWaitOrder ii
            aot = watch_orders!(s, ii)
            if !istaskrunning(aot)
                @error "wait for order: failed to restart task"
                return 0
            end
        end
    end
    slept
end

@doc """ Waits for a specific order to be processed.

$(TYPEDSIGNATURES)

This function waits for a specific order to be processed within a given time frame specified by `waitfor`.
If the order is not found or not tracked within the given timeframe, the function returns `false`.
If the order is found and tracked within the given timeframe, the function returns `true`.
It tracks the time spent waiting and if the timeout is reached before the order is found, the function returns `false`.

"""
function waitorder(s::LiveStrategy, ii, o::Order; waitfor=Second(3))
    slept = 0
    timeout = Millisecond(waitfor).value
    orders_byid = active_orders(ii)
    if @lock ii !haskey(orders_byid, o.id)
        isproc = isprocessed_order(s, ii, o.id)
        @debug "Wait for order: inactive" _module = LogWaitOrder unfilled(o) filled_amount(
            o
        ) isfilled(ii, o) isproc fetch_orders(s, ii, ids=(o.id,)) @caller
        return isproc || isfilled(ii, o)
    end
    @debug "Wait for order: start" _module = LogWaitOrder id = o.id timeout = timeout
    while slept < timeout
        slept += let this_slept = waitorder(s, ii; waitfor)
            if this_slept == 0
                return !haskey(orders_byid, o.id) ||
                    ordertype(o) <: MarketOrderType ||
                    !haskey(s, ii, o)
            end
            this_slept
        end
        if !haskey(orders_byid, o.id)
            @ifdebug if isimmediate(o) && isempty(trades(o))
                @warn "Wait for order: immediate order has no trades"
            end
            @debug "Wait for order: not tracked" _module = LogWaitOrder id = o.id
            return true
        elseif !haskey(s, ii, o) || ordertype(o) <: MarketOrderType
            @debug "Wait for order: not found" _module = LogWaitOrder id = o.id
            return true
        end
    end
    @debug "Wait for order: timedout" _module = LogWaitOrder id = o.id timeout
    return false
end

function waitsync(obj; since::Option{DateTime}=nothing, waitfor::Period=Second(5))
    events = get_events(obj)
    if isnothing(since)
        if isempty(events)
            return nothing
        end
        since = last(events).date
    end
    waitforcond(() -> lasteventrun!(obj) > since, waitfor)
    return nothing
end

function waitsync(
    s::LiveStrategy;
    since::Option{DateTime}=nothing,
    waitfor::Period=Second(5),
    waitwatchers=false,
)
    events = get_events(s)
    if isnothing(since)
        if isempty(events)
            return nothing
        end
        since = last(events).date
    end
    if waitwatchers
        waitwatcherprocess(balance_watcher(s); since, waitfor)
        if s isa MarginStrategy
            waitwatcherprocess(positions_watcher(s); since, waitfor)
        end
    end
    waitforcond(() -> lasteventrun!(s) > since, waitfor)
end

function waitwatcherupdate(w_func::Function)
    w::Option{Watcher} = nothing
    while isnothing(w)
        w = try
            w_func()
        catch e
            e isa InterruptException && rethrow(e)
            @error "sync unic cash" exception = (e, catch_backtrace())
        end
    end
    while isempty(w.buffer) && w.last_fetch == DateTime(0)
        @debug "sync uni cash: waiting for position data" _module = LogUniSync
        if !wait(w, Second(30), :process)
            @warn "sync uni cash: timeout waiting for position data" _module = LogUniSync
            break
        else
            sleep(0.01)
        end
    end
    @debug "sync uni cash: position data ready" _module = LogUniSync
end

function waitwatcherprocess(w::Watcher; since=nothing, waitfor=Minute(1))
    if isnothing(since)
        since = DateTime(0)
    end
    if _lastprocessed(w) > since
        return nothing
    end
    buf = w.buf_process # set in either the balance or positions watcher
    tasks = w.process_tasks
    waitfunc = () -> begin
        filter!(!istaskdone, w.process_tasks)
        _lastprocessed(w) > since && isempty(buf) && isempty(tasks)
    end
    waitforcond(waitfunc, waitfor)
end

macro syncedlock(ii, code)
    waitfor = esc(:waitfor)
    quote
        waitsync($ii, waitfor=$waitfor)
        @lock $ii $code
    end
end
