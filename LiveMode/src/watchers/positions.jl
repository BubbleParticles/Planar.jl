using Watchers
using Watchers: default_init, _buffer_lock
using Watchers.WatchersImpls: _tfunc!, _tfunc, _exc!, _exc, _lastpushed!, _lastpushed
@watcher_interface!
using .PaperMode: sleep_pad
using .Exchanges: check_timeout, current_account
using .Lang: splitkws, safenotify, safewait

const CcxtPositionsVal = Val{:ccxt_positions}
# :read, if true, the value of :pos has already be locally synced
# :closed, if true, the value of :pos should be considered stale, and the position should be closed (contracts == 0)
@doc """ A named tuple for keeping track of position updates.

$(FIELDS)

This named tuple `PositionTuple` has fields for date (`:date`), notification condition (`:notify`), read status (`:read`), closed status (`:closed`), and Python response (`:resp`), which are used to manage and monitor the updates of a position.

"""
const PositionTuple = NamedTuple{
    (:date, :notify, :read, :closed, :resp),
    Tuple{DateTime,Base.Threads.Condition,Ref{Bool},Ref{Bool},Py},
}
const PositionsDict2 = Dict{String,PositionTuple}

function _debug_getup(w, prop=:time)
    @something get(get(last(w.buffer, 1), 1, (;)), prop, nothing) ()
end
function _debug_getval(w, k="datetime"; src=_debug_getup(w, :value))
    @something get(@get(src, 1, pydict()), k, nothing) ()
end

@doc """ Sets up a watcher for CCXT positions.

$(TYPEDSIGNATURES)

This function sets up a watcher for positions in the CCXT library. The watcher keeps track of the positions and updates them as necessary.
"""
function ccxt_positions_watcher(
    s::Strategy;
    interval=Second(5),
    wid="ccxt_positions",
    buffer_capacity=10,
    start=false,
    kwargs...,
)
    exc = st.exchange(s)
    check_timeout(exc, interval)
    haswpos = !isnothing(first(exc, :watchPositions))
    iswatch = haswpos && @lget! s.attrs :is_watch_positions haswpos
    attrs = Dict{Symbol,Any}()
    attrs[:strategy] = s
    attrs[:kwargs] = kwargs
    attrs[:interval] = interval
    attrs[:iswatch] = iswatch
    _exc!(attrs, exc)
    watcher_type = Union{Py,PyList}
    wid = string(wid, "-", hash((exc.id, nameof(s), account(s))))
    watcher(
        watcher_type,
        wid,
        CcxtPositionsVal();
        start,
        load=false,
        flush=false,
        process=false,
        buffer_capacity,
        view_capacity=1,
        fetch_interval=interval,
        attrs,
    )
end

@doc """ Guesses the settlement for a given margin strategy.

$(TYPEDSIGNATURES)

This function attempts to guess the settlement for a given margin strategy `s`. The guessed settlement is returned.
"""
function guess_settle(s::MarginStrategy)
    try
        first(s.universe).asset.sc |> string |> uppercase
    catch
        ""
    end
end

function split_params(kwargs)
    if kwargs isa NamedTuple && haskey(kwargs, :params)
        kwargs[:params], length(kwargs) == 1 ? (;) : withoutkws(:params; kwargs)
    else
        LittleDict{Any,Any}(), kwargs
    end
end

@doc """ Wraps a fetch positions function with a specified interval.

$(TYPEDSIGNATURES)

This function wraps a fetch positions function `s` with a specified `interval`. Additional keyword arguments `kwargs` are passed to the fetch positions function.
"""
function _w_positions_func(s, w, interval; iswatch, kwargs)
    # common setup
    exc = exchange(s)
    params, rest = split_params(kwargs)
    timeout = throttle(s)
    @lget! params "settle" guess_settle(s)
    w[:process_tasks] = tasks = Task[]
    w[:errors_count] = errors = Ref(0)
    buffer_size = attr(s, :live_buffer_size, 1000)
    s[:positions_buffer] = w[:buf_process] = buf = Vector{Tuple{Any,Bool}}()
    s[:positions_notify] = w[:buf_notify] = buf_notify = Condition()
    sizehint!(buf, buffer_size)
    # delegate per-mode
    @debug "watchers pos process: delegate" _module = LogWatchPos iswatch
    if iswatch
        return _w_positions_watch_mode(
            s, w, exc, timeout, params, rest, buf, buf_notify, tasks, errors, kwargs
        )
    else
        return _w_positions_fetch_mode(s, w, timeout, params, rest, buf, tasks, interval)
    end
end

# Helpers for _w_positions_func
function _stop_stall_guard_if_any!(w)
    if haskey(w, :stall_guard_task)
        stop_task(w[:stall_guard_task])
        delete!(w, :stall_guard_task)
    end
end

function _start_stall_guard!(w, s, kwargs)
    w[:stall_guard_task] = @start_task IdDict() begin
        while isstarted(w)
            try
                last = _lastprocessed(w)
                if now() - last > Second(60)
                    @warn "positions watcher: forcing fetch due to stall" last now() s
                    for ai in s.universe
                        try
                            _force_fetchpos(
                                s, ai, get_position_side(s, ai); fallback_kwargs=kwargs
                            )
                        catch e
                            @warn "positions watcher: stall guard error (per asset)" exception =
                                e ai
                        end
                    end
                end
            catch e
                @warn "positions watcher: stall guard error" exception = e
            end
            sleep(10)
        end
        @debug "positions watcher: stall guard task stopped" _module = LogWatchPosProcess
    end
end

@doc """ Pushes a new value to the watcher's buffer and schedules processing if the value is not nothing. Used internally to handle new position data, either from fetch or watch mode.

- `w`: The watcher object.
- `tasks`: Array of processing tasks.
- `v`: The value to push (positions data).
- `fetched`: Whether the data was fetched (vs. watched).
"""
function _positions_process_push!(w, tasks, v; fetched=false)
    if !isnothing(v)
        if !isnothing(_dopush!(w, pylist(v)))
            push!(tasks, @async process!(w; fetched))
            filter!(!istaskdone, tasks)
        end
    end
end

function _w_positions_watch_mode(
    s, w, exc, timeout, params, rest, buf, buf_notify, tasks, errors, kwargs
)
    _stop_stall_guard_if_any!(w)
    _start_stall_guard!(w, s, kwargs)
    init = Ref(true)
    function init_watch_func(w)
        let v = @lock w fetch_positions(s; timeout, params, rest...)
            _positions_process_push!(w, tasks, v; fetched=false)
        end
        init[] = false
        function push_positions_to_buf(v)
            push!(buf, (v, false))
            notify(buf_notify)
            maybe_backoff!(errors, v)
        end
        h =
            w[:positions_handler] = watch_positions_handler(
                exc,
                (ai for ai in s.universe);
                f_push=push_positions_to_buf,
                params,
                rest...,
            )
        start_handler!(h)
    end
    function watch_positions_func(w)
        if init[]
            init_watch_func(w)
        end
        while isempty(buf)
            !isstarted(w) && return nothing
            wait(buf_notify)
        end
        v, fetched = popfirst!(buf)
        if v isa Exception
            @error "positions watcher: unexpected value" exception = v maxlog = 3
            sleep(1)
        else
            @debug "positions watcher: PUSHING" _module = LogWatchPos islocked(
                _buffer_lock(w)
            ) w_time = _debug_getup(w) new_time = _debug_getval(w; src=v) n = length(
                _debug_getup(w, :value)
            ) _debug_getval(w, "symbol", src=v) length(w[:process_tasks])
            _positions_process_push!(w, tasks, v; fetched=fetched)
            @debug "positions watcher: PUSHED" _module = LogWatchPos _debug_getup(w, :time) _debug_getval(
                w, "contracts", src=v
            ) _debug_getval(w, "symbol", src=v) _debug_getval(w, "datetime", src=v) length(
                w[:process_tasks]
            )
        end
        return true
    end
    return watch_positions_func
end

function _flush_positions_notify!(w, buf, tasks)
    while !isempty(buf)
        v, fetched = popfirst!(buf)
        _dopush!(w, v)
        push!(tasks, @async process!(w; fetched))
    end
end

function _w_positions_fetch_mode(s, w, timeout, params, rest, buf, tasks, interval)
    function fetch_positions_func(w)
        start = now()
        try
            _flush_positions_notify!(w, buf, tasks)
            filter!(!istaskdone, tasks)
            v = @lock w fetch_positions(s; timeout, params, rest...)
            _dopush!(w, v)
            push!(tasks, @async process!(w, fetched=true))
            _flush_positions_notify!(w, buf, tasks)
            filter!(!istaskdone, tasks)
        finally
            sleep_pad(start, interval)
        end
    end
    return fetch_positions_func
end

@doc """ Starts the watcher for positions in a live strategy.

$(TYPEDSIGNATURES)

This function starts the watcher for positions in a live strategy `s`. The watcher checks and updates the positions at a specified interval.
"""
function watch_positions!(s::LiveStrategy; interval=st.throttle(s), wait=false)
    w = @lock s @lget! attrs(s) :live_positions_watcher ccxt_positions_watcher(s; interval)
    just_started = if isstopped(w) && !attr(s, :stopped, false)
        @lock w if isstopped(w)
            start!(w)
            true
        else
            false
        end
    else
        false
    end
    while wait && just_started && _lastprocessed(w) == DateTime(0)
        @debug "live: waiting for initial positions" _module = LogWatchPos
        safewait(w.beacon.process)
    end
    w
end

@doc """ Stops the watcher for positions in a live strategy.

$(TYPEDSIGNATURES)

This function stops the watcher that is tracking and updating positions for a live strategy `s`.

"""
function stop_watch_positions!(s::LiveStrategy)
    w = get(s.attrs, :live_positions_watcher, nothing)
    if w isa Watcher
        @debug "live: stopping positions watcher" _module = LogWatchPos
        if isstarted(w)
            stop!(w)
        end
        @debug "live: positions watcher stopped" _module = LogWatchPos
    end
end

@doc """ Starts the main asynchronous task for processing positions in the watcher. This task repeatedly calls the watcher's processing function as long as the watcher is started, handling errors and backoff.

- `w`: The watcher object.
"""
function _positions_task!(w)
    f = _tfunc(w)
    errors = w.errors_count
    w[:positions_task] = (@async while isstarted(w)
        try
            @debug "watchers pos: fetching/watching" _module = LogWatchPos
            f(w)
            @debug "watchers pos: fetched/watched" _module = LogWatchPos
            safenotify(w.beacon.fetch)
            @debug "watchers pos: notified" _module = LogWatchPos
        catch e
            if e isa InterruptException
                break
            else
                maybe_backoff!(errors, e)
                @debug_backtrace LogWatchPos2
            end
        end
    end) |> errormonitor
end

_positions_task(w) = @lget! attrs(w) :positions_task _positions_task!(w)

function Watchers._start!(w::Watcher, ::CcxtPositionsVal)
    _lastprocessed!(w, DateTime(0))
    attrs = w.attrs
    view = attrs[:view]
    empty!(view.long)
    empty!(view.short)
    empty!(view.last)
    s = attrs[:strategy]
    w[:symsdict] = symsdict(s)
    w[:processed_syms] = Set{Tuple{String,PositionSide}}()
    w[:process_tasks] = Task[]
    _exc!(attrs, exchange(s))
    _tfunc!(
        attrs,
        _w_positions_func(
            s, w, attrs[:interval]; iswatch=attrs[:iswatch], kwargs=w[:kwargs]
        ),
    )
end
function Watchers._stop!(w::Watcher, ::CcxtPositionsVal)
    handler = attr(w, :positions_handler, nothing)
    if !isnothing(handler)
        stop_handler!(handler)
    end
    pt = attr(w, :positions_task, nothing)
    if istaskrunning(pt)
        stop_task(pt)
        interval = attr(w, :interval, Second(5))
        to_time = now() + interval
        while !istaskdone(pt) && now() < to_time
            sleep(0.1)
        end
        if !istaskdone(pt)
            @warn "positions watcher: stopping task by exception" w = w.name
            kill_task(pt)
        end
    end
    if haskey(w, :stall_guard_task)
        stop_task(w[:stall_guard_task])
        delete!(w, :stall_guard_task)
    end
    nothing
end

@doc """ Processes any pending position messages from the exchange's internal message queue, parsing and pushing them to the watcher buffer for processing. Used to handle out-of-band position updates.

- `w`: The watcher object.
"""
function _positions_from_messages(w::Watcher)
    exc = w.exc
    messages = pygetattr(exc, "_positions_messages", nothing)
    if pyisjl(messages)
        tasks = @lget! w.attrs :message_tasks Task[]
        parse_func = exc.parsePositions
        vec = pyjlvalue(messages)
        if vec isa Vector
            while !isempty(vec)
                msg = popfirst!(vec)
                pup = parse_func(msg)
                _dopush!(w, pylist(pup))
                push!(tasks, @async process!(w))
            end
            filter!(!istaskdone, tasks)
        end
    end
end

function Watchers._fetch!(w::Watcher, ::CcxtPositionsVal)
    try
        _positions_from_messages(w)
        fetch_task = _positions_task(w)
        if !istaskrunning(fetch_task)
            _positions_task!(w)
        end
        true
    catch
        @debug_backtrace LogWatchPos
        false
    end
end

function Watchers._init!(w::Watcher, ::CcxtPositionsVal)
    default_init(
        w,
        (; long=PositionsDict2(), short=PositionsDict2(), last=Dict{String,PositionSide}()),
        false,
    )
    _lastpushed!(w, DateTime(0))
    _lastprocessed!(w, DateTime(0))
    _lastcount!(w, ())
end

function _posupdate(date, resp)
    PositionTuple((;
        date, notify=Base.Threads.Condition(), read=Ref(false), closed=Ref(false), resp
    ))
end
function _posupdate(prev, date, resp)
    prev.read[] = false
    PositionTuple((; date, prev.notify, prev.read, prev.closed, resp))
end
_deletek(py, k=@pyconst("info")) = haskey(py, k) && py.pop(k)
function _last_updated_position(long_dict, short_dict, sym)
    lp = get(long_dict, sym, nothing)
    sp = get(short_dict, sym, nothing)
    isnothing(sp) || (!isnothing(lp) && lp.date >= sp.date) ? Long() : Short()
end

@doc """ Processes positions for a watcher using the CCXT library.

$(TYPEDSIGNATURES)

This function processes positions for a watcher `w` using the CCXT library. It goes through the positions stored in the watcher and updates their status based on the latest data from the exchange. If a symbol `sym` is provided, it processes only the positions for that symbol, updating their status based on the latest data for that symbol from the exchange.

"""
function Watchers._process!(w::Watcher, ::CcxtPositionsVal; fetched=false)
    if isempty(w.buffer)
        return nothing
    end
    eid = typeof(exchangeid(_exc(w)))
    data_date, data = last(w.buffer)
    if !_positions_is_list(data)
        @debug "watchers pos process: wrong data type" _module = LogWatchPosProcess data_date typeof(
            data
        )
        _lastprocessed!(w, data_date)
        _lastcount!(w, ())
        return nothing
    end
    if _positions_already_processed(w, data_date, data)
        @debug "watchers pos process: already processed" _module = LogWatchPosProcess data_date
        return nothing
    end
    s = w[:strategy]
    long_dict = w.view.long
    short_dict = w.view.short
    last_dict = w.view.last
    processed_syms = empty!(w.processed_syms)
    iswatchevent = w[:iswatch] && !fetched
    if _positions_handle_empty_watch!(w, data_date, data, iswatchevent)
        return nothing
    end
    @debug "watchers pos process: position" _module = LogWatchPosProcess
    jobs = Ref(0)
    jobs_count_ref = Ref(0)
    max_date_ref = Ref(data_date + Millisecond(1))
    ctx = (;
        w,
        s,
        eid,
        iswatchevent,
        fetched,
        long_dict,
        short_dict,
        last_dict,
        processed_syms,
        jobs,
        jobs_count_ref,
    )
    for resp in data
        _positions_process_resp!(ctx, resp, data_date, max_date_ref)
    end
    _lastprocessed!(w, data_date)
    _lastcount!(w, data)
    _positions_finalize!(ctx, max_date_ref[])
    @debug "watchers pos process: done" _module = LogWatchPosProcess data_date
end

# Helpers for _process!
_positions_is_list(data) = islist(data)

@doc """ Checks if the given data for a watcher has already been processed, by comparing the data's date and length to the last processed values.

- `w`: The watcher object.
- `data_date`: The date of the data.
- `data`: The data to check.

Returns `true` if already processed, `false` otherwise.
"""
function _positions_already_processed(w, data_date, data)
    data_date == _lastprocessed(w) && length(data) == _lastcount(w)
end

@doc """ Handles the case where a watch event returns an empty list of positions. Marks the watcher as processed for this date and returns true if handled.

- `w`: The watcher object.
- `data_date`: The date of the data.
- `data`: The data to check.
- `iswatchevent`: Whether this is a watch event.

Returns `true` if handled, `false` otherwise.
"""
function _positions_handle_empty_watch!(w, data_date, data, iswatchevent)
    if iswatchevent && isempty(data)
        @debug "watchers pos process: nothing to process" _module = LogWatchPosProcess typeof(
            data
        ) data
        _lastprocessed!(w, data_date)
        _lastcount!(w, data)
        return true
    end
    false
end

@doc """ Processes a single position response, validating, checking staleness, and scheduling an update job if appropriate. Updates the max date reference if the position is newer.

- `ctx`: Context object with watcher and state.
- `resp`: The position response.
- `data_date`: The date of the data.
- `max_date_ref`: Reference to the maximum date seen so far.
"""
function _positions_process_resp!(ctx, resp, data_date, max_date_ref)
    # Validate and locate required structures
    lookup_result = _positions_validate_and_lookup!(ctx, resp, data_date)
    if lookup_result === nothing
        return nothing
    end
    push!(ctx.processed_syms, (lookup_result.sym, lookup_result.side))
    # Compute dates and staleness
    prev_side = get(ctx.last_dict, lookup_result.sym, lookup_result.side)
    this_date = _positions_compute_effective_date(
        ctx, lookup_result.prev_date, data_date, resp
    )
    if _positions_is_stale_update(ctx, lookup_result, resp, prev_side, this_date)
        return nothing
    end
    @debug "watchers pos process: position async" _module = LogWatchPosProcess islocked(
        lookup_result.ai
    ) islocked(lookup_result.pos_cond)
    max_date_ref[] = max(max_date_ref[], this_date)
    # Build pup and enqueue job
    pup = _positions_build_pup(lookup_result.pup_prev, this_date, resp)
    _positions_enqueue_update_job!(ctx, lookup_result, pup, resp)
end

# -- _positions_process_resp! helpers --

@doc """ Validates a position response and looks up the corresponding asset, side, and previous position state. Returns a named tuple with lookup results, or `nothing` if invalid or not found.

- `ctx`: Context object with watcher and state.
- `resp`: The position response.
- `data_date`: The date of the data.

Returns a named tuple with lookup results, or `nothing`.
"""
function _positions_validate_and_lookup!(ctx, resp, data_date)
    if !isdict(resp) || resp_event_type(resp, ctx.eid) != ot.PositionEvent
        @debug "watchers pos process: not a position update" resp _module =
            LogWatchPosProcess
        return nothing
    end
    sym = resp_position_symbol(resp, ctx.eid, String)
    ai = asset_bysym(ctx.s, sym, ctx.w.symsdict)
    if isnothing(ai)
        @debug "watchers pos process: no matching asset for symbol" _module =
            LogWatchPosProcess sym
        return nothing
    end
    default_side_func = Returns(_last_updated_position(ctx.long_dict, ctx.short_dict, sym))
    side = posside_fromccxt(resp, ctx.eid; default_side_func)
    side_dict = ifelse(islong(side), ctx.long_dict, ctx.short_dict)
    pup_prev = get(side_dict, sym, nothing)
    prev_date, pos_cond = if isnothing(pup_prev)
        ctx.w.started, Threads.Condition()
    else
        pup_prev.date, pup_prev.notify
    end
    if data_date <= prev_date
        return nothing
    else
        @debug "watchers pos process: scheduling" _module = LogWatchPosProcess data_date prev_date
    end
    return (; valid=true, sym, ai, side, side_dict, pup_prev, prev_date, pos_cond)
end

@doc """ Computes the effective date for a position update, preferring the response's date if available and newer, otherwise using the data date.

- `ctx`: Context object.
- `prev_date`: Previous date for this position.
- `data_date`: The date of the data.
- `resp`: The position response.

Returns the effective date as a `DateTime`.
"""
function _positions_compute_effective_date(ctx, prev_date, data_date, resp)
    resp_date = @something pytodate(resp, ctx.eid) ctx.w.started
    resp_date == prev_date ? data_date : resp_date
end

@doc """ Checks if a position update is stale (i.e., the response is identical to the previous one). Logs a warning if so.

- `ctx`: Context object.
- `lookup_result`: Result from `_positions_validate_and_lookup!`.
- `resp`: The position response.
- `prev_side`: The previous side for this position.
- `this_date`: The effective date for this update.

Returns `true` if the update is stale, `false` otherwise.
"""
function _positions_is_stale_update(ctx, lookup_result, resp, prev_side, this_date)
    if resp === get(@something(lookup_result.pup_prev, (;)), :resp, nothing)
        @warn "watchers pos process: received stale position update" lookup_result.sym lookup_result.side prev_side this_date lookup_result.prev_date resp_position_contracts(
            resp, ctx.eid
        ) resp_position_contracts(lookup_result.pup_prev.resp, ctx.eid)
        return true
    end
    return false
end

@doc """ Builds a new position update tuple (`pup`) for a given response, using the previous state if available.

- `pup_prev`: Previous position update tuple, or `nothing`.
- `this_date`: The effective date for this update.
- `resp`: The position response.

Returns a new `PositionTuple`.
"""
function _positions_build_pup(pup_prev, this_date, resp)
    if isnothing(pup_prev)
        _posupdate(this_date, resp)
    else
        _posupdate(pup_prev, this_date, resp)
    end
end

@doc """ Enqueues an update job for a position, which will update the position state and trigger cash sync if needed. Increments the job count reference.

- `ctx`: Context object.
- `lr`: Lookup result from `_positions_validate_and_lookup!`.
- `pup`: The new position update tuple.
- `resp`: The position response.
"""
function _positions_enqueue_update_job!(ctx, lr, pup, resp)
    function update_position_job()
        try
            @inlock lr.ai begin
                @debug "watchers pos process: internal lock" _module = LogWatchPosProcess lr.sym lr.side
                @lock lr.pos_cond begin
                    @debug "watchers pos process: processing" _module = LogWatchPosProcess lr.sym lr.side
                    if !isnothing(pup)
                        @debug "watchers pos process: unread" _module = LogWatchPosProcess contracts = resp_position_contracts(
                            pup.resp, ctx.eid
                        ) pup.date
                        pup.read[] = false
                        pup.closed[] = iszero(resp_position_contracts(pup.resp, ctx.eid))
                        prev_side = get(ctx.last_dict, lr.sym, lr.side)
                        mm = @something resp_position_margin_mode(
                            resp, ctx.eid, Val(:parsed)
                        ) marginmode(ctx.w[:strategy])
                        if mm isa IsolatedMargin &&
                            prev_side != lr.side &&
                            !isnothing(lr.pup_prev)
                            @deassert LogWatchPosProcess resp_position_side(
                                lr.pup_prev.resp, ctx.eid
                            ) |> _ccxtposside == prev_side
                            lr.pup_prev.closed[] = true
                            if ctx.iswatchevent
                                _live_sync_cash!(ctx.s, lr.ai, prev_side; pup=lr.pup_prev)
                            end
                        end
                        ctx.last_dict[lr.sym] = lr.side
                        lr.side_dict[lr.sym] = pup
                        if ctx.iswatchevent
                            @debug "watchers pos process: syncing" _module =
                                LogWatchPosProcess contracts = resp_position_contracts(
                                pup.resp, ctx.eid
                            ) length(lr.ai.events) timestamp(lr.ai, lr.side)
                            _live_sync_cash!(ctx.s, lr.ai, lr.side; pup)
                            @debug "watchers pos process: synced" _module =
                                LogWatchPosProcess contracts = resp_position_contracts(
                                pup.resp, ctx.eid
                            ) lr.side cash(lr.ai, lr.side) timestamp(lr.ai, lr.side) pup.date ctx.iswatchevent ctx.fetched length(
                                lr.ai.events
                            )
                        end
                        safenotify(lr.pos_cond)
                    else
                        @debug "watchers pos process: pup is nothing" _module =
                            LogWatchPosProcess get(
                            @something(lr.pup_prev, (;)), :date, nothing
                        )
                    end
                end
            end
        finally
            ctx.jobs[] = ctx.jobs[] + 1
        end
    end
    sendrequest!(lr.ai, pup.date, update_position_job)
    ctx.jobs_count_ref[] += 1
end

@doc """ Finalizes the processing of all position updates for a batch, waiting for all jobs to complete and then syncing flags and cash for all positions.

- `ctx`: Context object.
- `max_date`: The maximum date for this batch of updates.
"""
function _positions_finalize!(ctx, max_date)
    if ctx.iswatchevent
        return nothing
    end
    tasks = ctx.w[:process_tasks]
    function jobs_completed()
        ctx.jobs_count_ref[] == ctx.jobs[]
    end
    function finalize_flags_and_cash_sync()
        _setposflags!(ctx, max_date, ctx.long_dict, Long())
        _setposflags!(ctx, max_date, ctx.short_dict, Short())
        live_sync_universe_cash!(ctx.s)
    end
    t =
        (@async begin
            # wait for per-asset jobs to complete with proportional timeout
            waitforcond(jobs_completed, Second(15) * ctx.jobs_count_ref[])
            if ctx.jobs_count_ref[] < ctx.jobs[]
                @error "watchers pos process: positions update jobs timed out" jobs_count = ctx.jobs_count_ref[] jobs_completed = ctx.jobs[]
            end
            finalize_flags_and_cash_sync()
        end) |> errormonitor
    push!(tasks, t)
    filter!(!istaskdone, tasks)
    sendrequest!(ctx.s, max_date, () -> wait(t))
end

@doc """ Updates position flags for a symbol in a dictionary.

$(TYPEDSIGNATURES)

This function updates the position flags for a symbol in a dictionary when not using the `watch*` function. This is necessary in case the returned list of positions from the exchange does not include closed positions (that were previously open). When using `watch*` functions, it is expected that position close updates are received as new events.

"""
function _setposflags!(ctx, max_date, dict, side)
    @sync for (sym, pup) in dict
        ai = asset_bysym(ctx.s, sym, ctx.w.symsdict)
        @debug "watchers pos process: pos flags locking" _module = LogWatchPosProcess isownable(
            ai.lock
        ) isownable(pup.notify.lock)
        @async @lock pup.notify if !pup.closed[] && (sym, side) ∉ ctx.processed_syms
            @debug "watchers pos process: pos flags setting" _module = LogWatchPosProcess
            this_pup = dict[sym] = _posupdate(pup, max_date, pup.resp)
            this_pup.closed[] = true
            func = () -> _live_sync_cash!(ctx.s, ai, side; pup=this_pup)
            sendrequest!(ai, max_date, func)
        end
    end
end

function _setunread!(w)
    data = w.view
    map(v -> (v.read[] = false), values(data.long))
    map(v -> (v.read[] = false), values(data.short))
end

positions_watcher(s) = s[:live_positions_watcher]

# function _load!(w::Watcher, ::ThisVal) end

# function _process!(w::Watcher, ::ThisVal) end
