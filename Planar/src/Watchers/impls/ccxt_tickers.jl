using PlanarCore.Fetch.Exchanges
using .Exchanges.Ccxt: choosefunc
using ..WatchersImpls: _wconvert, _wkey
using ..Watchers: JSON3

baremodule LogTickersWatcher end

const CcxtTickerVal = Val{:ccxt_ticker}
@doc "The ccxt ticker object as a NamedTuple."
const CcxtTicker = @NamedTuple begin
    symbol::String
    timestamp::Option{DateTime}
    open::Option{Float64}
    high::Option{Float64}
    low::Option{Float64}
    close::Option{Float64}
    previousClose::Option{Float64}
    bid::Option{Float64}
    ask::Option{Float64}
    bidVolume::Option{Float64}
    askVolume::Option{Float64}
    last::Option{Float64}
    vwap::Option{Float64}
    change::Option{Float64}
    percentage::Option{Float64}
    average::Option{Float64}
    baseVolume::Option{Float64}
    quoteVolume::Option{Float64}
end

_ids!(attrs, ids) = attrs[:ids] = string.(ids)
_ids(w) = attr(w, :ids)

@doc """ Create a `Watcher` instance that tracks all markets for an exchange (ccxt)

$(TYPEDSIGNATURES)

This function creates a `Watcher` instance that tracks all markets for an exchange (ccxt).
It sets the symbol, exchange, and time frame for the watcher, and prepares the trades buffer.
It also sets the watcher's status to pending and initializes the last fetched and last flushed timestamps.

"""
function ccxt_tickers_watcher(
    exc::Exchange;
    val=CcxtTickerVal(),
    wid=CcxtTickerVal.parameters[1],
    syms=keys(exc.markets),
    interval=Second(5),
    start=true,
    load=true,
    process=false,
    buffer_capacity=100,
    view_capacity=2000,
    flush=true,
    iswatch=nothing,
)
    check_timeout(exc, interval)
    attrs = Dict{Symbol,Any}()
    attrs[:iswatch] = something(iswatch) do
        has(exc, :watchTickersForSymbols) || has(exc, :watchTickers)
    end
    attrs[:issandbox] = issandbox(exc)
    attrs[:excparams] = Dict{String,Any}()
    attrs[:excaccount] = account(exc)
    _sym!(attrs, syms) # FIXME: this line should be removed
    _ids!(attrs, syms)
    _exc!(attrs, exc)
    watcher_type = Dict{String,CcxtTicker}
    wid = string(wid, "-", hash((exc.id, syms, attrs[:issandbox])))
    watcher(
        watcher_type,
        wid,
        val;
        start,
        load,
        flush,
        process,
        buffer_capacity,
        view_capacity,
        fetch_interval=interval,
        attrs,
    )
end
ccxt_tickers_watcher(syms...) = ccxt_tickers_watcher([syms...])

function _parse_ticker_snapshot(snap)
    result = Dict{String,CcxtTicker}()
    raw = snap isa Union{Dict, JSON3.Object} ? snap : nothing
    if isnothing(raw)
        @error "watcher: failed to parse ticker snapshot" snap
        return result
    end
    if !isempty(raw)
        for (_, py_ticker) in pairs(raw)
            # A single malformed ticker (e.g. null `symbol`, which is a required
            # `String` field, or a transient null in a numeric field) must not
            # throw here — an unhandled exception would abort parsing of the whole
            # WS snapshot and drop *every* ticker in the message.
            try
                ticker = fromdict(CcxtTicker, String, py_ticker, _wkey, _wconvert)
                symkey = something(ticker.symbol, "")
                isempty(symkey) && continue
                result[symkey] = ticker
            catch e
                @debug "watcher: failed to parse ticker, skipping" exception=(e, catch_backtrace())
            end
        end
    end
    result
end

@doc """ Fetches trades and updates the watcher's trades buffer

$(TYPEDSIGNATURES)

This function fetches trades for the watcher's symbol and time frame, and updates the watcher's trades buffer.
If new trades are fetched, they are appended to the trades buffer and the last fetched timestamp is updated.

"""
_fetch!(w::Watcher, ::CcxtTickerVal) = _tfunc(w)()
function _check_ids(exc, ids)
    markets = keys(exc.markets)
    issymbol_available(sym) =
        if sym ∉ markets
            @warn "tickers watcher: symbol not on exchange" sym
            false
        else
            true
        end
    v = filter(issymbol_available, ids)
    if isempty(v)
        @debug "tickers watcher: no symbols" ids exc
        error("tickers watcher: no symbols on exchange")
    end
    v
end
_func_args(exc, ids) =
    if isempty(ids)
        ()
    else
        (_check_ids(exc, ids),)
    end
function _reset_tickers_func!(w::Watcher)
    attrs = w.attrs
    eid = exchangeid(_exc(w))
    exc = getexchange!(
        eid, attrs[:excparams]; sandbox=attrs[:issandbox], account=attrs[:excaccount]
    )
    _exc!(attrs, exc)

    # Ensure the gateway exchange subprocess is started so its `has` dict is populated.
    _start_gateway_exchange(string(exc.id))

    # don't pass empty args to imply all symbols
    ids = _ids(w)
    @assert ids isa Vector
    args = _func_args(exc, ids)
    watch_func = first(exc, :watchTickersForSymbols, :watchTickers)
    # Use _first for WS-capable REST polling too — tries fetchTickersWs with
    # automatic fallback to fetchTickers on gateway failure.
    fetch_one_shot = first(exc, :fetchTickersWs, :fetchTickers)
    fetch_func = if fetch_one_shot !== nothing
        if isempty(ids)
            fetch_one_shot()
        else
            fetch_one_shot(; symbols=_check_ids(exc, ids))
        end
    else
        nothing
    end
    iswatch = if haskey(attrs, :iswatch)
        attrs[:iswatch]::Bool
    else
        has(exc, :watchTickersForSymbols) || has(exc, :watchTickers)
    end
    if iswatch
        corogen_func(_) = coro_func() = watch_func(args...)
        init_func() = fetch_func !== nothing ? fetch_func(; timeout=300.0) : nothing
        handler_task!(
            w;
            init_func,
            corogen_func,
            wrapper_func=_parse_ticker_snapshot,
            if_func=!isempty,
        )

        # Try websocket subscription; on failure fall back to REST polling.
        exc_id_str = string(exc.id)
        _rest_fallback = _make_tickers_func(w, exc_id_str, attrs, ids)
        if _setup_ws_watcher!(w, exc_id_str, "watchTickers", Dict{String,Any}("symbols" => ids), _rest_fallback)
            # WS connected — _tfunc is set up with reconnect logic
        else
            @warn "WebSocket unavailable for $(w.name), falling back to REST polling"
            _tfunc!(attrs, _rest_fallback)
        end
    else
        _tfunc!(attrs, _make_tickers_func(w, string(exc.id), attrs, ids))
    end
end

"""Create a polling function that fetches tickers via REST each cycle.
Tries the one-shot WS method (`fetchTickersWs`) first; on failure falls back to
REST (`fetchTickers`). Without this fallback, a failed WS call returns `nothing`,
the buffer stays empty, and `_process!` sees `isempty(w)` → returns immediately."""
function _make_tickers_func(w, exc_id::String, attrs, ids)
    fetch_symbols = _check_ids(_exc(w), ids)
    exc = _exc(w)
    fetch_func_ws = first(exc, :fetchTickersWs)
    fetch_func_rest = first(exc, :fetchTickers)
    return function ()
        process_subj = @lget! attrs :tickers_process_subject Rocket.Subject(Any)
        fetched = @lock w begin
            time = now()
            resp = try
                if fetch_func_ws !== nothing
                    fetch_func_ws(; symbols=fetch_symbols)
                elseif fetch_func_rest !== nothing
                    fetch_func_rest(; symbols=fetch_symbols)
                else
                    nothing
                end
            catch e
                # WS one-shot failed — try REST as fallback
                @warn "tickers WS poll failed, trying REST" exception=(e,)
                try
                    fetch_func_rest !== nothing && fetch_func_rest(; symbols=fetch_symbols)
                catch e2
                    @warn "tickers REST poll failed too" exception=(e2,)
                    nothing
                end
            end
            result = _parse_ticker_snapshot(resp)
            if !isempty(result)
                pushnew!(w, result, time)
                true
            else
                false
            end
        end
        if fetched
            Rocket.next!(process_subj, w)
        end
        return fetched
    end
end

_start!(w::Watcher, ::CcxtTickerVal) = _reset_tickers_func!(w)

function _stop!(w::Watcher, ::CcxtTickerVal)
    stop_handler_task!(w)
    sub_id = get(w.attrs, :ws_sub_id, nothing)
    if sub_id !== nothing
        ws_client = get(w.attrs, :ws_client, nothing)
        if ws_client !== nothing
            _WS = Fetch.Exchanges.Ccxt.CcxtGateway
            try _WS.send_unsubscribe(ws_client, sub_id) catch end
        end
        delete!(w.attrs, :ws_sub_id)
    end
end

function _init!(w::Watcher, ::CcxtTickerVal)
    exc = _exc(w)
    _key!(
        w,
        string(
            "ccxt_", exc.name, issandbox(exc), "_tickers_", join(snakecased.(_ids(w)), "_")
        ),
    )
    default_init(w, Dict{String,DataFrame}())
end

function _ccxt_tickers_process!(dict, buf, maxlen)
    data = @collect_buffer_data buf String CcxtTicker
    for (key, nts) in pairs(data)
        df_row = get!(dict, key) do; DataFrame(); end
        if nrow(df_row) > 0
            last_val = last(df_row)
            new_nts = filter(!=(last_val), nts)
            isempty(new_nts) || appendmax!(df_row, new_nts, maxlen)
        else
            appendmax!(df_row, nts, maxlen)
        end
    end
end

_process!(w::Watcher, ::CcxtTickerVal) = default_process(w, _ccxt_tickers_process!)
