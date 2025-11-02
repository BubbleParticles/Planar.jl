using Watchers
using Watchers: default_init
using Watchers.WatchersImpls:
    _tfunc!,
    _tfunc,
    _exc!,
    _exc,
    _lastpushed!,
    _lastpushed,
    _lastprocessed!,
    _lastprocessed,
    _lastcount!,
    _lastcount
@watcher_interface!
using .Exchanges: check_timeout
using .Exchanges.Python: @py
using .Lang: splitkws, withoutkws, safenotify, safewait

const CcxtBalanceVal = Val{:ccxt_balance_val}

@doc """ Sets up a watcher for CCXT balance.

$(TYPEDSIGNATURES)

This function sets up a watcher for balance in the CCXT library. The watcher keeps track of the balance and updates it as necessary.
"""
function ccxt_balance_watcher(
    s::Strategy;
    interval=Second(1),
    wid="ccxt_balance",
    buffer_capacity=10,
    start=false,
    params=LittleDict{Any,Any}(),
    kwargs...,
)
    exc = st.exchange(s)
    check_timeout(exc, interval)
    attrs = Dict{Symbol,Any}()
    params["type"] = @pystr(lowercase(string(balance_type(s))))
    _exc!(attrs, exc)
    attrs[:strategy] = s
    attrs[:iswatch] = @lget! s.attrs :is_watch_balance has(exc, :watchBalance)
    attrs[:func_kwargs] = (; params, kwargs...)
    attrs[:interval] = interval
    watcher_type = Py
    wid = string(wid, "-", hash((exc.id, nameof(s), account(s))))
    watcher(
        watcher_type,
        wid,
        CcxtBalanceVal();
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

@doc """
Returns true if the data is a dictionary and the event type matches BalanceUpdated.
"""
function _balance_valid_event_data(eid, data)
    isdict(data) && resp_event_type(data, eid) == ot.BalanceUpdated
end

@doc """
Checks if the data for the given date has already been processed.
"""
function _balance_is_already_processed(w, data_date, data)
    data_date == _lastprocessed(w) && length(data) == _lastcount(w)
end

@doc """
Returns true if the current date matches the view's date, and updates last processed.
"""
function _balance_is_same_view_date(w, data_date, date)
    if date == w.view.date
        _lastprocessed!(w, data_date)
        return true
    end
    false
end

@doc """
Returns the upper and lower case quote-currency symbols for the strategy.
"""
function _balance_qc_syms(w, s)
    @lget! attrs(w) :qc_syms begin
        upper = nameof(cash(s))
        lower = string(upper) |> lowercase |> Symbol
        upper, lower
    end
end

@doc """
Computes the free balance, falling back to total - assets_value if free is zero.
"""
function _balance_compute_free(total, free, assets_value)
    if iszero(free)
        return max(zero(total), total - assets_value)
    end
    free
end

@doc """
Computes used balance for quote-currency by summing unfilled order values.
"""
function _balance_compute_used_for_qc!(used, s)
    for o in orders(s)
        if o isa IncreaseOrder
            used += unfilled(o) * o.price
        end
    end
    used
end

@doc """
Computes used balance for a specific asset by summing unfilled reduce orders.
"""
function _balance_compute_used_for_asset!(used, s, ai)
    for o in orders(s, ai)
        if o isa ReduceOrder
            used += unfilled(o)
        end
    end
    used
end

@doc """
Computes the used balance for a symbol, using custom logic if value is zero.
"""
function _balance_compute_used(sym_bal, isqc, s, symsdict, sym)
    v = get_float(sym_bal, "used")
    if iszero(v)
        used = v
        if isqc
            return _balance_compute_used_for_qc!(used, s)
        else
            ai = asset_bysym(s, string(sym), symsdict)
            if !isnothing(ai)
                return _balance_compute_used_for_asset!(used, s, ai)
            end
        end
        return used
    else
        return v
    end
end

@doc """
Updates or creates a BalanceSnapshot for the given symbol and date.
"""
function _balance_update_snapshot!(baldict, k, date, sym, total, free, used)
    if haskey(baldict, k)
        update!(baldict[k], date; total, free, used)
        return baldict[k]
    else
        baldict[k] = BalanceSnapshot(; currency=sym, date, total, free, used)
        return baldict[k]
    end
end

@doc """
Dispatches sync events for updated balances, depending on asset type.
"""
function _balance_dispatch_events!(w, s, isqc, bal, sym, symsdict)
    if isqc
        s_events = get_events(s)
        func = () -> _live_sync_strategy_cash!(s; bal)
        sendrequest!(s, bal.date, func)
    elseif s isa NoMarginStrategy
        ai = asset_bysym(s, sym, symsdict)
        if !isnothing(ai)
            func = () -> _live_sync_cash!(s, ai; bal)
            sendrequest!(ai, bal.date, func)
        end
    end
    nothing
end

@doc """
Processes and updates the balance for a single symbol.
"""
function _balance_process_symbol!(
    w, s, symsdict, baldict, qc_upper, qc_lower, sym, sym_bal, date, assets_value
)
    if isdict(sym_bal) && haskey(sym_bal, @pyconst("free"))
        k = Symbol(sym)
        total = get_float(sym_bal, "total")
        free = _balance_compute_free(total, get_float(sym_bal, "free"), assets_value)
        isqc = k == qc_upper || k == qc_lower
        used = _balance_compute_used(sym_bal, isqc, s, symsdict, sym)
        bal = _balance_update_snapshot!(baldict, k, date, sym, total, free, used)
        _balance_dispatch_events!(w, s, isqc, bal, sym, symsdict)
    end
    nothing
end

@doc """
Initializes and returns the state for the balance watcher, including buffers and tasks.
"""
function _balance_setup_state!(s, w, attrs)
    exc = exchange(s)
    timeout = throttle(s)
    interval = attrs[:interval]
    params, rest = _ccxt_balance_args(s, attrs[:func_kwargs])
    buffer_size = attr(s, :live_buffer_size, 1000)
    s[:balance_buffer] = w[:buf_process] = buf = Vector{Any}()
    s[:balance_notify] = w[:buf_notify] = buf_notify = Condition()
    sizehint!(buf, buffer_size)
    tasks = w[:process_tasks] = Vector{Task}()
    errors = w[:errors_count] = Ref(0)
    (
        s=s,
        w=w,
        attrs=attrs,
        exc=exc,
        timeout=timeout,
        interval=interval,
        params=params,
        rest=rest,
        buf=buf,
        buf_notify=buf_notify,
        tasks=tasks,
        errors=errors,
    )
end

@doc """
Starts a background task to force fetch if the watcher stalls for too long.
"""
function _balance_setup_stall_guard!(state)
    s = state.s
    w = state.w
    attrs = state.attrs
    if haskey(w, :stall_guard_task)
        stop_task(w[:stall_guard_task])
        delete!(w, :stall_guard_task)
    end
    w[:stall_guard_task] = @start_task IdDict() begin
        while isstarted(w)
            try
                last = _lastprocessed(w)
                if now() - last > Second(60)
                    @warn "balance watcher: forcing fetch due to stall" last now() s
                    _force_fetchbal(s; fallback_kwargs=attrs[:func_kwargs])
                end
            catch e
                @warn "balance watcher: stall guard error" exception = e
            end
            sleep(10)
        end
        @debug "balance watcher: stall guard task stopped" _module = LogWatchBalProcess
    end
end

@doc """
Processes a new balance value, pushing it to the buffer and starting processing tasks.
"""
function _balance_process_bal!(state, w, v)
    if !isnothing(v)
        if !isnothing(_dopush!(w, v; if_func=isdict))
            push!(state.tasks, @async process!(w))
            filter!(!istaskdone, state.tasks)
        end
    end
    nothing
end

@doc """
Initializes the balance watcher and its handler.
"""
function _balance_init_watch!(state)
    s = state.s
    w = state.w
    v = @lock w fetch_balance(s; state.timeout, state.params, state.rest...)
    _balance_process_bal!(state, w, v)
    state_init = Ref(false)
    f_push(v) = begin
        push!(state.buf, v)
        notify(state.buf_notify)
        maybe_backoff!(state.errors, v)
    end
    h =
        w[:balance_handler] = watch_balance_handler(
            state.exc; f_push, state.params, state.rest...
        )
    start_handler!(h)
    state_init
end

@doc """
Returns a closure that steps the balance watcher, initializing if needed.
"""
function _balance_watch_closure(state)
    init_ref = Ref(true)
    function _balance_watch_do_init!()
        if init_ref[]
            _ = _balance_init_watch!(state)
            init_ref[] = false
        end
        nothing
    end
    function balance_watch_step(w)
        _balance_watch_do_init!()
        while isempty(state.buf) && isstarted(w)
            wait(state.buf_notify)
        end
        if !isempty(state.buf)
            v = popfirst!(state.buf)
            if v isa Exception
                @error "balance watcher: unexpected value" exception = v
                maybe_backoff!(state.errors, v)
                sleep(1)
            else
                _balance_process_bal!(state, w, pydict(v))
            end
        end
        nothing
    end
    balance_watch_step
end

@doc """
Flushes the buffer, processing all pending balance values.
"""
function _balance_flush_buf_notify!(state, w)
    while !isempty(state.buf)
        v = popfirst!(state.buf)
        _dopush!(w, v)
        push!(state.tasks, @async process!(w))
        filter!(!istaskdone, state.tasks)
    end
end

@doc """
Returns a closure that fetches and processes balance updates periodically.
"""
function _balance_fetch_closure(state)
    s = state.s
    function balance_fetch_step(w)
        start = now()
        try
            _balance_flush_buf_notify!(state, w)
            v = @lock w fetch_balance(s; state.timeout, state.params, state.rest...)
            _dopush!(w, v; if_func=isdict)
            push!(state.tasks, @async process!(w))
            _balance_flush_buf_notify!(state, w)
            filter!(!istaskdone, state.tasks)
        finally
            sleep_pad(start, state.interval)
        end
        nothing
    end
    balance_fetch_step
end

@doc """
Returns the appropriate balance watcher function (watch or fetch) based on attrs.
"""
function _w_balance_func(s, w, attrs)
    state = _balance_setup_state!(s, w, attrs)
    if attrs[:iswatch]
        _balance_setup_stall_guard!(state)
        return _balance_watch_closure(state)
    else
        return _balance_fetch_closure(state)
    end
end

@doc """
Starts the main balance watcher task for the watcher.
"""
function _balance_task!(w)
    f = _tfunc(w)
    errors = w.errors_count
    w[:balance_task] = (@async while isstarted(w)
        try
            f(w)
            safenotify(w.beacon.fetch)
        catch e
            if e isa InterruptException
                break
            else
                maybe_backoff!(errors, e)
                @debug_backtrace LogWatchBalance
            end
        end
    end) |> errormonitor
end

_balance_task(w) = @lget! attrs(w) :balance_task _balance_task!(w)

function Watchers._stop!(w::Watcher, ::CcxtBalanceVal)
    handler = attr(w, :balance_handler, nothing)
    if !isnothing(handler)
        stop_handler!(handler)
    end
    if haskey(w, :stall_guard_task)
        stop_task(w[:stall_guard_task])
        delete!(w, :stall_guard_task)
    end
    notify(w.buf_notify)
    nothing
end

function Watchers._fetch!(w::Watcher, ::CcxtBalanceVal)
    fetch_task = _balance_task(w)
    if !istaskrunning(fetch_task)
        _balance_task!(w)
    end
    return true
end

function _init!(w::Watcher, ::CcxtBalanceVal)
    default_init(w, BalanceDict(), false)
    _lastpushed!(w, DateTime(0))
    _lastprocessed!(w, DateTime(0))
    _lastcount!(w, ())
end

@doc """ Processes balance for a watcher using the CCXT library.

$(TYPEDSIGNATURES)

This function processes balance for a watcher `w` using the CCXT library. It goes through the balance stored in the watcher and updates it based on the latest data from the exchange.

"""
function Watchers._process!(w::Watcher, ::CcxtBalanceVal; fetched=false)
    # No-op if there is nothing new in the ring buffer
    if isempty(w.buffer)
        return nothing
    end
    # Read the last fetched event from the exchange and the current balance view
    eid = typeof(exchangeid(_exc(w)))
    data_date, data = last(w.buffer)
    baldict = w.view.assets
    if !_balance_valid_event_data(eid, data)
        # Ignore unrelated/unexpected payloads but advance processed watermark
        @debug "balance watcher: wrong data type" _module = LogWatchBalProcess data_date typeof(
            data
        )
        _lastprocessed!(w, data_date)
        _lastcount!(w, ())
        return nothing
    end
    if _balance_is_already_processed(w, data_date, data)
        # Skip if same payload already handled (idempotency)
        @debug "balance watcher: already processed" _module = LogWatchBalProcess data_date
        return nothing
    end
    # Use exchange provided timestamp if present, else fallback to now
    date = @something pytodate(data, eid) now()
    if _balance_is_same_view_date(w, data_date, date)
        return nothing
    end
    # Strategy context and helpers for per-asset processing
    s = w.strategy
    symsdict = w.symsdict
    # Compute current non-cash asset valuation to derive a conservative free amount when free==0
    assets_value = current_total(s; bal=w.view) - s.cash
    # Resolve quote-currency symbols once (upper/lower forms)
    qc_upper, qc_lower = _balance_qc_syms(w, s)
    # Update per-currency balances and dispatch sync events
    for (sym, sym_bal) in data.items()
        _balance_process_symbol!(
            w, s, symsdict, baldict, qc_upper, qc_lower, sym, sym_bal, date, assets_value
        )
    end
    # Commit view timestamp and watermarks
    w.view.date = date
    _lastprocessed!(w, data_date)
    _lastcount!(w, data)
    @debug "balance watcher data:" _module = LogWatchBalProcess date get(baldict, :BTC, nothing) 
end

@doc """ Starts a watcher for balance in a live strategy.

$(TYPEDSIGNATURES)

This function starts a watcher for balance in a live strategy `s`. The watcher checks and updates the balance at a specified interval.

"""
function watch_balance!(s::LiveStrategy; interval=st.throttle(s), wait=false)
    @debug "live: watch balance get" _module = LogWatchBalance islocked(s)
    w = @lock s @lget! s :live_balance_watcher ccxt_balance_watcher(s; interval)
    just_started = if isstopped(w) && !attr(s, :stopped, false)
        @debug "live: locking" _module = LogWatchBalance
        @lock w if isstopped(w)
            @debug "live: start" _module = LogWatchBalance
            start!(w)
            @debug "live: started" _module = LogWatchBalance
            true
        else
            @debug "live: already started" _module = LogWatchBalance
            false
        end
    else
        false
    end
    while wait && just_started && _lastprocessed(w) == DateTime(0)
        @debug "live: waiting for initial balance" _module = LogWatchBalance
        safewait(w.beacon.process)
    end
    w
end

@doc """ Stops the watcher for balance in a live strategy.

$(TYPEDSIGNATURES)

This function stops the watcher that is tracking and updating balance for a live strategy `s`.

"""
function stop_watch_balance!(s::LiveStrategy)
    w = get(s.attrs, :live_balance_watcher, nothing)
    if w isa Watcher
        @debug "live: stopping balance watcher" _module = LogWatchBalance islocked(w)
        if isstarted(w)
            stop!(w)
        end
        @debug "live: balance watcher stopped" _module = LogWatchBalance
    end
end

@doc """ Retrieves the balance watcher for a live strategy.

$(TYPEDSIGNATURES)
"""
balance_watcher(s) = s[:live_balance_watcher]

# function _load!(w::Watcher, ::CcxtBalanceVal) end

# function _process!(w::Watcher, ::CcxtBalanceVal) end

function _start!(w::Watcher, ::CcxtBalanceVal)
    _lastprocessed!(w, DateTime(0))
    attrs = w.attrs
    view = attrs[:view]
    reset!(view)
    s = attrs[:strategy]
    w[:symsdict] = symsdict(s)
    exc = exchange(s)
    _exc!(attrs, exc)
    _tfunc!(attrs, _w_balance_func(s, w, attrs))
end
