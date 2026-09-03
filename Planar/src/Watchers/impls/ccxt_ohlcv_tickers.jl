using PlanarCore.Data: OHLCV_COLUMNS, contiguous_ts
using PlanarCore.Data.DFUtils: lastdate, dateindex
using PlanarCore.Misc: between, truncate_file
using PlanarCore.Fetch.Processing: iscomplete, fill_missing_candles!
using PlanarCore.Fetch.Exchanges: ratelimit_njobs
using PlanarCore.Lang: fromstruct, ifproperty!, ifkey!, @acquire, @add_statickeys!, @k_str
using ..Watchers: @logerror, _val, default_view, buffer, watcher_tasks

const PRICE_SOURCES = (:last, :vwap, :bid, :ask)
const CcxtOHLCVTickerVal = Val{:ccxt_ohlcv_ticker}

baremodule LogOHLCVTickers end

@add_statickeys! begin
    tickers_ohlcv
    price_source
    diff_volume
    volume_divisor
    stale_candle
    stale_df
    callback
    vwap
    minrows_warned
    symstates
end

@doc """OHLCV watcher based on exchange tickers data. This differs from the ohlcv watcher based on trades.

- The OHLCV ticker watcher can monitor a group of symbols, while the trades watcher only one symbol per instance.
- The OHLCV ticker watcher candles do not match 1:1 the exchange candles, since they rely on polled data.
- The OHLCV ticker watcher is intended to be *lazy*. It won't pre-load/fetch data for all symbols, it will only
process new candles from the time it is started w.r.t. the timeframe provided.
- The source price chooses which price to use to build the candles any of `:last`, `:vwap`, `:bid`, `:ask` (default `:last`).

To back-fill the *view* (DataFrame) of a particular symbol, call `load!(watcher, symbol)`, which will fill
the view up to the watcher `view_capacity`.

- `logfile`: optional path to save errors.
- `diff_volume`: calculate volume by subtracting the rolling 1d snapshots (`true`)
- `n_jobs`: concurrent startup fetching jobs for ohlcv
- `callback`: function `fn(df, sym)` called every time a dataframe is updated

!!! "warning" startup times
    The higher the number of symbols, the longer it will take to load initial OHLCV candles. When the semaphore (`w[:sem]`) is not full anymore, all the symbols should then start to trail the latest (full) candle as soon as possible.
"""
function ccxt_ohlcv_tickers_watcher(
    exc::Exchange;
    price_source=:last,
    diff_volume=true,
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
    w = ccxt_tickers_watcher(
        exc;
        val=CcxtOHLCVTickerVal(),
        wid=CcxtOHLCVTickerVal.parameters[1],
        start=false,
        load=false,
        process=true,
        view_capacity,
        buffer_capacity,
        kwargs...,
    )

    a = attrs(w)
    @assert price_source ∈ PRICE_SOURCES "price_source $price_source is not one of: $PRICE_SOURCES"
    @setkey! a price_source
    @setkey! a default_view
    @setkey! a timeframe
    @setkey! a n_jobs
    @setkey! a callback
    @setkey! a diff_volume
    a[k"ohlcv_method"] = :tickers
    a[k"minrows_warned"] = false
    a[k"tickers_ohlcv"] = true
    a[k"sem"] = Base.Semaphore(n_jobs)
    a[k"volume_divisor"] = Day(1) / period(timeframe)
    a[k"status"] = Pending()
    a[k"key"] = string(
        "ccxt_",
        exc.name,
        "_",
        issandbox(exc) ? "sb" : "",
        "_ohlcv_tickers_",
        hash(a[k"ids"]),
    )
    a[k"load_timeframe"] = load_timeframe
    a[:load_path] = load_path
    if !isnothing(logfile)
        @setkey! a logfile
    end
    w
end

function _fetch!(w::Watcher, ::CcxtOHLCVTickerVal; sym=nothing)
    _fetch!(w, CcxtTickerVal())
    _checkforstale(w)
    true
end

@doc """ A mutable struct representing a temporary candlestick chart.

$(FIELDS)

The `TempCandle` struct holds the timestamp, open, high, low, close, and volume values for a temporary candlestick chart.

"""
@kwdef mutable struct TempCandle{T}
    timestamp::DateTime = DateTime(0)
    open::T = NaN
    high::T = -Inf
    low::T = Inf
    close::T = NaN
    volume::T = 0
    TempCandle(args...; kwargs...) = begin
        new{DFT}(args...; kwargs...)
    end
end

@kwdef mutable struct TickerWatcherSymbolState2
    const sym::String
    const temp::TempCandle = TempCandle()
    const lock::ReentrantLock = ReentrantLock()
    loaded::Bool = false
    daily_volume::DFT = 0.0
    max_base::DFT = 0.0
    prev_quote_volume::DFT = 0.0
    curr_quote_volume::DFT = 0.0
    last_diff_ts::DateTime = DateTime(0)
    ticks::Int16 = 0
    backoff::Int8 = 0
    isprocessed::Bool = false
    processed_time::DateTime = DateTime(0)
end

@doc """ Initializes the watcher for the OHLCV ticker.

$(TYPEDSIGNATURES)

This function initializes the watcher with default view, temporary OHLCV, candle ticks, loaded symbols, and symbol locks.
It also initializes the symbols and checks for the watcher.

"""
function _init!(w::Watcher, ::CcxtOHLCVTickerVal)
    _view!(w, default_view(w, Dict{String,DataFrame}))
    a = attrs(w)
    a[:last_processed] = typemax(DateTime)
    _checkson!(w)
end

@doc """ Resets the temporary candlestick chart with a new timestamp and price.

$(TYPEDSIGNATURES)

This function resets the temporary candlestick chart with a new timestamp and price.
It also resets the high and low prices to their extreme values and the volume to zero if the price source is not `vwap`.

"""
resetcandle!(w, cdl::TempCandle, ts, price) = begin
    cdl.timestamp = ts
    cdl.open = price
    cdl.high = price
    cdl.low = price
    cdl.close = price
    cdl.volume = ifelse(_isvwap(w), NaN, 0.0)
end
_isvwap(w) = w[k"price_source"] == k"vwap"

function _maybe_resolve(w, df, sym, this_ts, tf)
    if isempty(df)
        state = get(w.attrs, k"symstates", nothing)
        if state !== nothing
            s = get(state, sym, nothing)
            if s !== nothing
                @lock s.lock @acquire w[k"sem"] _ensure_ohlcv!(w, sym)
            else
                @acquire w[k"sem"] _ensure_ohlcv!(w, sym)
            end
        else
            @acquire w[k"sem"] _ensure_ohlcv!(w, sym)
        end
        if isempty(df)
            return k"stale_df"
        end
    end
    if this_ts == _lastdate(df)
        k"stale_candle"
    elseif this_ts < _lastdate(df)
        # _ensure_ohlcv! fetched data past this_ts in a previous gap-fill call,
        # overshooting because its to=bound is _nextdate(tf) not this_ts.
        # The exchange data already covers this minute — the ticker-derived
        # candle is redundant/outdated.
        k"stale_candle"
    elseif !isrightadj(this_ts, _lastdate(df), tf)
        @debug "ohlcv tickers: resolving stale df" _module = LogOHLCVTickers sym _lastdate(
            df
        ) this_ts
        state2 = get(w.attrs, k"symstates", nothing)
        if state2 !== nothing
            s2 = get(state2, sym, nothing)
            if s2 !== nothing
                @lock s2.lock @acquire w[k"sem"] _ensure_ohlcv!(w, sym)
            else
                @acquire w[k"sem"] _ensure_ohlcv!(w, sym)
            end
        else
            @acquire w[k"sem"] _ensure_ohlcv!(w, sym)
        end
        # covers this candle — temp_candle is redundant/outdated.
        if _lastdate(df) >= this_ts
            return k"stale_candle"
        end
        # If the fetch updated df successfully, the temp candle should now be
        # right-adjacent and the caller handles it via the normal isnothing path.
        if isrightadj(this_ts, _lastdate(df), tf)
            return nothing
        end
        return k"stale_df"
    end
end
@doc """ Adjusts the volume of the temporary candlestick chart.

$(TYPEDSIGNATURES)

This function adjusts the volume of the temporary candlestick chart by dividing it by the number of ticks and the volume divisor.

"""
function _meanvolume!(w, state)
    cdl = state.temp
    cdl.volume = cdl.volume / cdl.ticks / w[k"volume_divisor"]
end
@doc """ Appends temp_candle ensuring contiguity.

$(TYPEDSIGNATURES)

This function appends the temporary candle to the DataFrame ensuring contiguity.
If the temporary candle is not right adjacent to the last date in the DataFrame, it resolves the gap and then appends the candle.

"""
function _ensure_contig!(w, df, temp_candle::TempCandle, tf, sym)
    # Guard: ensure all OHLC values are finite — the old resetcandle! used
    # typemin/typemax sentinel values that could leak when a candle was pushed
    # without a real ticker update (stale-check path). With the fix to use price
    # directly this shouldn't happen, but belted suspenders.
    if !isfinite(temp_candle.high)
        temp_candle.high = temp_candle.close
    end
    if !isfinite(temp_candle.low)
        temp_candle.low = temp_candle.close
    end
    if !isfinite(temp_candle.open)
        temp_candle.open = temp_candle.close
    end
    res = _maybe_resolve(w, df, sym, temp_candle.timestamp, tf)
    if isnothing(res)
        ## append complete candle (check again adjaciency)
        if isrightadj(temp_candle.timestamp, _lastdate(df), tf)
            # Exchange OHLCV volume fallback: if the exchange data already
            # has a candle at this timestamp with non-zero volume but the
            # ticker-computed volume is zero, preserve the exchange volume.
            # This handles the case where the exchange's 24h rolling baseVolume
            # doesn't change between boundary ticker snapshots (no diff for
            # diff_volume!), but the exchange's own OHLCV candle has accurate
            # per-minute volume from trade-level data.
            if iszero(temp_candle.volume) && !isempty(df)
                idx = dateindex(df, temp_candle.timestamp)
                if idx > 0 && idx <= nrow(df) && df[idx, :timestamp] == temp_candle.timestamp
                    exvol = df[idx, :volume]
                    if !iszero(exvol)
                        @debug "ohlcv tickers: using exchange volume" _module = LogOHLCVTickers sym temp_candle.timestamp volume = exvol
                        temp_candle.volume = exvol
                    end
                end
            end
            _maybe_push!(w, df, temp_candle, sym)
        end
    elseif res == k"stale_df" && (isempty(df) || _lastdate(df) < temp_candle.timestamp)
        # _maybe_resolve couldn't fetch current data from the exchange (network
        # issue, exchange API trouble, gap in the WS stream). _maybe_push! skips
        # the candle when it is a flat resetcandle! artifact (open==high==low==
        # close) carrying a stale price, keeping an honest gap. The first-seed
        # case (empty df) is always pushed.
        _maybe_push!(w, df, temp_candle, sym)
    end
end
@doc """ Appends a candle row, guaranteeing the view never contains two rows with the same timestamp.

$(TYPEDSIGNATURES)

`pushmax!` simply appends, so two callers racing on `df` (the ticker processing task and the
concurrent stale-check task) — or a gap-fill fetch followed by a ticker push — can otherwise
produce a duplicate timestamp. If a row for `row.timestamp` already exists, the push is skipped
(the existing row is authoritative: it came from an exchange fetch or an earlier, identical push).
"""
function _push_unique!(df, row, cap)
    ts = row.timestamp
    if !isempty(df) && lastdate(df) == ts
        # Latest candle being re-pushed (race / redundant push) — already present.
        return
    elseif !isempty(df)
        idx = dateindex(df, ts)
        if idx > 0 && idx <= nrow(df) && df[idx, :timestamp] == ts
            # Timestamp exists elsewhere in the view — skip to keep timestamps unique.
            return
        end
    end
    pushmax!(df, row, cap)
end
function _maybe_push!(w, df, temp_candle, sym)
    # Skip candles that had zero real ticker contributions (stale artifacts from
    # resetcandle! after a gap / WS drop). These have state.ticks == 0 because
    # _update_sym_ohlcv was never called with a valid price for this minute.
    # Check state.ticks rather than open==high==low==close because a market with
    # no price movement in a minute produces a legitimate one-ticker candle where
    # all four fields equal the same price — such candles SHOULD be pushed; they
    # represent real data and prevent unfillable gaps in the view.
    state = get(w[k"symstates"], sym, nothing)
    if state isa TickerWatcherSymbolState2 && state.ticks == 0
        @debug "ohlcv tickers watcher: skipping stale candle (state.ticks == 0)" _module = LogOHLCVTickers sym temp_candle.timestamp
        return
    end
    _push_unique!(df, fromstruct(temp_candle), w.capacity.view)
    invokelatest(w[k"callback"], df, sym)
end
function diff_volume!(w, df, state, latest_timestamp)
    temp_candle = state.temp
    sym = state.sym

    # curr_max = max baseVolume observed during the just-ended minute
    # (from all tickers within the minute, tracked by state.max_base).
    # prev_base = max baseVolume from the previous complete minute.
    curr_max = state.max_base
    prev_base = state.daily_volume

    # Update baseline for next diff and reset per-minute tracking.
    state.daily_volume = curr_max
    state.max_base = 0.0

    # Init guard — trigger baseline fetch when no prev_base exists.
    if iszero(prev_base) && !iszero(curr_max) && !state.loaded
        @warn "ohlcv tickers watcher: zero prev max base volume" latest_timestamp sym curr_max
        @lock state.lock @acquire w[k"sem"] _ensure_ohlcv!(w, sym)
        temp_candle.volume = 0.0
        return false
    end

    # First diff after watcher start (prev_base=0) — baseline unknown,
    # zero this candle's volume.
    if iszero(prev_base)
        temp_candle.volume = 0.0
        state.last_diff_ts = temp_candle.timestamp
        return true
    end

    # Gap detection: if the candle being pushed is more than one period
    # after the last diff, prev_base is stale. Zero this candle — the
    # next ticker's max_base tracking will rebuild a fresh baseline.
    tf = _tfr(w)
    prd = period(tf)
    if state.last_diff_ts != DateTime(0) && temp_candle.timestamp - state.last_diff_ts > prd
        state.last_diff_ts = temp_candle.timestamp
        temp_candle.volume = 0.0
        return true
    end
    state.last_diff_ts = temp_candle.timestamp

    # Volume = increase in max baseVolume + volume of candle dropping off the 24h
    # rolling window. The dropped-candle term compensates for the exchange's cached
    # 24h rolling baseVolume: when baseVolume doesn't change between minutes,
    # curr_max - prev_base == 0, but there WAS trading activity — its volume is
    # reflected in the candle that just exited the 24h window. Without this term,
    # candles with no baseVolume increase get volume = 0 even when OHLC values differ.
    volume = max(0.0, curr_max - prev_base)
    dropped_candle_date = latest_timestamp - Day(1) - tf
    didx = dateindex(df, dropped_candle_date)
    if didx > 0 && didx <= nrow(df) && df[didx, :timestamp] == dropped_candle_date
        dropped_vol = df[didx, :volume]
        if !iszero(dropped_vol)
            volume += dropped_vol
        end
    end

    temp_candle.volume = volume
    true
end
@doc """ Updates the OHLCV for a specific symbol.

$(TYPEDSIGNATURES)

This function updates the OHLCV for a specific symbol based on the latest timestamp and price from the ticker.
It resets the temporary candlestick chart if the timestamp is newer than the current one and ensures contiguity when appending the candle to the DataFrame.

"""
function _update_sym_ohlcv(w, ticker, latest_timestamp, sym=ticker.symbol)
    @debug "ohlcv tickers watcher: update temp candle" _module = LogOHLCVTickers sym latest_timestamp now()
    # Guard against tickers whose symbol is missing/null: a null `symbol` (or a
    # symbol not being tracked) must not throw inside the async processing task,
    # which would silently drop the candle for *every* symbol (the exception is
    # swallowed by errormonitor, so WS data is received but no candle is appended).
    state = get(w[k"symstates"], sym, nothing)
    isnothing(state) && return nothing
    price = getproperty(ticker, w[k"price_source"])
    # `last` (or the configured price source) can be `nothing`/`NaN` in a WS
    # `watchTickers` payload. Without this guard `resetcandle!` assigns `nothing`
    # to a `Float64` field and throws — silently, killing candle formation.
    (isnothing(price) || !isfinite(price)) && return nothing
    df = @lget! w.view sym cached_ohlcv!(w, :tickers; sym=sym)
    temp_candle = state.temp
    isdiff = w[k"diff_volume"]
    if temp_candle.timestamp == DateTime(0)
        resetcandle!(w, temp_candle, latest_timestamp, price)
    elseif temp_candle.timestamp < latest_timestamp
        if isdiff
            # Save current ticker's quoteVolume for diff_volume! fallback
            quote_vol = something(get(ticker, :quoteVolume, nothing), 0.0)
            state.prev_quote_volume, state.curr_quote_volume = state.curr_quote_volume, quote_vol
            # Initialize max_base for the just-ended minute with the trigger
            # ticker's baseVolume BEFORE diff_volume! reads it. Use `=` not
            # `max(...,)` — the boundary ticker is the FIRST ticker of the
            # new minute, so its volume is the correct starting point; any
            # stale value left over from a skipped (gap) diff_volume! must
            # NOT be carried forward (would inflate volume if baseVolume
            # dropped below the stale max during the gap).
            temp_candle.volume = something(ticker.baseVolume, 0.0)
            state.max_base = temp_candle.volume
            diff_volume!(w, df, state, latest_timestamp)
        elseif !_isvwap(w)
            _meanvolume!(w, state)
        end
        _ensure_contig!(w, df, temp_candle, _tfr(w), sym)
        resetcandle!(w, temp_candle, latest_timestamp, price)
        state.ticks = 0
    end
    ifproperty!(isless, temp_candle, :high, price)
    ifproperty!(>, temp_candle, :low, price)
    if isdiff
        vol = something(ticker.baseVolume, 0.0)
        temp_candle.volume = vol
        # Track max baseVolume from ALL tickers in this minute for the next
        # diff_volume! call. Mid-minute exchange updates to baseVolume are
        # captured here, preventing volume=0 when the boundary-trigger ticker
        # happens before the exchange pushes an update.
        state.max_base = max(state.max_base, vol)
    elseif !_isvwap(w)
        temp_candle.volume += something(ticker.baseVolume, 0.0)
    end
    # Note: state.max_base tracks the maximum baseVolume observed from any
    # ticker within the current minute (reset by diff_volume! at the start of
    # each new minute). state.daily_volume carries the previous minute's max
    # as the baseline for the next diff. This max-to-max computation captures
    # baseVolume increases from mid-minute exchange updates that the old
    # trigger-to-trigger diff approach lost.
    temp_candle.close = price
    state.ticks += 1
end

function _idx_to_process(w, date, prev_idx)
    idx = findprev(snap -> snap.time <= date, buffer(w), prev_idx)
    if isnothing(idx)
        if first((buffer(w))).time > date
            firstindex(buffer(w))
        end
    elseif buffer(w)[idx].time != date
        idx
    elseif idx < length(buffer(w))
        idx + 1
    end
end

function sym_procstate!(state::TickerWatcherSymbolState2, p=false, time=DateTime(0))
    state.isprocessed = p
    state.processed_time = time
end

@doc """ Processes the watcher data.

$(TYPEDSIGNATURES)

This function processes the watcher data by updating the OHLCV for each symbol in the last fetch.
It does this in a synchronous manner, ensuring that all updates are completed before proceeding.

"""
function _process!(w::Watcher, ::CcxtOHLCVTickerVal)
    @warmup! w
    last_p_date = _lastprocessed(w)
    if isempty(w)
        return nothing
    elseif @ispending(w)
        # Initialize state.daily_volume from the first ticker's baseVolume to provide
        # a baseline for diff_volume!. Without this, the first candle's volume diff
        # always zeroes out (prev_base == 0 → volume = 0) — only subsequent candles
        # with a non-zero prev_base produce meaningful volume.
        if w[k"diff_volume"] && !isempty(buffer(w))
            _, data = last(buffer(w))
            for (sym, ticker) in data
                state = get(w[k"symstates"], sym, nothing)
                if state isa TickerWatcherSymbolState2
                    state.daily_volume = something(ticker.baseVolume, 0.0)
                end
            end
        end
        return nothing
    end
    symstates = w[k"symstates"]
    map(sym_procstate!, values(symstates))
    last_idx = lastindex(buffer(w))
    idx = _idx_to_process(w, last_p_date, last_idx)
    latest_timestamp = DateTime(0)
    this_tf = _tfr(w)
    tasks = watcher_tasks(w)
    while !isnothing(idx)
        data_date, data = w.buffer[idx]
        for (sym, ticker) in data
            state = get(symstates, sym, nothing)
            if !isnothing(state)
                latest_timestamp = apply(this_tf, data_date)
                t = @async @lock state.lock _update_sym_ohlcv(w, ticker, latest_timestamp)
                push!(tasks, errormonitor(t))
                sym_procstate!(state, true, latest_timestamp)
            end
        end
        _lastprocessed!(w, data_date)
        idx = _idx_to_process(w, data_date, last_idx)
    end
end

@doc """ Checks for stale data in the watcher.

$(TYPEDSIGNATURES)

This function checks for stale data in the watcher by iterating over the symbol states and updating the OHLCV if necessary.
"""
function _checkforstale(w)
    symstates = w.symstates
    this_tf = _tfr(w)
    # Buffer entries are NamedTuples `(; time, value)` (see defaults.jl).
    # `last(buffer(w)).time` is the DateTime of the newest entry; apply()
    # floors it to the watcher timeframe. The previous code did
    # `@lget!(last(buffer(w)), 1, ...).time` — but `@lget!` with index 1
    # already returns the *DateTime* (field 1), so `.time` was applied to a
    # DateTime and threw FieldError, killing this stale-check task silently
    # (it runs inside the errormonitor'd fetch loop). Stale/gapped data
    # was then never recovered. Guard the empty buffer with now().
    latest_timestamp = apply(
        this_tf, isempty(buffer(w)) ? now() : last(buffer(w)).time
    )
    tasks = watcher_tasks(w)
    for state in values(symstates)
        if !state.isprocessed && apply(this_tf, state.processed_time) < latest_timestamp
            t = @async @lock state.lock _update_sym_ohlcv(
                w, nothing, latest_timestamp, state.sym
            )
            push!(tasks, errormonitor(t))
            sym_procstate!(state, true, latest_timestamp)
        end
    end
end

function _start!(w::Watcher, ::CcxtOHLCVTickerVal)
    # NOTE: order is important
    empty!(buffer(w))
    _pending!(w)
    _chill!(w)
    a = attrs(w)
    a[k"sem"] = Base.Semaphore(a[k"n_jobs"])
    a[k"symstates"] = Dict(sym => TickerWatcherSymbolState2(; sym) for sym in _ids(w))
    # Ensure the exchange has markets loaded before pre-loading history.
    # The Exchange(sym) constructor doesn't load markets — they're populated
    # by getexchange! → setexchange! → loadmarkets!. Without this, _ensure_ohlcv!
    # → _fetch_loop would fail with "Pair not in exchange markets".
    eid = exchangeid(_exc(w))
    exc = getexchange!(
        eid, a[k"excparams"]; sandbox=a[k"issandbox"], account=a[k"excaccount"]
    )
    _exc!(a, exc)
    # Pre-load historical OHLCV data for each symbol, matching the behavior of
    # ccxt_ohlcv_trades (which calls _fetchto! directly in _start!) and
    # ccxt_ohlcv_candles (which does the same via handler_task init_func).
    for sym in _ids(w)
        errormonitor(@async begin
            # Hold state.lock so the history preload cannot race the live ticker
            # path (_checkforstale → _update_sym_ohlcv, which also holds state.lock)
            # on the same w.view[sym] df. Both push via non-deduping _fetchto! /
            # _push_unique!, so a concurrent run would duplicate a timestamp.
            state = w.symstates[sym]
            try
                @lock state.lock @acquire a[k"sem"] _ensure_ohlcv!(w, sym)
            catch e
                @error "ohlcv tickers history preload failed for $sym" exception = (e, catch_backtrace())
            end
        end)
    end
    _reset_tickers_func!(w)
end

_stop!(w::Watcher, ::CcxtOHLCVTickerVal) = _stop!(w, CcxtTickerVal())

function _ensure_ohlcv!(w, sym)
    @debug "ohlcv tickers watcher: ensure" _module = LogOHLCVTickers sym
    tf = _tfr(w)
    min_rows = w.capacity.view - w.capacity.buffer
    df = @lget! w.view sym begin
        cached_ohlcv!(w, :candles; sym)
    end
    try
        if isempty(df)
            local this, from, to
            this = now()
            from = this - (w.capacity.view + 1) * tf
            to = _nextdate(tf)
            _fetchto!(w, df, sym, tf, Val(:append); from, to, allow_upsample=true)
        else
            (from, to) = (lastdate(df), _nextdate(tf))
            if length(from:(period(tf)):to) > min_rows
                from = to - period(tf) * w.capacity.view
            end
            _fetchto!(w, df, sym, tf, Val(:append); from, to, allow_upsample=false)
            # Skipping fill_missing_candles! — it creates synthetic rows with
            # volume=0 and stale OHLCV that are indistinguishable from real data.
            _ensure_ohlcv_check_contig!(w, df, sym)
            if nrow(df) < min_rows
                to = _firstdate(df) + period(tf)
                _fetchto!(w, df, sym, tf, Val(:prepend); to, allow_upsample=true)
                _ensure_ohlcv_check_contig!(w, df, sym)
            end
        end
    catch e
        @warn "_ensure_ohlcv! fetch failed for $sym" exception=(e, catch_backtrace())
    end
    # Dedup is placed OUTSIDE try/catch so it runs even when a fetch error (e.g.
    # _fetch_error in _fetchto!) partially completes and leaves the view with
    # duplicate timestamps. df.timestamp is ascending, so duplicates are adjacent.
    _dedup_view!(df)
    if nrow(df) < min_rows && !w[k"minrows_warned"]
        @warn "ohlcv tickers watcher: can't fill view with enough data" sym nrow(df) min_rows
        w[k"minrows_warned"] = true
    end
    cb = get(w.attrs, k"callback", nothing)
    if applicable(cb, df, sym)
        invokelatest(cb, df, sym)
    end
    # Mark the symbol as loaded so diff_volume! (and other callers) know the
    # initial fetch was attempted — avoids repeated _ensure_ohlcv! calls that
    # would each fail with the same overlap/contiguity error.
    state = get(w[k"symstates"], sym, nothing)
    if state isa TickerWatcherSymbolState2
        state.loaded = true
    end
end

function _ensure_ohlcv_check_contig!(w, df, sym)
    # _fetchto! already performs a non-fatal contiguity check and logs any gap in
    # the fetched exchange history. Re-raising here would abort the whole history
    # preload on a *legitimate* exchange gap (e.g. a minute with no trades has no
    # candle), leaving the view short and spamming "fetch failed" errors. Tolerate
    # it — an honest gap is preferable to dropping the entire history load.
    try
        _do_check_contig(w, df, _checks(w))
    catch e
        @debug "ohlcv tickers watcher: preloaded history not contiguous (gap tolerated)" _module = LogOHLCVTickers sym exception = (e, catch_backtrace())
    end
end
function _dedup_view!(df)
    # Guarantee the view's unique-timestamp invariant (Lesson 17): if a race
    # between the history preload (_fetchto! → appendmax!/prependmax!, no dedup)
    # and the live ticker path produced two rows with the same timestamp, drop the
    # duplicate. df.timestamp is ascending, so duplicates are strictly adjacent.
    n = nrow(df)
    n <= 1 && return
    dup = falses(n)
    ts = df[:, :timestamp]
    for i in 2:n
        ts[i] == ts[i - 1] && (dup[i] = true)
    end
    any(dup) && deleteat!(df, findall(dup))
end
function _load_ohlcv!(w, sym)
    state = attr(w, k"symstates", nothing)
    if isnothing(state)
        @error "ohlcv tickers watcher: load filed, not tracking" sym
    end
    if !state.loaded
        @lock state.lock @acquire w[k"sem"] _ensure_ohlcv!(w, sym)
        state.loaded = true
    end
end

@doc """ Loads the OHLCV data for a specific symbol.

$(TYPEDSIGNATURES)

This function loads the OHLCV data for a specific symbol.
If the symbol is not being tracked by the watcher or if the data for the symbol has already been loaded, the function returns nothing.

"""
_load!(w::Watcher, ::CcxtOHLCVTickerVal, sym) = _load_ohlcv!(w, sym)

function _load_all_ohlcv!(w)
    if (isempty(w.buffer) || isempty(w.view))
        return nothing
    end
    syms = isempty(w.buffer) ? keys(w.view) : keys(last(w.buffer).value)
    @sync for sym in syms
        @async @acquire w[k"sem"] @logerror w _load!(w, _val(w), sym)
    end
end

@doc """ Loads the OHLCV data for all symbols.

$(TYPEDSIGNATURES)

This function loads the OHLCV data for all symbols.
If the buffer or view of the watcher is empty, the function returns nothing.

"""
_loadall!(w::Watcher, ::CcxtOHLCVTickerVal) = _load_all_ohlcv!(w)

function _update_sym_ohlcv(w, ::Nothing, latest_timestamp, sym)
    @debug "ohlcv tickers watcher: no update trail check" _module = LogOHLCVTickers sym
    df = get(w.view, sym, nothing)
    if isnothing(df)
        return nothing
    end
    state = get(w[k"symstates"], sym, nothing)
    if isnothing(state)
        return nothing
    end
    temp_candle = state.temp
    price = if isfinite(temp_candle.close) && !iszero(temp_candle.close)
        temp_candle.close
    elseif !isempty(df)
        p = last(df.close)
        resetcandle!(w, temp_candle, _lastdate(df), p)
        p
    else
        return nothing
    end
    # if new candle timestamp, push the previous finished candle
    if temp_candle.timestamp < latest_timestamp
        if state.ticks > 0
            if w[k"diff_volume"]
                diff_volume!(w, df, state, latest_timestamp)
            elseif !_isvwap(w)
                # NOTE: this is where a stall can happen since can potentially call
                # process adjusted volume
                _meanvolume!(w, state)
            end
            # Set high/low from the available price (resetcandle! uses price directly,
            # so sentinel -Inf/Inf values no longer appear; this is belt-and-suspenders
            # for any path that pushes the candle without a real ticker update)
            ifproperty!(isless, temp_candle, :high, price)
            ifproperty!(>, temp_candle, :low, price)
            _ensure_contig!(w, df, temp_candle, _tfr(w), sym)
        end
        # Always advance the candle to latest_timestamp, even when no real ticker data
        # arrived (state.ticks == 0). The candle has no meaningful OHLCV — it was
        # seeded by resetcandle! with stale price data — so we skip _ensure_contig!
        # to avoid pushing a misleading flat candle. The next real ticker's _ensure_contig!
        # will call _maybe_resolve → _ensure_ohlcv! → _fetchto! to fill the gap properly.
        resetcandle!(w, temp_candle, latest_timestamp, price)
        state.ticks = 0
    end
end
