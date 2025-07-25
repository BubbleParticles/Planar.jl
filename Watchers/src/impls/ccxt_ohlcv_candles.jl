using Watchers.WatchersImpls:
    _resolve,
    _curdate,
    _tfr,
    _ids,
    Watcher,
    handler_task!,
    check_task!,
    stop_handler_task!,
    getexchange!,
    _exc!,
    _check_ids
using Watchers: logerror
using Base: Semaphore, acquire, release, ReentrantLock, current_task
using .Data: DataFrame
using .Misc: period

const PRICE_SOURCES = (:last, :vwap, :bid, :ask)
const CcxtOHLCVCandlesVal = Val{:ccxt_ohlcv_candles}

baremodule LogOHLCVWatcher end

function ccxt_ohlcv_candles_watcher(
    exc::Exchange,
    syms;
    timeframe=tf"1m",
    logfile=nothing,
    buffer_capacity=100,
    view_capacity=count(timeframe, tf"1d") + 1 + buffer_capacity,
    default_view=nothing,
    n_jobs=ratelimit_njobs(exc),
    callback=Returns(nothing),
    load_timeframe=default_load_timeframe(timeframe),
    load_path=nothing,
    kwargs...,
)
    a = Dict{Symbol,Any}()
    a[k"ids"] = [string(v) for v in syms]
    a[k"issandbox"] = issandbox(exc)
    a[k"excparams"] = params(exc)
    a[k"excaccount"] = account(exc)
    a[k"ohlcv_method"] = :candles
    @setkey! a exc
    @setkey! a default_view
    @setkey! a timeframe
    @setkey! a n_jobs
    @setkey! a callback
    a[k"minrows_warned"] = false
    a[k"sem"] = Base.Semaphore(n_jobs)
    a[k"key"] = string(
        "ccxt_",
        exc.name,
        "_",
        issandbox(exc) ? "sb" : "",
        "_ohlcv_candles_",
        hash(a[k"ids"]),
    )
    a[k"load_timeframe"] = load_timeframe
    a[:load_path] = load_path
    if !isnothing(logfile)
        @setkey! a logfile
    end
    watcher_type = Py
    wid = string(
        CcxtOHLCVCandlesVal.parameters[1], "-", hash((exc.id, syms, a[k"issandbox"]))
    )
    w = watcher(
        watcher_type,
        wid,
        CcxtOHLCVCandlesVal();
        start=false,
        load=false,
        flush=false,
        process=false,
        buffer_capacity,
        view_capacity,
        fetch_interval=Second(1),
        attrs=a,
    )
    w
end

_fetch!(w::Watcher, ::CcxtOHLCVCandlesVal; sym=nothing) = _tfunc(w)()

@kwdef mutable struct CandleWatcherSymbolState4
    const sym::String
    const lock::ReentrantLock = ReentrantLock()
    loaded::Bool = false
    backoff::Int8 = 0
    isprocessed::Bool = false
    processed_time::DateTime = DateTime(0)
    nextcandle::Any = ()
    is_resyncing::Bool = false
end

function _init!(w::Watcher, ::CcxtOHLCVCandlesVal)
    _view!(w, default_view(w, Dict{String,DataFrame}))
    _checkson!(w)
end

_process!(::Watcher, ::CcxtOHLCVCandlesVal) = nothing

function _start!(w::Watcher, ::CcxtOHLCVCandlesVal)
    a = w.attrs
    a[k"sem"] = Base.Semaphore(a[k"n_jobs"])
    a[k"symstates"] = Dict(sym => CandleWatcherSymbolState4(; sym) for sym in _ids(w))
    _reset_candles_func!(w)
end

_stop!(w::Watcher, ::CcxtOHLCVCandlesVal) = begin
    if haskey(w.attrs, :handlers)
        for sym in _ids(w)
            stop_handler_task!(w, sym)
        end
    elseif haskey(w.attrs, :handler)
        stop_handler_task!(w)
    end
end

function _perform_locked_resync(w::Watcher, sym::String)
    @debug "Watchers: _perform_locked_resync called for $sym. Attempting to acquire symbol lock."
    start_time_overall = time_ns()
    local resolve_successful = false # To track if _resolve itself succeeded
    try
        lock(w.symstates[sym].lock) do
            @debug "Watchers: Symbol lock acquired for $sym."
            start_time_resolve = time_ns()
            try
                # THE ACTUAL CALL TO _resolve:
                _resolve(w, w.view[sym], _curdate(_tfr(w)), sym)

                elapsed_ms_resolve = (time_ns() - start_time_resolve) / 1_000_000
                @debug "Watchers: _resolve completed for $sym in $(round(elapsed_ms_resolve, digits=2)) ms."
                resolve_successful = true
            catch err
                elapsed_ms_resolve = (time_ns() - start_time_resolve) / 1_000_000
                @error "Watchers: Error during _resolve for $sym after $(round(elapsed_ms_resolve, digits=2)) ms (within lock)" exception = (
                    err, catch_backtrace()
                )
                rethrow()
            end
        end # Lock is released here

        # Logs after lock is released
        elapsed_ms_overall = (time_ns() - start_time_overall) / 1_000_000
        if resolve_successful
            @debug "Watchers: _perform_locked_resync successfully finished for $sym in $(round(elapsed_ms_overall, digits=2)) ms (lock was acquired and released)."
        else
            # This path would typically not be hit if _resolve errors and rethrows,
            # as the exception would be caught by the outer try-catch.
            # However, it's here for logical completeness if _resolve could error without rethrowing to here.
            @warn "Watchers: _perform_locked_resync finished for $sym in $(round(elapsed_ms_overall, digits=2)) ms, but _resolve may have failed or did not run (lock was acquired and released)."
        end

    catch outer_err # Catches errors from lock acquisition or if rethrow() from _resolve's catch block propagates
        elapsed_ms_overall = (time_ns() - start_time_overall) / 1_000_000
        @error "Watchers: Error in _perform_locked_resync for $sym (e.g., lock acquisition failed or error propagated from _resolve) after $(round(elapsed_ms_overall, digits=2)) ms." exception = (
            outer_err, catch_backtrace()
        )
        rethrow() # Ensure the calling async task knows about the failure
    end
end

@doc """ Loads the OHLCV data for a specific symbol.

$(TYPEDSIGNATURES)

This function loads the OHLCV data for a specific symbol.
If the symbol is not being tracked by the watcher or if the data for the symbol has already been loaded, the function returns nothing.

"""
_load!(w::Watcher, ::CcxtOHLCVCandlesVal, sym) = _load_ohlcv!(w, sym)

@doc """ Loads the OHLCV data for all symbols.

$(TYPEDSIGNATURES)

This function loads the OHLCV data for all symbols.
If the buffer or view of the watcher is empty, the function returns nothing.

"""
_loadall!(w::Watcher, ::CcxtOHLCVCandlesVal) = _load_all_ohlcv!(w)
isemptish(v) = isnothing(v) || isempty(v)

function _reset_candles_func!(w)
    attrs = w.attrs
    eid = exchangeid(_exc(w))
    exc = getexchange!(
        eid, attrs[k"excparams"]; sandbox=attrs[k"issandbox"], account=attrs[k"excaccount"]
    )
    _exc!(attrs, exc)
    # don't pass empty args to imply all symbols
    ids = _check_ids(exc, _ids(w))
    @assert ids isa Vector && !isempty(ids) "ohlcv (candles)  no symbols to watch given"
    tf = _tfr(w)
    tf_str = string(tf)
    init_tasks = @lget! attrs k"process_tasks" Set{Task}()
    function init_func()
        for sym in ids
            push!(
                init_tasks,
                @async begin
                    @lock w.symstates[sym].lock @acquire w.sem _ensure_ohlcv!(w, sym)
                    delete!(init_tasks, current_task())
                end
            )
        end
    end
    if has(exc, :watchOHLCVForSymbols)
        watch_func = exc.watchOHLCVForSymbols
        wrapper_func = _update_ohlcv_func(w)
        syms = [@py([sym, tf_str]) for sym in ids]
        corogen_func = (_) -> coro_func() = watch_func(syms)
        handler_task!(w; init_func, corogen_func, wrapper_func, if_func=!isemptish)
        _tfunc!(attrs, () -> check_task!(w))
    elseif has(exc, :watchOHLCV)
        w[:handlers] = Dict{String,WatcherHandler2}()
        watch_func = exc.watchOHLCV
        syms = [(sym, tf) for sym in ids]
        for sym in ids
            wrapper_func = _update_ohlcv_func_single(w, sym)
            corogen_func = (_) -> coro_func() = watch_func(sym; timeframe=tf_str)
            handler_task!(w, sym; init_func, corogen_func, wrapper_func, if_func=!isemptish)
        end
        check_all_handlers() = all(check_task!(w, sym) for sym in ids)
        _tfunc!(attrs, check_all_handlers)
    else
        error(
            "ohlcv (candles) watcher only works with exchanges that support `watchOHLCVforSymbols` functions",
        )
    end
end

# Helper function to DRY the resync logic
function maybe_schedule_resync!(w, sym, state, snap=nothing)
    should_resync = lock(state.lock) do
        if !state.is_resyncing
            state.is_resyncing = true
            true
        else
            false
        end
    end
    if should_resync
        @debug "Watchers: Scheduling async resync for $sym"
        @async begin
            @debug "Watchers: Async task for $sym attempting to acquire semaphore"
            try
                Base.acquire(w.attrs[k"sem"]) # Acquire global semaphore
                @debug "Watchers: Async task for $sym acquired semaphore"
                try
                    _perform_locked_resync(w, sym)
                finally
                    # Ensure symbol-specific resync flag is reset even if _perform_locked_resync errors
                    lock(w.symstates[sym].lock) do
                        w.symstates[sym].is_resyncing = false
                    end
                end
            catch err
                logerror(
                    w,
                    err,
                    catch_backtrace(),
                    "Async OHLCV resync task manager failed for $sym",
                )
                # Also reset the flag in case of error acquiring semaphore or other top-level async error
                lock(w.symstates[sym].lock) do # Attempt to lock and reset
                    if w.symstates[sym].is_resyncing # Check if it's still true
                        w.symstates[sym].is_resyncing = false
                    end
                end
            finally
                Base.release(w.attrs[k"sem"]) # Release global semaphore
            end
        end
    end
    return should_resync
end

function _update_ohlcv_func(w)
    view = _view(w)
    tf = _tfr(w)
    tf_str = string(tf)
    symstates = w.symstates
    sem = w.sem
    function ohlcv_wrapper_func(snap)
        if snap isa Exception
            @error "ohlcv (candles): exception" exception = snap
            return nothing
        elseif !isdict(snap)
            @error "ohlcv (candles): unknown value" snap
            return nothing
        end
        latest_ts = apply(tf, now())
        for (sym, tf_candles) in snap
            state = symstates[sym]::CandleWatcherSymbolState4
            @lock state.lock begin
                this_df = view[sym]
                if isempty(this_df)
                    @debug "ohlcv (candles): waiting for startup fetch" _module =
                        LogOHLCVWatcher sym
                    maybe_schedule_resync!(w, sym, state)
                    state.nextcandle = tf_candles
                    continue
                end
                next_ts = _nextdate(this_df, tf)
                if islast(lastdate(this_df), tf) || next_ts == latest_ts
                    # df is already updated
                    state.nextcandle = tf_candles
                    continue
                end
                for (this_tf_str, candles) in state.nextcandle
                    if this_tf_str == tf_str
                        for cdl in candles
                            cdl_ts = apply(tf, first(cdl) |> dt)
                            if cdl_ts == next_ts
                                tup = (cdl_ts, (pytofloat(cdl[idx]) for idx in 2:6)...)
                                push!(this_df, tup)
                                next_ts += tf
                            end
                        end
                        if next_ts + tf < latest_ts
                            @debug "ohlcv (candles): out of sync, resolving" sym next_ts tf latest_ts
                            maybe_schedule_resync!(w, sym, state)
                        end
                    end
                end
                invokelatest(w[k"callback"], this_df, sym)
                state.nextcandle = tf_candles
            end
        end
        snap.py
    end
end

function _update_ohlcv_func_single(w, sym)
    view = _view(w)
    tf = _tfr(w)
    state = w.symstates[sym]::CandleWatcherSymbolState4
    sem = w.sem
    handlers = w.handlers
    function ohlcv_wrapper_func(snap)
        if snap isa Exception
            @error "ohlcv (candles): exception" exception = snap
            return nothing
        elseif !islist(snap)
            @error "ohlcv (candles): unknown value" snap
            return nothing
        end
        @lock state.lock begin
            df = get(view, sym, nothing)
            if isnothing(df) || isempty(df)
                maybe_schedule_resync!(w, sym, state, snap)
                state.nextcandle = snap
                @debug "ohlcv (candles): waiting for startup fetch" _module =
                    LogOHLCVWatcher sym
                return nothing
            end
            latest_ts = apply(tf, now())
            next_ts::DateTime = _nextdate(df, tf)
            if islast(lastdate(df), tf) || next_ts >= latest_ts
                state.nextcandle = snap
                # df is already updated
                return nothing
            end
            for cdl in state.nextcandle
                cdl_ts = apply(tf, first(cdl) |> dt)
                if cdl_ts == next_ts
                    tup = (cdl_ts, (pytofloat(cdl[idx]) for idx in 2:6)...)
                    push!(df, tup)
                    next_ts = cdl_ts
                    break
                end
            end
            if next_ts + tf < latest_ts && isempty(handlers[sym].buffer)
                @debug "ohlcv (candles): out of sync, resolving" sym next_ts tf latest_ts
                maybe_schedule_resync!(w, sym, state, snap)
            end
            invokelatest(w[k"callback"], df, sym)
            state.nextcandle = snap
            snap.py
        end
    end
end
