using PlanarCore.Fetch: OrderBookLevel, L1, L2, L3
using PlanarCore.Ccxt: CcxtGateway, default_client, call_exchange
using PlanarCore.Fetch.Exchanges.ExchangeTypes: _supports_ws_method

const CcxtOrderBookVal = Val{:ccxt_order_book}

_l1func(w) = attr(w, :l1func)
_l2func(w) = attr(w, :l2func)
@doc """ Assigns the appropriate order book function based on the level.

$(TYPEDSIGNATURES)

The function assigns the appropriate order book function to the `attrs` dictionary based on the `level` provided.
It tries to assign the function in the order of preference and breaks the loop as soon as a function is successfully assigned.
If no function can be assigned, it throws an assertion error.

"""
function _ob_func(attrs, level)
    name = "$(level)OrderBook"
    names = if level == L1
        ("OrderBook", name)
    else
        (name,)
    end
    for func in names
        try
            _tfunc!(attrs, func)
            break
        catch e
            @error e
        end
    end
    @assert :tfunc in keys(attrs)
end

@doc """ Creates a watcher for the order book of a given exchange and symbol.

$(TYPEDSIGNATURES)

This function creates a watcher for the order book of a given exchange and symbol.
It sets up the watcher with the specified `level`, `interval`, and other parameters.
The watcher is then started and returned for use.
The function checks for timeout, sets up the attributes, and assigns the appropriate order book function based on the level.

"""
function ccxt_orderbook_watcher(exc::Exchange, sym; level=L1, interval=Second(1), iswatch=nothing)
    check_timeout(exc, interval)
    attrs = Dict{Symbol,Any}()
    _sym!(attrs, sym)
    _exc!(attrs, exc)
    _tfr!(attrs, timeframe)
    attrs[:oblevel] = level
    attrs[:issandbox] = issandbox(exc)
    attrs[:excparams] = Dict{String,Any}()
    attrs[:excaccount] = account(exc)
    attrs[:iswatch] = something(iswatch) do
        has(exc, :watchOrderBookForSymbols) || has(exc, :watchOrderBook)
    end
    _ob_func(attrs, OrderBookLevel(level))
    watcher_type = DataFrame
    wid = string(
        CcxtOrderBookVal.parameters[1], "-", hash((exc.id, attrs[:issandbox], sym, level))
    )
    w = watcher(
        watcher_type,
        wid,
        CcxtOrderBookVal();
        start=false,
        load=false,
        flush=true,
        process=true,
        buffer_capacity=10,
        view_capacity=1000,
        fetch_interval=interval,
        fetch_timeout=2interval,
        flush_interval=3interval,
        attrs,
    )
    _key!(w, "ccxt_$(exc.name)_orderbook_$(snakecased(_sym(w)))")
    start!(w)
    w
end

function ccxt_orderbook_watcher(exc::Exchange, syms::Iterable; kwargs...)
    tasks = [errormonitor(@async ccxt_orderbook_watcher(exc, s; kwargs...)) for s in syms]
    [fetch(t) for t in tasks]
end

function _init!(w::Watcher, ::CcxtOrderBookVal)
    default_init(w, DataFrame())
    _lastflushed!(w, DateTime(0))
end

_totimestamp(v) = dt(Int(v))
_timestamp!(d, v) = metadata!(d, "timestamp", v)
_symbol!(d, ob) = metadata!(d, "symbol", string(get(ob, "symbol", "unknown")))
_obtimestamp(d::DataFrame) = metadata(d, "timestamp")

@doc """ Converts order book data to a DataFrame.

$(TYPEDSIGNATURES)

This function takes an order book and converts it into a DataFrame.
It creates separate columns for timestamp, bid price, bid amount, ask price, and ask amount.
The function also ensures that the DataFrame is created even if the bids and asks are uneven by using the zip function.

"""
function _ob_to_df(ob)
    out = (
        timestamp=DateTime[],
        bid_price=Float64[],
        bid_amount=Float64[],
        ask_price=Float64[],
        ask_amount=Float64[],
    )
    # Guard against null/missing timestamp (same pattern as Fetch/src/orderbook.jl:77)
    ts_raw = get(ob, "timestamp", nothing)
    ts = ts_raw === nothing ? now() : _totimestamp(ts_raw)
    # Guard against null/missing bids/asks — return empty DataFrame gracefully
    bids = something(get(ob, "bids", []), [])
    asks = something(get(ob, "asks", []), [])
    for (bid, ask) in zip(bids, asks)
        push!(out.timestamp, ts)
        push!(out.bid_price, Float64(bid[1]))
        push!(out.bid_amount, Float64(bid[2]))
        push!(out.ask_price, Float64(ask[1]))
        push!(out.ask_amount, Float64(ask[2]))
    end
    d = df!(out)
    _timestamp!(d, ts)
    _symbol!(d, ob)
    d
end

@doc """ Fetches the order book data and pushes it to the watcher.

$(TYPEDSIGNATURES)

This function delegates to the tfunc callable set by `_start!`, which is either
a REST polling closure or `check_task!` for WebSocket streaming.

"""
function _fetch!(w::Watcher, ::CcxtOrderBookVal)
    _tfunc(w)()
end

@doc """ Processes the watcher data.

$(TYPEDSIGNATURES)

This function processes the watcher data by appending it to the view.
It uses the `appendby` function to append the last buffer value to the view, with a capacity limit.

"""
function _process!(w::Watcher, ::CcxtOrderBookVal)
    appendby(v, b, cap) = appendmax!(v, last(b).value, cap)
    default_process(w, appendby)
end

@doc """ Flushes the watcher data.

$(TYPEDSIGNATURES)

This function checks if the watcher view is empty and returns nothing if it is.
Otherwise, it gets the range of data after the last flushed time from the buffer and saves it if the range has data.
The last flushed time is then updated to the time of the last data in the buffer.

"""
function _flush!(w::Watcher, ::CcxtOrderBookVal)
    isempty(w.view) && return nothing
    range = rangeafter(w.buffer, (; time=_lastflushed(w)); by=x -> x.time)
    if !isempty(range)
        toflush = vcat(getproperty.(view(w.buffer, range), :value)...)
        save_data(zi[], _key(w), toflush; serialize=false, type=Float64)
        _lastflushed!(w, w.buffer[end].time)
    end
end

function _start!(w::Watcher, ::CcxtOrderBookVal)
    attrs = w.attrs
    eid = exchangeid(_exc(w))
    exc = getexchange!(
        eid, attrs[:excparams]; sandbox=attrs[:issandbox], account=attrs[:excaccount]
    )
    _exc!(attrs, exc)

    # Ensure the gateway exchange subprocess is started so its `has` dict is populated.
    _start_gateway_exchange(string(exc.id))

    _ob_func(attrs, OrderBookLevel(attrs[:oblevel]))
    # Conditionally include fetchOrderBookWs — some exchanges (e.g., Binance) only
    # support it for certain market types (e.g., swap). The helper checks this.
    sym = _sym(w)
    ws_methods = if _supports_ws_method(exc, sym, "OrderBook")
        (:fetchOrderBookWs, :fetchOrderBook)
    else
        (:fetchOrderBook,)
    end
    iswatch = get(attrs, :iswatch, has(exc, :watchOrderBookForSymbols) || has(exc, :watchOrderBook))
    if iswatch
        watch_func = first(exc, :watchOrderBookForSymbols, :watchOrderBook)
        sym = _sym(w)

        # Initial REST fetch for handler_task! init
        init_fetch = function ()
            if fetch_func !== nothing
                return fetch_func(; symbol=sym, timeout=300.0)
            end
            return nothing
        end
        init_func() = init_fetch()
        wrapper_func(v) = _ob_to_df(v)
        handler_task!(w; init_func, corogen_func, wrapper_func, if_func=!isempty)

        if _setup_ws_watcher!(w, string(exc.id), "watchOrderBook", Dict{String,Any}("symbol" => sym), _make_orderbook_func(w, string(exc.id), exc))
            # WS connected — _tfunc is set up with reconnect logic
        else
            @warn "WebSocket unavailable for $(w.name), falling back to REST polling"
            _tfunc!(attrs, _make_orderbook_func(w, string(exc.id), exc))
        end
    else
        _tfunc!(attrs, _make_orderbook_func(w, string(eid), exc))
    end
end

"""Create a polling function that fetches order book via REST (with WS fallback) each cycle."""
function _make_orderbook_func(w, exc_id::String, exc)
    sym = _sym(w)
    ws_methods = if _supports_ws_method(exc, sym, "OrderBook")
        (:fetchOrderBookWs, :fetchOrderBook)
    else
        (:fetchOrderBook,)
    end
    fetch_func = first(exc, ws_methods...)
    return function ()
        @lock w begin
            sym = _sym(w)
            ob = try
                if fetch_func !== nothing
                    fetch_func(; symbol=sym)
                else
                    nothing
                end
            catch e
                @debug "orderbook poll failed" exception=(e,)
                nothing
            end
            if !isnothing(ob) && !isempty(ob)
                result = _ob_to_df(ob)
                pushnew!(w, result, _obtimestamp(result))
                true
            else
                false
            end
        end
    end
end

function _stop!(w::Watcher, ::CcxtOrderBookVal)
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

const OBCHUNKS = (100, 5) # chunks of the z array
@doc """ Loads order book data.

$(TYPEDSIGNATURES)

This function loads the order book data from the specified location.

"""
function _load_ob_data(w)
    load_data(zi[], _key(w); sz=OBCHUNKS, serialized=false, type=Float64)
end
