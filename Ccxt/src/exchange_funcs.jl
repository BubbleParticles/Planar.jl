# exchange_funcs.jl - Gateway helper functions

const HAS_CACHE_TTL = 300.0  # 5 minutes in seconds
const _has_cache = Dict{String, Tuple{Dict{String, Any}, Float64}}()

function _has_cache_valid(exchange_id::String)
    if !haskey(_has_cache, exchange_id)
        return false
    end
    _, ts = _has_cache[exchange_id]
    return time() - ts < HAS_CACHE_TTL
end

function get_cached_has(client::CcxtGateway.GatewayClient, exchange_id::String)
    if !_has_cache_valid(exchange_id)
        result = CcxtGateway.fetch_exchange_has(client, exchange_id)
        if result isa Dict || result isa JSON3.Object
            _has_cache[exchange_id] = (Dict{String, Any}(string(k) => v for (k, v) in pairs(result)), time())
        end
    end
    if haskey(_has_cache, exchange_id)
        return _has_cache[exchange_id][1]
    end
    Dict{String, Any}()
end

function get_cached_has(exchange_id::String)
    client = CcxtGateway.GatewayClient()
    get_cached_has(client, exchange_id)
end

function exchange_has(client::CcxtGateway.GatewayClient, exchange_id::String, method::String)
    has_dict = get_cached_has(client, exchange_id)
    if !isempty(has_dict)
        v = get(has_dict, method, nothing)
        return v !== nothing && v !== false
    end
    false
end

function exchange_has(exchange_id::String, method::String)
    client = CcxtGateway.GatewayClient()
    exchange_has(client, exchange_id, method)
end

@doc "Check if the key `k` is supported using CcxtGateway."
function issupported(exchange_id::String, k::String)
    try
        client = CcxtGateway.GatewayClient()
        return exchange_has(client, exchange_id, k)
    catch
        false
    end
end

function _suffix_to_methods(suffix::String)
    if suffix == "Ticker"
        return ("fetchTickers", "fetchTicker", "fetchTickersWs", "fetchTickerWs")
    elseif suffix == "OrderBook"
        return ("fetchOrderBooks", "fetchOrderBook", "fetchOrderBooksWs", "fetchOrderBookWs")
    elseif suffix == "Trade"
        return ("fetchTrades", "fetchTrade", "fetchTradesWs", "fetchTradeWs")
    elseif suffix == "OHLCV"
        return ("fetchOHLCVs", "fetchOHLCV", "fetchOHLCVsWs", "fetchOHLCVWs")
    elseif suffix == "Order"
        return ("fetchOrders", "fetchOrder", "fetchOrdersWs", "fetchOrderWs")
    elseif suffix == "Balance"
        return ("fetchBalances", "fetchBalance", "fetchBalancesWs", "fetchBalanceWs")
    else
        error("Unsupported suffix: $suffix")
    end
end

function _multifunc(exchange_id::String, suffix::String, hasinputs::Bool=false)
    multi_method, single_method, multi_ws, single_ws = _suffix_to_methods(suffix)
    
    if issupported(exchange_id, multi_method) || issupported(exchange_id, multi_ws)
        return multi_method, :multi
    end
    
    if issupported(exchange_id, single_ws) || issupported(exchange_id, single_method)
        if !hasinputs
            return multi_method, :multi
        end
        return single_method, :single
    end
    
    error("Exchange $exchange_id does not support any $suffix methods")
end

function _out_as_input(inputs, data; elkey=nothing)
    if data isa Vector
        if length(data) == length(inputs)
            return Dict(i => v for (v, i) in zip(data, inputs))
        else
            @assert elkey !== nothing "Functions returned a list, but element key not provided."
            return Dict(v[elkey] => v for v in data)
        end
    elseif data isa Dict
        return Dict(i => data[i] for i in inputs if haskey(data, i))
    else
        return Dict(i => data for i in inputs)
    end
end

function choosefunc(exchange_id::String, suffix::String, inputs::AbstractVector; elkey=nothing, kwargs...)
    hasinputs = length(inputs) > 0
    method, kind = _multifunc(exchange_id, suffix, hasinputs)
    client = CcxtGateway.GatewayClient()
    
    if hasinputs
        if kind == :multi
            data = CcxtGateway.call_exchange(client, exchange_id, method; kwargs...)
            return _out_as_input(inputs, data; elkey)
        else
            out = Dict{eltype(inputs), Any}()
            for i in inputs
                out[i] = CcxtGateway.call_exchange(client, exchange_id, method; symbol=string(i), kwargs...)
            end
            return _out_as_input(inputs, out; elkey)
        end
    else
        return CcxtGateway.call_exchange(client, exchange_id, method; kwargs...)
    end
end

function choosefunc(exchange_id::String, suffix::String, inputs...; kwargs...)
    choosefunc(exchange_id, suffix, [inputs...]; kwargs...)
end

function ccxt_exchange_names()
    try
        client = CcxtGateway.GatewayClient(; timeout=5.0)
        exchanges = CcxtGateway.list_exchanges(client)
        return exchanges
    catch
        []
    end
end

export ccxt_exchange_names, choosefunc, issupported, _multifunc, _out_as_input, _suffix_to_methods
export exchange_has, get_cached_has
