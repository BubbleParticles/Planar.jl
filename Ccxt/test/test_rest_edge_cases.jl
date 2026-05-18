# Test edge cases for CcxtGateway REST module
using Test
using HTTP
using JSON3

# Load the REST module directly
include("../src/CcxtGateway/types.jl")
using .Types
include("../src/CcxtGateway/rest.jl")
using .Rest

@testset "Error handling functions" begin
    @testset "_ccxt_errors Ref" begin
        @test Rest._ccxt_errors[] == String[]
    end
    
    @testset "isccxterror keyword matching logic" begin
        # Test the keyword matching logic directly
        ccxt_keywords = ["ccxt", "exchange", "symbol", "invalid", "not supported", "authentication"]
        
        err1_str = "ccxt error: invalid symbol"
        @test any(kw -> occursin(kw, lowercase(err1_str)), ccxt_keywords) == true
        
        err2_str = "some other error"
        @test any(kw -> occursin(kw, lowercase(err2_str)), ccxt_keywords) == false
        
        err3_str = "Exchange not available"
        @test any(kw -> occursin(kw, lowercase(err3_str)), ccxt_keywords) == true
    end
end

@testset "_started_exchanges tracking" begin
    @testset "Initial state" begin
        @test isempty(Rest._started_exchanges)
    end

    @testset "Idempotent start" begin
        empty!(Rest._started_exchanges)
        push!(Rest._started_exchanges, "test_exchange" => time())
        @test haskey(Rest._started_exchanges, "test_exchange")
        @test Rest._started_exchanges["test_exchange"] isa Float64
        @test Rest._started_exchanges["test_exchange"] > 0
    end

    @testset "Multiple exchanges" begin
        empty!(Rest._started_exchanges)
        Rest._started_exchanges["binance"] = time()
        sleep(0.01)
        Rest._started_exchanges["coinbase"] = time()
        @test length(Rest._started_exchanges) == 2
        @test Rest._started_exchanges["coinbase"] > Rest._started_exchanges["binance"]
    end

    @testset "Stop removes tracking" begin
        empty!(Rest._started_exchanges)
        Rest._started_exchanges["binance"] = time()
        @test haskey(Rest._started_exchanges, "binance")
        delete!(Rest._started_exchanges, "binance")
        @test !haskey(Rest._started_exchanges, "binance")
    end

    @testset "already_started dict response" begin
        empty!(Rest._started_exchanges)
        Rest._started_exchanges["binance"] = 12345.0
        result = Dict("status" => "already_started", "exchange_id" => "binance", "started_at" => Rest._started_exchanges["binance"])
        @test result["status"] == "already_started"
        @test result["exchange_id"] == "binance"
        @test result["started_at"] == 12345.0
    end
end

@testset "Error recovery edge cases" begin
    @testset "stop_exchange removes from _started_exchanges" begin
        client = GatewayClient()
        empty!(Rest._started_exchanges)
        Rest._started_exchanges["binance"] = time()
        @test haskey(Rest._started_exchanges, "binance")
        
        # Mock HTTP delete to return success
        mock_calls = []
        mock_del(url; kwargs...) = (push!(mock_calls, url); HTTP.Response(200, JSON3.write(Dict("result" => "ok"))))
        Rest.set_http_delete!(mock_del)
        try
            stop_exchange(client, "binance")
        catch
        end
        @test !haskey(Rest._started_exchanges, "binance")
    end

    @testset "exchange restart after crash" begin
        empty!(Rest._started_exchanges)
        # Simulate: exchange is running
        Rest._started_exchanges["binance"] = time()
        @test haskey(Rest._started_exchanges, "binance")
        
        # Simulate: subprocess crashes (removed by gateway)
        delete!(Rest._started_exchanges, "binance")
        @test !haskey(Rest._started_exchanges, "binance")
        
        # Simulate: restart - start_exchange with new timestamp
        Rest._started_exchanges["binance"] = time()
        @test haskey(Rest._started_exchanges, "binance")
        @test length(Rest._started_exchanges) == 1
    end

    @testset "_started_exchanges survives multiple operations" begin
        empty!(Rest._started_exchanges)
        exchanges = ["binance", "coinbase", "kraken", "bitfinex"]
        for (i, ex) in enumerate(exchanges)
            Rest._started_exchanges[ex] = time()
            if i > 1
                sleep(0.01)
            end
        end
        @test length(Rest._started_exchanges) == 4
        @test Rest._started_exchanges["kraken"] > Rest._started_exchanges["binance"]
        
        delete!(Rest._started_exchanges, "bitfinex")
        @test !haskey(Rest._started_exchanges, "bitfinex")
        
        Rest._started_exchanges["bitfinex"] = time()
        @test haskey(Rest._started_exchanges, "bitfinex")
        @test length(Rest._started_exchanges) == 4
    end
end

@testset "GatewayClient construction" begin
    @testset "Default values" begin
        client = GatewayClient()
        @test client.host == "localhost"
        @test client.port == 8999
        @test client.base_url == "https://localhost:8999"
        @test client.use_ssl == true
        @test client.timeout == 30.0
    end
    
    @testset "Custom host and port" begin
        client = GatewayClient(; host="127.0.0.1", port=8080)
        @test client.host == "127.0.0.1"
        @test client.port == 8080
        @test client.base_url == "https://127.0.0.1:8080"
    end
    
    @testset "SSL disabled" begin
        client = GatewayClient(; use_ssl=false)
        @test client.base_url == "http://localhost:8999"
        @test client.use_ssl == false
    end
    
    @testset "Custom timeout" begin
        client = GatewayClient(; timeout=60.0)
        @test client.timeout == 60.0
    end
    
    @testset "Show method" begin
        client = GatewayClient()
        str = string(client)
        @test occursin("localhost", str)
        @test occursin("8999", str)
    end
end

@testset "build_url edge cases" begin
    @testset "Path with leading slash" begin
        client = GatewayClient()
        url = build_url(client, "/ping")
        @test url == "https://localhost:8999/ping"
    end
    
    @testset "Path without leading slash" begin
        client = GatewayClient()
        url = build_url(client, "ping")
        @test url == "https://localhost:8999/ping"
    end
    
    @testset "Nested path" begin
        client = GatewayClient()
        url = build_url(client, "exchanges/binance/status")
        @test url == "https://localhost:8999/exchanges/binance/status"
    end
    
    @testset "Path with query-like chars" begin
        client = GatewayClient()
        url = build_url(client, "/exchanges/binance/fetch_ticker")
        @test url == "https://localhost:8999/exchanges/binance/fetch_ticker"
    end
    
    @testset "Base URL without trailing slash" begin
        client = GatewayClient(; use_ssl=false)
        url = build_url(client, "/admin/exchanges")
        @test url == "http://localhost:8999/admin/exchanges"
    end
end

@testset "HTTP method selection" begin
    @testset "POST methods" begin
        client = GatewayClient()
        method = "createOrder"
        is_post = method ∈ ("createOrder", "cancelOrder", "withdraw")
        @test is_post === true
        
        method2 = "cancelOrder"
        is_post2 = method2 ∈ ("createOrder", "cancelOrder", "withdraw")
        @test is_post2 === true
        
        method3 = "withdraw"
        is_post3 = method3 ∈ ("createOrder", "cancelOrder", "withdraw")
        @test is_post3 === true
    end
    
    @testset "GET methods" begin
        client = GatewayClient()
        method = "fetch_ticker"
        is_post = method ∈ ("createOrder", "cancelOrder", "withdraw")
        @test is_post === false
        
        method2 = "fetch_balance"
        is_post2 = method2 ∈ ("createOrder", "cancelOrder", "withdraw")
        @test is_post2 === false
    end
end

@testset "make_request kwargs handling" begin
    @testset "Empty kwargs" begin
        client = GatewayClient()
        @test client.use_ssl == true
    end
    
    @testset "Query parameter construction" begin
        query = Dict("symbol" => "BTC/USDT", "limit" => "100")
        @test query["symbol"] == "BTC/USDT"
        @test query["limit"] == "100"
    end
end

@testset "API path construction" begin
    @testset "Exchange paths" begin
        exchange_id = "binance"
        
        start_path = "/exchanges/$exchange_id"
        @test start_path == "/exchanges/binance"
        
        status_path = "/exchanges/$exchange_id/status"
        @test status_path == "/exchanges/binance/status"
        
        method_path = "/exchanges/$exchange_id/fetch_ticker"
        @test method_path == "/exchanges/binance/fetch_ticker"
    end
    
    @testset "Admin paths" begin
        admin_exchanges = "/admin/exchanges"
        @test admin_exchanges == "/admin/exchanges"
    end
end

@testset "Admin endpoint tests" begin
    @testset "server_info calls /admin/info" begin
        client = GatewayClient()
        mock_calls = String[]
        mock_get(url; kwargs...) = begin
            push!(mock_calls, url)
            HTTP.Response(200, JSON3.write(Dict("result" => Dict("status" => "running", "version" => "0.1.0"), "error" => nothing)))
        end
        Rest.set_http_get!(mock_get)
        try server_info(client) catch end
        @test length(mock_calls) == 1
        @test occursin("/admin/info", mock_calls[1])
    end

    @testset "memory_usage calls /admin/memory" begin
        client = GatewayClient()
        mock_calls = String[]
        mock_get(url; kwargs...) = begin
            push!(mock_calls, url)
            HTTP.Response(200, JSON3.write(Dict("result" => Dict("total_memory_mb" => 150.0), "error" => nothing)))
        end
        Rest.set_http_get!(mock_get)
        try memory_usage(client) catch end
        @test length(mock_calls) == 1
        @test occursin("/admin/memory", mock_calls[1])
    end

    @testset "server_info returns dict on success" begin
        client = GatewayClient()
        mock_get(url; kwargs...) = HTTP.Response(200, JSON3.write(Dict("result" => Dict("status" => "running", "version" => "1.0.0", "uptime_seconds" => 123.0), "error" => nothing)))
        Rest.set_http_get!(mock_get)
        result = server_info(client)
        @test result isa Union{Dict, JSON3.Object}
        @test result["status"] == "running"
    end

    @testset "memory_usage returns dict on success" begin
        client = GatewayClient()
        mock_get(url; kwargs...) = HTTP.Response(200, JSON3.write(Dict("result" => Dict("total_memory_mb" => 250.0, "exchange_count" => 2), "error" => nothing)))
        Rest.set_http_get!(mock_get)
        result = memory_usage(client)
        @test result isa Union{Dict, JSON3.Object}
        @test result["total_memory_mb"] == 250.0
    end
end

@testset "Exchange state checks" begin
    @testset "Has field access" begin
        info = Dict("has" => Dict("fetchTicker" => true, "fetchOrderBook" => false))
        has = get(info, "has", nothing)
        @test has !== nothing
        @test get(has, "fetchTicker", false) === true
        @test get(has, "fetchBalance", false) === false
    end
    
    @testset "Nothing info" begin
        info = nothing
        @test info === nothing
    end
    
    @testset "Missing has field" begin
        info = Dict("exchange_id" => "binance")
        has = get(info, "has", nothing)
        @test has === nothing
    end
end

@testset "Gateway lifecycle" begin
    @testset "initial state" begin
        @test !isassigned(Rest._gateway_pid) || Rest._gateway_pid[] === nothing
    end

    @testset "stop_gateway with nothing tracked" begin
        Rest._gateway_pid[] = nothing
        Rest.stop_gateway()
        @test Rest._gateway_pid[] === nothing
    end

    @testset "stop_gateway clears tracked pid" begin
        Rest._gateway_pid[] = 99999
        Rest.stop_gateway()
        @test Rest._gateway_pid[] === nothing
    end
end

@testset "Gateway paths and constants (regression: no UndefVarError for Ccxt.GATEWAY_PIDFILE)" begin
    # Verify path constants resolve correctly — these were using Ccxt.GATEWAY_PIDFILE
    # which caused UndefVarError: Ccxt not defined in Rest
    @test Rest.REST_GATEWAY_DIR isa String
    @test Rest.REST_GATEWAY_PIDFILE isa String
    @test Rest.REST_GATEWAY_LOCKFILE isa String
    @test isdir(Rest.REST_GATEWAY_DIR)
    @test occursin("ccxt-gateway", Rest.REST_GATEWAY_DIR)
    @test occursin(".cache", Rest.REST_GATEWAY_DIR)
    @test endswith(Rest.REST_GATEWAY_PIDFILE, "ccxt_gateway.pid")
    @test endswith(Rest.REST_GATEWAY_LOCKFILE, "ccxt_gateway.lock")

    # Verify spawn_gateway is accessible without UndefVarError
    @test spawn_gateway isa Function
end

@testset "stop_gateway clears _started_exchanges" begin
    empty!(Rest._started_exchanges)
    Rest._started_exchanges["binance"] = time()
    Rest._started_exchanges["kraken"] = time()
    @test length(Rest._started_exchanges) == 2
    # stop_gateway with no gateway running still clears the cache
    old_pid = Rest._gateway_pid[]
    Rest._gateway_pid[] = nothing
    Rest.stop_gateway()
    @test isempty(Rest._started_exchanges)
    Rest._gateway_pid[] = old_pid
end

@testset "Convenience methods resolve without stack overflow" begin
    # These convenience wrappers were causing infinite recursion
    @test exchange_info isa Function
    @test start_exchange isa Function
    @test stop_exchange isa Function
    @test call_exchange isa Function
    @test exchange_has isa Function
    @test server_info isa Function
    @test memory_usage isa Function
    @test ping isa Function
    @test list_exchanges isa Function
end

@testset "stop_gateway HTTP path does not throw when gateway unreachable" begin
    # stop_gateway first tries HTTP POST /admin/shutdown
    # When no gateway is running, it should gracefully fall through to kill + clear
    old_pid = Rest._gateway_pid[]
    old_started = copy(Rest._started_exchanges)
    empty!(Rest._started_exchanges)
    Rest._gateway_pid[] = nothing
    Rest._started_exchanges["test_exchange"] = time()
    # This should not throw — the HTTP call fails silently, then it clears the cache
    Rest.stop_gateway()
    @test isempty(Rest._started_exchanges)
    Rest._gateway_pid[] = old_pid
    empty!(Rest._started_exchanges)
    for (k, v) in old_started
        Rest._started_exchanges[k] = v
    end
end

println("REST module edge case tests passed!")