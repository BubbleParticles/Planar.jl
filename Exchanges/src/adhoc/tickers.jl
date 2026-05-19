function fetch_tickers(exc::Exchange, type)
    @assert hastickers(exc) "Exchange doesn't provide tickers list."
    name = string(exc.id)
    try
        call_exchange(default_client(), name, "fetchTickers", query=Dict("type" => string(type)))
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
        call_exchange(default_client(), name, "fetchTickers", query=Dict("symbols" => join(markets, ","), "type" => string(type)))
    catch e
        @error "fetch tickers: " exception = e
        rethrow(e)
    end
end

function fetch_tickers(exc::Exchange{ExchangeID{:binance}}, type)
    @assert hastickers(exc) "Exchange doesn't provide tickers list."
    name = string(exc.id)
    query = Dict{String,String}()
    if type != :spot
        query["type"] = string(type)
    end
    try
        call_exchange(default_client(), name, "fetchTickers"; query=query)
    catch e
        @error "fetch tickers: " exception = e
        rethrow(e)
    end
end
