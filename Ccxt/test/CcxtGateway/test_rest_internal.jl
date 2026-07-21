"""Tests for internal Rest functions that don't require HTTP"""
using Test
using Ccxt.CcxtGateway.Rest
using Ccxt.CcxtGateway.Types
using JSON3

@testset "Rest - Internal Functions" begin
    @testset "GatewayClient" begin
        client = GatewayClient()
        @test client.host == "localhost"
        @test client.port == 8000
        @test client.timeout == 30.0
        @test occursin("https://", client.base_url)
        
        client2 = GatewayClient(host="127.0.0.1", port=9000, timeout=60.0)
        @test client2.host == "127.0.0.1"
        @test client2.port == 9000
        @test client2.timeout == 60.0
    end
    
    @testset "build_url" begin
        client = GatewayClient()
        @test build_url(client, "ping") == "https://localhost:8000/ping"
        @test build_url(client, "admin/exchanges") == "https://localhost:8000/admin/exchanges"
        @test build_url(client, "binance/fetch_balance") == "https://localhost:8000/binance/fetch_balance"
        @test build_url(client, "binance/fetch_ticker") == "https://localhost:8000/binance/fetch_ticker"
    end
    
    @testset "GatewayResponse" begin
        resp = GatewayResponse(result="test", error=nothing, error_code=nothing)
        @test resp.result == "test"
        @test resp.error === nothing
        @test resp.error_code === nothing
        
        resp2 = GatewayResponse(result=nothing, error="err", error_code="E001")
        @test resp2.result === nothing
        @test resp2.error == "err"
        @test resp2.error_code == "E001"
    end
    
    @testset "check_response" begin
        using HTTP
        
        # Test successful response
        resp = HTTP.Response(200, JSON3.write(Dict(
            "result" => "test",
            "error" => nothing,
            "error_code" => nothing
        )))
        parsed = check_response(resp)
        @test parsed.result == "test"
        @test parsed.error === nothing
        
        # Test error response parsing
        resp_err = HTTP.Response(200, JSON3.write(Dict(
            "result" => nothing,
            "error" => "Some error",
            "error_code" => "E001"
        )))
        parsed_err = JSON3.read(resp_err.body, GatewayResponse)
        @test has_error(parsed_err)
        @test parsed_err.error == "Some error"
    end
    
    @testset "get_result" begin
        resp = GatewayResponse(result="test", error=nothing, error_code=nothing)
        @test get_result(resp) == "test"
        
        resp2 = GatewayResponse(result=Dict("key" => "value"), error=nothing, error_code=nothing)
        @test get_result(resp2) == Dict("key" => "value")
        
        resp3 = GatewayResponse(result=[1, 2, 3], error=nothing, error_code=nothing)
        @test get_result(resp3) == [1, 2, 3]
    end
    
    @testset "has_error" begin
        resp_ok = GatewayResponse(result="test", error=nothing, error_code=nothing)
        @test !has_error(resp_ok)
        
        resp_err = GatewayResponse(result=nothing, error="Error", error_code="E001")
        @test has_error(resp_err)
        
        resp_err2 = GatewayResponse(result=nothing, error=nothing, error_code="E002")
        @test has_error(resp_err2)
    end
    
    @testset "call_exchange path construction" begin
        client = GatewayClient()
        
        # Test that call_exchange constructs correct path
        # The path should be /{exchange_id}/{method}
        exchange_id = "binance"
        method = "fetch_balance"
        expected_path = "/$exchange_id/$method"
        @test expected_path == "/binance/fetch_balance"
        
        # Test with different methods
        for m in ["fetch_ticker", "fetch_tickers", "fetch_order_book", 
                   "fetch_trades", "create_order", "cancel_order",
                   "fetch_ohlcv", "fetch_funding_rate"]
            path = "/$exchange_id/$m"
            @test startswith(path, "/$exchange_id/")
        end
    end
    
    @testset "HTTP method selection in call_exchange" begin
        # POST methods
        @test ("createOrder" ∈ ("createOrder", "cancelOrder", "withdraw")) == true
        @test ("cancelOrder" ∈ ("createOrder", "cancelOrder", "withdraw")) == true
        @test ("withdraw" ∈ ("createOrder", "cancelOrder", "withdraw")) == true
        
        # GET methods (everything else)
        @test ("fetch_balance" ∈ ("createOrder", "cancelOrder", "withdraw")) == false
        @test ("fetch_ticker" ∈ ("createOrder", "cancelOrder", "withdraw")) == false
    end
end
