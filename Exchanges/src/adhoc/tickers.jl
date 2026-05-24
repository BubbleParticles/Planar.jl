function fetch_tickers(exc::Exchange, type)
    @assert hastickers(exc) "Exchange doesn't provide tickers list."
    name = string(exc.id)
    try
        call_exchange(default_client(), name, "fetchTickers", body=Dict("params" => Dict("type" => string(type))))
    catch e
        @error "fetch tickers: " exception = e
        rethrow(e)
    end
end

function syms_by_market_type(exc, type)
    tp = string(type)
    [sym for (sym, mkt) in exc.markets if mkt["type"] == tp]
end

function fetch_tickers(exc::Exchange{ExchangeID{:bitrue}}, type)
    name = string(exc.id)
    markets = syms_by_market_type(exc, type)
    try
        call_exchange(default_client(), name, "fetchTickers", body=Dict("symbols" => join(markets, ","), "params" => Dict("type" => string(type))))
    catch e
        @error "fetch tickers: " exception = e
        rethrow(e)
    end
end

function fetch_tickers(exc::Exchange{ExchangeID{:binance}}, type)
    @assert hastickers(exc) "Exchange doesn't provide tickers list."
    name = string(exc.id)
    body = Dict{String,Any}()
    if type != :spot
        body["params"] = Dict("type" => string(type))
    end
    try
        call_exchange(default_client(), name, "fetchTickers"; body=body)
    catch e
        @error "fetch tickers: " exception = e
        rethrow(e)
    end
end
