using ..Fetch.Exchanges
using .Exchanges.Ccxt: choosefunc
using ..WatchersImpls: _wconvert, _wkey
using ..Watchers: JSON3

baremodule LogTickersWatcher end

const CcxtTickerVal = Val{:ccxt_ticker}
@doc "The ccxt ticker object as a NamedTuple."
const CcxtTicker = @NamedTuple begin
    symbol::String
    timestamp::Option{DateTime}
    open::Float64
    high::Float64
    low::Float64
    close::Float64
    previousClose::Option{Float64}
    bid::Float64
    ask::Float64
    bidVolume::Option{Float64}
    askVolume::Option{Float64}
    last::Float64
    vwap::Float64
    change::Float64
    percentage::Float64
    average::Float64
    baseVolume::Float64
    quoteVolume::Float64
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
    attrs[:iswatch] = something(iswatch, false)::Bool
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
            ticker = fromdict(CcxtTicker, String, py_ticker, _wkey, _wconvert)
            result[ticker.symbol] = ticker
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
    fetch_func = choosefunc(string(exc.id), "Ticker", args...)
    # The CcxtGateway returns a non-nothing closure for every websocket
    # method on `first(...)`, regardless of whether the exchange actually
    # supports it. This forces every watcher down the `iswatch=true`
    # path which runs `check_task!` but never fetches data, leaving the
    # buffer stale. Force the polling path unless the user explicitly
    # opted in to websockets via the constructor's `iswatch` argument.
    iswatch = if haskey(attrs, :iswatch)
        attrs[:iswatch]::Bool
    else
        false
    end
    if iswatch
        corogen_func(_) = coro_func() = watch_func(args...)
        init_func() = fetch_func
        handler_task!(
            w;
            init_func,
            corogen_func,
            wrapper_func=_parse_ticker_snapshot,
            if_func=!isempty,
        )
        _tfunc!(attrs, () -> check_task!(w))
    else
        # Capture exchange id, args, and ids so the closure can re-invoke
        # `choosefunc` on every fetch. The result of `choosefunc` itself is
        # a one-shot gateway response; the real fix is to call the gateway
        # again before each poll, not repeat the snapshot.
        exc_id = string(exc.id)
        sym_ids = ids
        fetch_symbols = _check_ids(exc, ids)
        tickers_func() = begin
            process_subj = @lget! attrs :tickers_process_subject Rocket.Subject(Any)
            fetched = @lock w begin
                time = now()
                # Re-evaluate `choosefunc` on every poll so the gateway
                # returns fresh data instead of repeating the first snapshot.
                resp = if fetch_func isa Function
                    try
                        fetch_func()
                    catch
                        choosefunc(exc_id, "Ticker", fetch_symbols)
                    end
                else
                    # CcxtGateway path: re-invoke choosefunc each cycle.
                    choosefunc(exc_id, "Ticker", fetch_symbols)
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
        _tfunc!(attrs, tickers_func)
    end
end

_start!(w::Watcher, ::CcxtTickerVal) = _reset_tickers_func!(w)
_stop!(w::Watcher, ::CcxtTickerVal) = stop_handler_task!(w)

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
