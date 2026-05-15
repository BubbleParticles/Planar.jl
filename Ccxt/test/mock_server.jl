"""Mock HTTP server for testing CcxtGateway"""
module MockServer

using HTTP, JSON3

export start_mock_server, stop_mock_server, get_requests, clear_requests

const _server = Ref{Any}(nothing)
const _requests = Ref{Vector{Dict}}(Dict[])
const _responses = Ref{Dict{String, Any}}(Dict{String, Any}())

function start_mock_server(port::Int=8888)
    # Default responses
    default_responses = Dict(
        "/ping" => Dict("result" => "pong", "error" => nothing, "error_code" => nothing),
        "/admin/exchanges" => Dict("result" => ["binance", "kraken"], "error" => nothing),
        "/admin/info" => Dict("result" => Dict("version" => "1.0.0"), "error" => nothing),
        "/admin/memory" => Dict("result" => Dict("rss_mb" => 100.0), "error" => nothing),
    )
    _responses[] = default_responses
    
    server = HTTP.serve!(port) do req
        # Record request
        push!(_requests[], Dict(
            "method" => req.method,
            "path" => HTTP.uri(req).path,
            "query" => HTTP.queryparams(req),
            "body" => isempty(req.body) ? nothing : JSON3.read(String(req.body))
        ))
        
        path = HTTP.uri(req).path
        
        # Check if path matches exchange pattern /{exchange_id}/{method}
        m = match(r"^/([^/]+)/([^/?]+)", path)
        if m !== nothing
            exchange_id, method = m.captures
            # Return mock data based on method
            result = get_mock_data(String(method))
            resp = Dict("result" => result, "error" => nothing, "error_code" => nothing)
            return HTTP.Response(200, JSON3.write(resp))
        end
        
        # Check static paths
        if haskey(_responses[], path)
            return HTTP.Response(200, JSON3.write(_responses[][path]))
        end
        
        # Default 404
        return HTTP.Response(404, JSON3.write(Dict("error" => "Not found")))
    end
    
    _server[] = server
    port
end

function stop_mock_server()
    if _server[] !== nothing
        close(_server[])
        _server[] = nothing
    end
end

function get_mock_data(method::String)
    data = Dict(
        "fetch_balance" => Dict("USDT" => Dict("free" => 1000.0, "used" => 500.0, "total" => 1500.0)),
        "fetch_ticker" => Dict("symbol" => "BTC/USDT", "last" => 50000.0, "bid" => 49900.0, "ask" => 50100.0),
        "fetch_tickers" => Dict("BTC/USDT" => Dict("last" => 50000.0)),
        "fetch_order_book" => Dict("bids" => [[49900.0, 1.0]], "asks" => [[50100.0, 1.0]], "timestamp" => 1000000),
        "fetch_trades" => [Dict("id" => "1", "price" => 50000.0, "amount" => 1.0)],
        "fetch_orders" => [Dict("id" => "1", "status" => "open", "symbol" => "BTC/USDT")],
        "fetch_open_orders" => [Dict("id" => "1", "status" => "open")],
        "fetch_ohlcv" => [[1000000, 50000.0, 51000.0, 49000.0, 50500.0, 1000.0]],
        "fetch_funding_rate" => Dict("symbol" => "BTC/USDT", "rate" => 0.0001),
        "status" => Dict("exchange_id" => "test", "running" => true, "pid" => 1234),
    )
    get(data, method, Dict())
end

function get_requests()
    _requests[]
end

function clear_requests()
    empty!(_requests[])
end

end # module MockServer
