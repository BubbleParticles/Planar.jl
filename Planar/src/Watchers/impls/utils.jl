using Rocket
using PlanarCore.Data: df!, _contiguous_ts, nrow, save_ohlcv, zi, check_all_flag, snakecased, empty_ohlcv
using PlanarCore.Data.DFUtils: firstdate, lastdate, copysubs!, addcols!
using PlanarCore.Data.DataFramesMeta

using PlanarCore.Fetch
using PlanarCore.Fetch.Exchanges: Exchange, account, getexchange!, FeesType, DFT, TradeSide, TradeRole
using PlanarCore.TimeTicks: dt
using PlanarCore.Fetch.Exchanges.Ccxt: _multifunc
using PlanarCore.Fetch: fetch_candles
using PlanarCore.Lang
using PlanarCore.Misc: rangeafter, rangebetween, rangebefore
using PlanarCore.Fetch.Processing: cleanup_ohlcv_data, fill_missing_candles!, iscomplete, isincomplete, upsample
using ..Watchers: logerror
using ..Watchers: JSON3

"""Start the gateway exchange subprocess if not already started, and wait for it to be ready."""
function _start_gateway_exchange(eid::String)
    client = Fetch.Exchanges.Ccxt.CcxtGateway.default_client()
    try
        Fetch.Exchanges.Ccxt.CcxtGateway.Rest.start_exchange(client, eid)
    catch e
        @debug "start_exchange for $eid" exception=(e, catch_backtrace())
    end
    # Wait for exchange to be ready (has dict populated)
    for _ in 1:30
        try
            Fetch.Exchanges.Ccxt.CcxtGateway.Rest.exchange_ready(client, eid) && return
        catch
        end
        sleep(0.5)
    end
    @warn "Exchange $eid may not be fully ready; has dict could be incomplete"
end

# JSON3-aware converters for fromdict (gateway data)
_wconvert(::Type{DateTime}, v) = v isa AbstractString ? _parsedatez(v) : dt(Int(v))
_wconvert(::Type{TradeSide}, v) = TradeSide(v)
_wconvert(::Type{TradeRole}, v) = TradeRole(v)
_wconvert(::Type{Vector{T}}, v) where {T} = [_wconvert(T, x) for x in v]
function _wconvert(::Type{Union{Nothing, T}}, v) where {T}
    isnothing(v) && return nothing
    _wconvert(T, v)
end
_wconvert(::Type{Vector{T}}, v::Nothing) where {T} = T[]
_wconvert(::Type{Union{Nothing, <:AbstractVector{T}}}, v) where {T} =
    isnothing(v) ? T[] : _wconvert(Vector{T}, v)
    _wconvert(::Type{T}, v) where {T<:DFT} = Float64(v)
    _wconvert(::Type{T}, ::Nothing) where {T<:DFT} = nothing
_wconvert(::Type{String}, v) = string(v)
_wconvert(::Type{Symbol}, v) = Symbol(v)
function _wconvert(::Type{Union{Nothing, DFT}}, v)
    isnothing(v) && return nothing
    Float64(v)
end
function _wconvert(::Type{Union{Nothing, String}}, v)
    isnothing(v) && return nothing
    string(v)
end
function _wconvert(::Type{Union{Nothing, TradeRole}}, v)
    isnothing(v) && return nothing
    TradeRole(v)
end
_wconvert(::Type{<:FeesType}, v) = _convert_fees(v)
function _convert_fees(v)
    if v isa Union{Dict, JSON3.Object}
        cost = get(v, "cost", nothing)
        currency = get(v, "currency", nothing)
        # `something(cost, nothing)` crashes with ArgumentError when both
        # arguments are nothing/missing. Use a tiny helper to normalize.
        _nf(x) = x === nothing || x === missing ? nothing : x
        (; cost=_nf(cost), currency=_nf(currency))
    elseif isnothing(v)
        nothing
    elseif v isa Number
        Float64(v)
    else
        error("watchers: invalid fees type $v")
    end
end

_wkey(::Type{String}, k) = string(k)

# Stream handler stubs for non-Python mode
struct StreamHandler
    stop::Function
    push::Function
end
StreamHandler(; stop=Base.Returns(nothing), push=Base.Returns(nothing)) = StreamHandler(stop, push)

function stream_handler(coro_func, f_push)
    # Websocket/Python ccxt stream handler. In the non-Python gateway mode,
    # there is no real streaming coroutine to manage, so both stop and push
    # are no-ops. Use `_push` so the closure is invoked in case downstream
    # code relies on f_push being a real side-effecting function (it does not
    # run where Rocket subjects are the actual delivery mechanism).
    StreamHandler(Base.Returns(nothing), f_push)
end
start_handler!(h) = nothing
stop_handler!(h) = nothing

@add_statickeys! begin
    exc
    status
    ohlcv_method
end

@doc """
Removes trailing 'Z' from a string and parses it into a DateTime object.

"""
_parsedatez(s::AbstractString) = begin
    s = rstrip(s, 'Z')
    Base.parse(DateTime, s)
end

@doc """
Converts market data into a NamedTuple.

$(TYPEDSIGNATURES)

This macro takes a tick type, a collection of market data, and an optional key (defaulting to "symbol"). It then converts each market data item into the specified tick type and constructs a NamedTuple where each entry corresponds to a market, with the key being the market's symbol and the value being the converted data.
"""
macro parsedata(tick_type, mkts, key="symbol")
    key = esc(key)
    mkts = esc(mkts)
    quote
        NamedTuple(
            convert(Symbol, m[$key]) => fromdict($tick_type, String, m, _wkey, _wconvert) for m in $mkts
        )
    end
end

@doc """ Collects data from a buffer and stores it in a dictionary

$(TYPEDSIGNATURES)

The `collect_buffer_data` macro takes a buffer variable, key type, value type, and an optional push function.
It escapses the provided parameters and initializes a dictionary with the key type and vector of the value type.
The push function is used to populate the dictionary with data from the buffer.
If no push function is provided, a default one is used which pushes the ticker data into the dictionary.
The dictionary is then returned after collecting all data from the buffer.

"""
macro collect_buffer_data(buf_var, key_type, val_type, push=nothing)
    key_type = esc(key_type)
    val_type = esc(val_type)
    buf = esc(buf_var)
    push_func = isnothing(push) ? :(push!(@kget!(data, key, $(val_type)[]), tick)) : push
    quote
        let data = Dict{$key_type,Vector{$val_type}}(), dopush((key, tick)) = $push_func
            docollect(entry) = begin
                # entry is BufferEntry NamedTuple(:time,:value); skip null/invalid timestamps (lesson #35)
                t = entry.time
                if !isnothing(t) && t != DateTime(0)
                    foreach(dopush, pairs(entry.value))
                end
            end
            foreach(docollect, $buf)
            data
        end
    end
end

@doc """ Defines a closure that appends new data on each symbol dataframe

$(TYPEDSIGNATURES)

The `append_dict_data` macro takes a dictionary, data, and a maximum length variable.
It defines a closure `doappend` that appends new data to each symbol dataframe in the dictionary.
The macro ensures that the length of the dataframe does not exceed the provided maximum length.

"""
macro append_dict_data(dict, data, maxlen_var)
    maxlen = esc(maxlen_var)
    df = esc(:df)
    quote
        function doappend((key, newdata))
            $(df) = @kget! $(esc(dict)) key DataFrame()
            appendmax!($df, newdata, $maxlen)
        end
        foreach(doappend, $(esc(data)))
    end
end

# FIXME
Base.convert(::Type{Symbol}, s::JSON3.String) = Symbol(s)
Base.convert(::Type{DateTime}, s::JSON3.String) = _parsedatez(s)
Base.convert(::Type{DateTime}, s::JSON3.Number) = unix2datetime(s)
Base.convert(::Type{String}, s::Symbol) = string(s)
Base.convert(::Type{Symbol}, s::AbstractString) = Symbol(s)
_checks(w) = get(attrs(w), :checks, nothing)
_checksoff!(w) = setattr!(w, Val(:off), :checks)
_checkson!(w) = setattr!(w, Val(:on), :checks)
function _do_check_contig(w, df, ::Val{:on})
    isempty(df) || _contiguous_ts(df.timestamp, timefloat(_tfr(w)))
end
_do_check_contig(_, _, ::Val{:off}) = nothing
_do_check_contig(_, _, ::Nothing) = nothing
function _do_check_contig(w, df::AbstractDict, ::Val{:on})
    for v in values(df)
        _do_check_contig(w, v, Val(:on))
    end
end
_check_contig(w, df) = !isempty(df) && _do_check_contig(w, df, _checks(w))

_exc(attrs) = attrs[:exc]
_exc(w::Watcher) = _exc(attrs(w))
_exc!(attrs, exc) = attrs[:exc] = exc
_exc!(w::Watcher, exc) = _exc!(attrs(w), exc)
# --- Shared WebSocket subscription helpers ---

"""
    _connect_ws_subscribe!(w, eid, method, params) -> Bool

Connect to the gateway WebSocket and subscribe to `method` with `params`.
"""
function _connect_ws_subscribe!(w::Watcher, eid::String, method::String, params::Dict{String,Any})::Bool
    attrs = w.attrs
    handler = get(attrs, :handler, nothing)
    handler === nothing && return false

    subject = handler.subject
    _WS = Fetch.Exchanges.Ccxt.CcxtGateway

    ws_client = _WS.default_ws_client()

    # Clean up old subscription callback before reconnecting to prevent
    # client.subscriptions from accumulating stale callbacks on each reconnect.
    old_sub_id = get(attrs, :ws_sub_id, nothing)
    if old_sub_id !== nothing
        _WS.send_unsubscribe(ws_client, old_sub_id)
    end

    connected = _WS.connect!(ws_client)
    if !connected
        return false
    end

    sub_id = try
        _WS.send_subscribe(
            ws_client, eid, method,
            params=params,
            callback = data -> begin
                @debug "WS callback received" data_type=typeof(data) data_summary=summary(data)
                if data !== nothing
                    Rocket.next!(subject, data)
                end
            end,
        )
    catch e
        @error "WebSocket subscribe failed" exception = (e, catch_backtrace())
        return false
    end

    attrs[:ws_client] = ws_client
    attrs[:ws_sub_id] = sub_id
    return true
end

"""
    _setup_ws_watcher!(w, eid, method, params, rest_fallback) -> Bool

Combined helper: tries initial WS connection+subscribe, then sets up the watcher's
`_tfunc` with automatic reconnection on WS disconnect. Returns `true` if WS was
established, `false` if the caller should fall back to REST polling.
"""
function _setup_ws_watcher!(w::Watcher, eid::String, method::String, params::Dict{String,Any}, rest_fallback::Function)::Bool
    attrs = w.attrs
    _WS = Fetch.Exchanges.Ccxt.CcxtGateway

    # Initial connection
    if !_connect_ws_subscribe!(w, eid, method, params)
        return false
    end

    # Reconnect-aware tfunc: always run REST polling as a heartbeat/fallback so the
    # periodic fetch pipeline is never a no-op. WS delivers real-time updates via the
    # handler subject; REST keeps the view fresh and recovers automatically if WS
    # stalls or drops. (Previously this only called check_task! while connected,
    # leaving the view stale whenever WS was up but not streaming.)
    _tfunc!(attrs, function ()
        ws_client = get(attrs, :ws_client, nothing)
        if ws_client !== nothing && _WS.is_connected(ws_client)
            rest_fallback()
        else
            @warn "WebSocket disconnected for $(w.name), attempting reconnect..."
            if _connect_ws_subscribe!(w, eid, method, params)
                @info "WebSocket reconnected for $(w.name)"
                rest_fallback()
            else
                @debug "WebSocket reconnect failed for $(w.name), using REST fallback"
                rest_fallback()
            end
        end
    end)

    return true
end

# --- End shared WebSocket helpers ---

_tfunc!(attrs, suffix) = attrs[:tfunc] = _multifunc(string(_exc(attrs).id), suffix, true)[1]
_tfunc!(attrs, f::Function) = attrs[:tfunc] = f
_tfunc(w::Watcher) = get(attrs(w), :tfunc, nothing)
_sym(w::Watcher) = get(attrs(w), :sym, nothing)
_sym!(attrs, v) = attrs[:sym] = v
_sym!(w::Watcher, v) = _sym!(attrs(w), v)
_tfr(attrs) = get(attrs, :timeframe, nothing)
_tfr(w::Watcher) = _tfr(attrs(w))
_tfr!(attrs, tf) = attrs[:timeframe] = tf
_tfr!(w::Watcher, tf) = setattr!(w, tf, :timeframe)
_firstdate(df::DataFrame, range::UnitRange) = df[range.start, :timestamp]
_firstdate(df::DataFrame) = df[begin, :timestamp]
_firsttrade(w::Watcher) = first(_trades(w))
_lasttrade(w::Watcher) = last(_trades(w))
_lastdate(df::DataFrame) = df[end, :timestamp]
_nextdate(df::DataFrame, tf) = df[end, :timestamp] + period(tf)
_lastdate(z::ZArray) = z[end, 1] # the first col is a to
_curdate(tf) = isnothing(tf) ? now() : apply(tf, now())
_nextdate(tf) = isnothing(tf) ? now() : _curdate(tf) + tf
_dateidx(tf, from, to) = isnothing(tf) ? 1 : max(1, (to - from) ÷ period(tf))
_lastflushed!(w::Watcher, v) = setattr!(w, v, :last_flushed)
_lastflushed(w::Watcher) = get(attrs(w), :last_flushed, nothing)
_lastprocessed!(w::Watcher, v) = setattr!(w, v, :last_processed)
_lastprocessed(w::Watcher) = get(attrs(w), :last_processed, nothing)
_lastcount!(w::Watcher, v, f=length) = setattr!(w, f(v), :last_count)
_lastcount(w::Watcher) = get(attrs(w), :last_count, nothing)

struct Warmed end
struct Pending end
_ispending(::Warmed) = false
_ispending(::Pending) = true
_iswarm(::Warmed) = true
_iswarm(::Pending) = false
macro iswarm(w)
    w = esc(w)
    :(_iswarm(_status($w)))
end
macro ispending(w)
    w = esc(w)
    :(_ispending(_status($w)))
end
_warmed!(_, ::Warmed) = nothing
_warmed!(w, ::Pending) = setattr!(w, Warmed(), :status)
_pending!(attrs) = attrs[:status] = Pending()
_pending!(w::Watcher) = _pending!(attrs(w))
_status(w::Watcher) = get(attrs(w), :status, Pending())
@doc "`_chill!` sets the warmup target attribute of the window to the current time applied with the time frame rate."
_chill!(w) = let tf=_tfr(w); isnothing(tf) ? nothing : setattr!(w, apply(tf, now()), :warmup_target) end
_warmup!(_, ::Warmed) = nothing
@doc "Checks if we can start processing data, after we are past the initial incomplete timeframe."
function _warmup!(w, ::Pending)
    tf=_tfr(w)
    isnothing(tf) && return nothing
    ats = apply(tf, now())
    target = get(w.attrs, :warmup_target, nothing)
    isnothing(target) && return nothing
    if ats > target
        @debug "watchers: warmed!" w
        _warmed!(w, _status(w))
    end
end
macro warmup!(w)
    w = esc(w)
    :(_warmup!($w, _status($w)))
end

_key!(w::Watcher, v) = setattr!(w, v, :key)
_key(w::Watcher) = get(attrs(w), :key, nothing)
_view!(w, v) = setattr!(w, v, :view)
_view(w) = get(attrs(w), :view, nothing)

function _dopush!(w, v; if_func=!isnothing)
    try
        if if_func(v)
            pushnew!(w, v, now())
            _lastpushed!(w, now())
            return true
        end
    catch
        @debug_backtrace
    end
    return nothing
end

iswatchfunc(func::Function) = startswith(string(nameof(func)), "watch")
iswatchfunc(func) = false

@doc """ Returns the available data within the given window

$(TYPEDSIGNATURES)

The `_get_available` function checks if data is available within a given window.
It calculates the maximum lookback period and checks if the data in the window is empty.
If it is, the function returns nothing.
If data is available, it creates a view of the data and checks if the data is too old.
If it is, it returns nothing and schedules a background task to update the data.
Otherwise, it converts the available data to OHLCV format and returns it.

"""
function _get_available(w, z, to)
    max_lookback = to - _tfr(w) * w.capacity.view
    isempty(z) && return nothing
    maxlen = min(w.capacity.view, size(z, 1))
    available = @view(z[(end - maxlen + 1):end, :])
    return if dt(available[end, 1]) < max_lookback
        # data is too old, fetch just the latest candles,
        # and schedule a background task to fast forward saved data
        nothing
    else
        Data.to_ohlcv(available[:, :])
    end
end

@doc """ Deletes OHLCV data of a given symbol from the window

$(TYPEDSIGNATURES)

The `_delete_ohlcv!` function removes OHLCV data of a specified symbol from the window.
If no symbol is provided, it defaults to the symbol of the window.
It fetches the data associated with the symbol and the current time frame rate, and deletes it.

"""
function _delete_ohlcv!(w, sym=_sym(w))
    z = load(zi, _exc(w).name, snakecased(sym), string(_tfr(w)); raw=true)[1]
    delete!(z)
end

@doc """ Fast forwards the window to the current timestamp

$(TYPEDSIGNATURES)

The `_fastforward` function ensures the window is up-to-date by fast-forwarding to the current timestamp.
It checks whether the stored data is empty or corrupted and retrieves available data within the window.
If no data is available, it calculates the starting point for fetching new data.
Otherwise, it appends the available data to the dataframe, checks the continuity of the data, and updates the starting point.
If the starting point is not equal to the current timestamp, it fetches new data up to the current timestamp and checks the data continuity again.

"""
function _fastforward(w, sym=_sym(w))
    tf = _tfr(w)
    df = w.view
    z = load(zi, _exc(w).name, sym, string(tf); raw=true)[1]
    @ifdebug @assert isempty(z) || _lastdate(z) != 0 "Corrupted storage because last date is 0: $(_lastdate(z))"

    cur_timestamp = _curdate(tf)
    avl = _get_available(w, z, cur_timestamp)
    from = if isnothing(avl)
        (cur_timestamp - period(tf) * w.capacity.view) - period(tf)
    else
        appendmax!(df, avl, w.capacity.view)
        _check_contig(w, df)
        _lastdate(df)
    end
    if from != cur_timestamp
        @debug "watchers fast forward: fetching " sym tf from to = cur_timestamp
        _sticky_fetchto!(w, w.view, sym, tf; to=cur_timestamp, from)
        _check_contig(w, df)
    end
end

function _fetch_candles(w, from, to="", sym=_sym(w); tf=_tfr(w))
    diff_str = if to isa DateTime && from isa DateTime
        "$(to - from) vs prd=$(period(tf)) (diff>prd=$(to - from > period(tf)))"
    else
        "non-DateTime args"
    end
    @debug "_fetch_candles called" sym tf from to diff=diff_str maxlog=10
    fetch_candles(_exc(w), tf, sym; from, to)
end

@doc """ Generates an error message when data fetching fails

$(TYPEDSIGNATURES)

The `_fetch_error` function is used when data fetching for a given symbol fails.
It generates an error message detailing the symbol, exchange name, and the time frame for which data fetching failed, unless the `quiet` attribute of the window is set to `true`.

"""
function _fetch_error(w, from, to, sym=_sym(w), args...)
    get(w.attrs, :quiet, false) || error(
        "Trades/ohlcv fetching failed for $sym @ $(_exc(w).name) from: $from to: $to ($(args...))",
    )
end

_op(::Val{:append}, args...; kwargs...) = appendmax!(args...; kwargs...)
_op(::Val{:prepend}, args...; kwargs...) = prependmax!(args...; kwargs...)
@doc "`_fromto` calculates a starting timestamp given a target timestamp, period, capacity and data kept."
_fromto(to, prd, cap, kept) = to - prd * (cap - kept) - 2prd
@doc """ Calculates the starting date for appending data to a dataframe

$(TYPEDSIGNATURES)

The `_from` function determines the starting date for appending data to a dataframe.
It takes into account a target date, time frame rate, capacity, and the `:append` flag.
The function ensures that the target date is not earlier than the last date in the dataframe.
It then calculates the earliest date that can be included in the dataframe based on the capacity and the time frame rate.
If the dataframe is empty, this earliest date is returned.
Otherwise, the minimum between this date and the last date in the dataframe is returned.

"""
function _from(df, to, tf, cap, ::Val{:append})
    @ifdebug @assert to >= _lastdate(df)
    date_cap = (to - tf * cap) - tf # add one more period to ensure from inclusion
    (isempty(df) ? date_cap : min(date_cap, _lastdate(df)))
end
_from(df, to, tf, cap, ::Val{:prepend}) = _fromto(to, period(tf), cap, nrow(df))
@doc """ Empties a dataframe

$(TYPEDSIGNATURES)

The `_empty!!` function tries to empty a dataframe.
If calling the `empty!` function on the dataframe throws an error, it uses the `copysubs!` function with the `empty` argument to empty the dataframe.

"""
_empty!!(df::DataFrame) =
    try
        empty!(df)
    catch
        copysubs!(df, empty, empty!)
    end

@doc """ Fetches and appends or prepends data to a dataframe

$(TYPEDSIGNATURES)

This function fetches data for a given symbol and time frame, and appends or prepends it to a provided dataframe.
The operation (append or prepend) is determined by the `op` parameter.
If the dataframe is not empty, it checks for data continuity.
If the data is not contiguous and the `resync_noncontig` attribute of the watcher is set to `true`, it empties the dataframe and resets the rows count.
The function calculates the starting date for fetching new data based on the dataframe, target date, time frame, and operation.
It then fetches the data, cleans it, and checks if it can be appended or prepended to the dataframe.
If the operation is possible, it performs it and returns `true`.
If the fetched data is empty, it returns `false`.
If the difference between the target date and the starting date is less than or equal to the period of the time frame, it also returns `true`.

"""
function _fetchto!(w, df, sym, tf, op=Val(:append); to, from=nothing, allow_upsample::Bool=true)
    rows = nrow(df)
    prd = period(tf)
    rows > 0 && try
        _check_contig(w, df)
    catch e
        logerror(w, e, catch_backtrace())
        if attr(w, :resync_noncontig, false)
            try
                empty!(df)
            catch
                copysubs!(df, empty, empty!)
            end
            rows = 0
        end
    end
    from = @something from _from(df, to, tf, w.capacity.view, op)
    diff = (to - from)
    @debug "fetchto! decision" diff prd from to diff_gt_prd=diff > prd diff_eq_prd=diff == prd to_lt_curdate=to < _curdate(tf) maxlog=10
    if diff > prd || (diff == prd && to < _curdate(tf))
        # GUARD: if diff is somehow still < prd (defense in depth), bail out
        if diff < prd
            @debug "fetchto!: GUARD CAUGHT sub-period fetch (diff=$diff < prd=$prd, from=$from, to=$to, tf=$tf)" maxlog=10
            return true
        end
        load_tf = attr(w, k"load_timeframe", tf)
        use_upsample = allow_upsample && (load_tf != tf) && (timefloat(load_tf.period) % timefloat(tf.period) == 0)
        candles = if use_upsample
            raw_candles = _fetch_candles(w, from, to, sym; tf=load_tf)
            # Last-mile strategy: only upsample COMPLETE load_tf periods.
            # The current incomplete period (e.g. current hour for 1h) is
            # fetched directly at native tf — no fake data from upsampling
            # a partial candle.
            _last_mile_boundary = apply(load_tf, now())
            _complete = isempty(raw_candles) ? empty_ohlcv() :
                let cr = rangebefore(raw_candles.timestamp, _last_mile_boundary)
                    isempty(cr) ? empty_ohlcv() :
                        upsample(view(raw_candles, cr, :), load_tf, tf)
                end
            result = if _last_mile_boundary < to
                _lm = _fetch_candles(w, max(from, _last_mile_boundary), to, sym; tf=tf)
                isempty(_lm) ? _complete : vcat(_complete, _lm)
            else
                _complete
            end
            result
        else
            _fetch_candles(w, from, to, sym; tf=nrow(df) < 2 ? tf : timeframe!(df))
        end
        from_to_range = rangebetween(candles.timestamp, from, to; strict=false)
        if isempty(from_to_range)
            if isempty(candles)
                @debug "watchers fetchto!: no data returned for range" tf from to maxlog=10
                return true
            end
            @debug "watchers fetchto!: all fetched data outside range, already caught up" tf from to nrows=nrow(candles)
            return true
        end
        @debug "watchers fetchto!: " to _lastdate(candles) from _firstdate(candles) length(
            from_to_range
        ) nrow(candles)
        sliced = if length(from_to_range) == nrow(candles)
            candles
        else
            view(candles, from_to_range, :)
        end
        cleaned = cleanup_ohlcv_data(sliced, tf; fill_missing=false)
        @debug "watchers fetchto!: " last_date =
            isempty(sliced) ? nothing : lastdate(sliced)

        # # Cleaning can add missing rows, and expand the range outside our target dates
        cleaned = DataFrame(
            @view(cleaned[rangebetween(cleaned.timestamp, from, to; strict=false), :]); copycols=false
        )
        if isempty(cleaned)
            if diff < prd
                @debug "watchers fetchto!: empty result due to sub-period range, treating as success" tf from to diff prd
                return true
            end
            return false
        end
        @debug "watchers fetchto!: " firstdate(cleaned) lastdate(cleaned)
        if op == Val(:append) && !isempty(df) && firstdate(cleaned) < lastdate(df)
            _fetch_error(w, from, to, sym, firstdate(cleaned))
        end
        isleftadj() = isempty(df) ? false : lastdate(cleaned) + prd == firstdate(df)
        isrightadj() = isempty(df) ? false : firstdate(cleaned) - prd == lastdate(df)
        isrecent() = isempty(df) ? false : lastdate(cleaned) > lastdate(df)
        isprep() = if op == Val(:prepend)
            if isleftadj()
                true
            elseif !isempty(df) && lastdate(cleaned) >= firstdate(df)
                # Prepended data covers/overlaps existing data (e.g., cached
                # 1-row from startup_task with the same timestamp).
                # Clear existing data — the cleaned data contains everything.
                _empty!!(df)
                true
            else
                false
            end
        else
            false
        end
        function isapp()
            op == Val(:append) && (isrightadj() || isrecent())
        end
        @debug "watchers fetchto!: " isprep() isapp() isleftadj() isrightadj()
        if isempty(df) || isprep() || isapp()
            # When appending and cleaned starts at or before df's last timestamp,
            # skip the overlapping row(s) to avoid duplicate timestamps.
            if op == Val(:append) && !isempty(df) && !isempty(cleaned) && firstdate(cleaned) <= lastdate(df)
                trimmed = @view cleaned[rangeafter(cleaned.timestamp, lastdate(df); strict=true), :]
                if !isempty(trimmed)
                    _op(op, df, DataFrame(trimmed, copycols=false), w.capacity.view)
                end
            else
                _op(op, df, cleaned, w.capacity.view)
            end
            # Not filling gaps — fill_missing_candles! creates synthetic rows with
            # volume=0 and stale OHLCV. Gaps from no-trade periods are honest.
            if nrow(df) > w.capacity.view
                deleteat!(df, 1:(nrow(df) - w.capacity.view))
            end
        end
        @debug "watchers fetchto!: returning " lastdate(cleaned) lastdate(df)
        @ifdebug @assert nrow(df) <= w.capacity.view
        true
    end
    true
end

@doc """ Continuously attempts to fetch and append or prepend data to a dataframe until successful

$(TYPEDSIGNATURES)

This function continuously calls the `_fetchto!` function until it successfully fetches and appends or prepends data to a dataframe.
If the `_fetchto!` function fails, the function waits for a certain period before trying again.
The waiting period increases with each failed attempt.

"""
function _sticky_fetchto!(args...; kwargs...)
    backoff = 0.5
    max_backoff = 30.0
    for _ in 1:20
        try
            _fetchto!(args...; kwargs...) && return true
        catch e
            @warn "_sticky_fetchto! fetch failed, retrying" exception=(e, catch_backtrace())
        end
        sleep(backoff)
        backoff = min(backoff + 0.5, max_backoff)
    end
    @warn "_sticky_fetchto! exhausted retries"
    false
end

function _resolve(w, ohlcv_dst, ohlcv_src::DataFrame, sym=_sym(w))
    if isempty(ohlcv_src)
        @debug "_resolve: ohlcv_src DataFrame is empty for $sym, nothing to resolve"
        return
    end
    _resolve(w, ohlcv_dst, _firstdate(ohlcv_src), sym)
    _append_ohlcv!(
        w, ohlcv_dst, ohlcv_src, _lastdate(ohlcv_dst), _nextdate(ohlcv_dst, _tfr(w))
    )
end
@doc """ Ensures the dataframe is up-to-date by fetching and appending data

$(TYPEDSIGNATURES)

This function ensures the dataframe is up-to-date by fetching and appending data for a given symbol and time frame.
It checks whether the stored data is empty or corrupted and retrieves available data within the window.
If no data is available, it calculates the starting point for fetching new data.
Otherwise, it appends the available data to the dataframe, checks the continuity of the data, and updates the starting point.
If the starting point is not equal to the current timestamp, it fetches new data up to the current timestamp and checks the data continuity again.

"""
function _resolve(w, ohlcv_dst, date_candidate::DateTime, sym=_sym(w))
    tf = _tfr(w)
    if isempty(ohlcv_dst)
        @debug "_resolve: empty DataFrame for $sym, fetching initial data"
        right = date_candidate
        from = right - w.capacity.view * period(tf)
        _sticky_fetchto!(w, ohlcv_dst, sym, tf; to=right, from=from)
        return
    end
    left = _lastdate(ohlcv_dst)
    right = date_candidate
    next = _nextdate(ohlcv_dst, tf)
    if next < right
        _sticky_fetchto!(w, ohlcv_dst, sym, tf; to=right, from=left)
    else
        @ifdebug @assert isrightadj(right, left, tf) "Should $(right) is not right adjacent to $(left)!"
    end
end

@doc """ Appends data to a dataframe if it is contiguous

$(TYPEDSIGNATURES)

This function appends data from a source dataframe to a destination dataframe if the data is contiguous.
It checks if the first date in the source dataframe is the next expected date in the destination dataframe.
If it is, the function appends the data from the source dataframe to the destination dataframe and checks the continuity of the data.

"""
function _append_ohlcv!(w, ohlcv_dst, ohlcv_src, left, next)
    # at initialization it can happen that processing is too slow
    # and fetched ohlcv overlap with processed ohlcv
    @ifdebug @assert _lastdate(ohlcv_dst) == left
    @ifdebug @assert left + _tfr(w) == next
    from_range = rangeafter(ohlcv_src.timestamp, left)
    if !isempty(from_range)
        src_view = view(ohlcv_src, from_range, :)
        if src_view.timestamp[begin] == next
            @debug "Appending trades from $(_firstdate(ohlcv_src, from_range)) to $(_lastdate(ohlcv_src))"
            appendmax!(ohlcv_dst, src_view, w.capacity.view)
            # Fill gaps in the freshly appended slice (e.g. minutes with no trades
            # when deriving OHLCV from trades) so the contiguity check passes.
            fill_missing_candles!(ohlcv_dst, period(_tfr(w)))
            if nrow(ohlcv_dst) > w.capacity.view
                deleteat!(ohlcv_dst, 1:(nrow(ohlcv_dst) - w.capacity.view))
            end
            _check_contig(w, w.view)
        end
    end
end

@doc """ Ensures the dataframe is up-to-date by flushing data

$(TYPEDSIGNATURES)

This function ensures the dataframe is up-to-date by flushing data.
If the dataframe is not empty, it checks the last flushed date and the last date in the dataframe.
If these dates are not the same, it saves the data in the dataframe from the last flushed date to the last date in the dataframe and updates the last flushed date.

"""
function _flushfrom!(w)
    isempty(w.view) && return nothing
    # we assume that _load! and process already clean the data
    from_date = max(_firstdate(w.view), _lastflushed(w))
    from_date == _lastdate(w.view) && return nothing
    save_ohlcv(
        zi,
        _exc(w).name,
        _sym(w),
        string(_tfr(w)),
        w.view[DateRange(from_date)];
        check=@ifdebug(check_all_flag, :none)
    )
    _lastflushed!(w, _lastdate(w.view))
end

@kwdef mutable struct WatcherHandler2
    init = true
    init_func::Function
    corogen_func::Function
    wrapper_func::Function
    subject::Rocket.Subject{Any}
    state::Option{StreamHandler} = nothing
    subscription::Union{Nothing, Rocket.SubjectSubscription} = nothing
end

function maybe_backoff!(errors, v)
    if v isa Exception
        errors[] += 1
        if errors[] > 3
            sleep(0.1)
            errors[] = 0
        end
    end
end

function new_handler_task(w; init_func, corogen_func, wrapper_func=identity, if_func=!isnothing)
    subject = Rocket.Subject(Any)
    wh = WatcherHandler2(; init_func, corogen_func, wrapper_func, subject)
    function process_val!(w, v)
        if !isnothing(v)
            @lock w _dopush!(w, wrapper_func(v); if_func)
        end
        process!(w)
    end
    function init_watch_func(w)
        let v = @lock w if wh.init
                init_func()
            else
                return nothing
            end
            process_val!(w, v)
        end
        wh.init = false
        errors = Ref(0)
        f_push(v) = begin
            Rocket.next!(wh.subject, v)
            maybe_backoff!(errors, v)
        end
        wh.state = stream_handler(corogen_func(w), f_push)
        start_handler!(wh.state)
    end
    pipeline = wh.subject |> Rocket.map(Nothing, v -> begin
        if v isa Exception
            @error "watcher: $(w.name)" exception = v
            sleep(1)
            return nothing
        end
        process_val!(w, v)
        Rocket.next!(w.beacon.fetch, now())
    end)
    wh.subscription = Rocket.subscribe!(pipeline, Rocket.lambda(
        on_next = _ -> nothing,
        on_error = err -> logerror(w, err, catch_backtrace()),
    ))
    init_watch_func(w)
    return wh
end

handler_task!(w, sym; kwargs...) = @lget! w.handlers sym new_handler_task(w; kwargs...)
handler_task!(w; kwargs...) = w[:handler] = new_handler_task(w; kwargs...)
handler_task(w) = w.handler.subscription
handler_task(w, sym) = w.handlers[sym].subscription
function check_handler_task!(wh)
    try
        !isnothing(wh.subscription)
    catch
        @debug_backtrace
        false
    end
end

check_task!(w) = check_handler_task!(w.handler)
check_task!(w, sym) = check_handler_task!(w.handlers[sym])

function stop_watcher_handler!(wh)
    if !isnothing(wh)
        stop_handler!(wh.state)
        if !isnothing(wh.subscription)
            Rocket.unsubscribe!(wh.subscription)
            wh.subscription = nothing
        end
    end
    nothing
end

stop_handler_task!(w) = begin
    h = get(w.attrs, :handler, nothing)
    if !isnothing(h)
        stop_watcher_handler!(h)
    end
end
stop_handler_task!(w, sym) = begin
    hs = get(w.attrs, :handlers, nothing)
    if !isnothing(hs)
        h = get(hs, sym, nothing)
        if !isnothing(h)
            stop_watcher_handler!(h)
        end
    end
end
