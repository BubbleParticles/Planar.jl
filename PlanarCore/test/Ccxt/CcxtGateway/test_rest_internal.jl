# Tests for internal Rest functions that don't require HTTP
using Test
using PlanarCore.Ccxt.CcxtGateway.Rest
using PlanarCore.Ccxt.CcxtGateway.Types
using JSON3

@testset "Rest - Internal Functions" begin
    @testset "GatewayClient" begin
        client = GatewayClient()
        @test client.host == "localhost"
        @test client.port == 8999
        @test client.timeout == 30.0
        @test occursin("https://", client.base_url)

        client2 = GatewayClient(host="127.0.0.1", port=9000, timeout=60.0)
        @test client2.host == "127.0.0.1"
        @test client2.port == 9000
        @test client2.timeout == 60.0
    end

    @testset "build_url" begin
        client = GatewayClient()
        @test build_url(client, "ping") == "https://localhost:8999/ping"
        @test build_url(client, "admin/exchanges") == "https://localhost:8999/admin/exchanges"
        @test build_url(client, "binance/fetch_balance") == "https://localhost:8999/binance/fetch_balance"
        @test build_url(client, "binance/fetch_ticker") == "https://localhost:8999/binance/fetch_ticker"
    end
    
    @testset "GatewayResponse" begin
        resp = GatewayResponse("test", nothing, nothing)
        @test resp.result == "test"
        @test resp.error === nothing
        @test resp.error_code === nothing

        resp2 = GatewayResponse(nothing, "err", "E001")
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
        parsed = Rest.check_response(resp)
        @test parsed.result == "test"
        @test parsed.error === nothing

        # Test error response
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
        resp = GatewayResponse("test", nothing, nothing)
        @test get_result(resp) == "test"

        resp2 = GatewayResponse(Dict("key" => "value"), nothing, nothing)
        @test get_result(resp2) == Dict("key" => "value")

        resp3 = GatewayResponse([1, 2, 3], nothing, nothing)
        @test get_result(resp3) == [1, 2, 3]
    end

    @testset "has_error" begin
        resp_ok = GatewayResponse("test", nothing, nothing)
        @test !has_error(resp_ok)

        resp_err = GatewayResponse(nothing, "Error", "E001")
        @test has_error(resp_err)

        resp_err2 = GatewayResponse(nothing, nothing, "E002")
        @test has_error(resp_err2)
    end
    
    @testset "call_exchange routes through mocked HTTP" begin
        using HTTP
        prev_init = Rest._gateway_initialized[]
        prev_get = Rest._http_get[]
        got = Ref("")
        try
            Rest._gateway_initialized[] = true
            set_http_get!((url; kwargs...) -> begin
                got[] = url
                HTTP.Response(200, JSON3.write(Dict("result" => Dict("ok" => true), "error" => nothing, "error_code" => nothing)))
            end)
            out = call_exchange(GatewayClient(), "binance", "fetch_balance")
            @test endswith(got[], "/exchanges/binance/fetch_balance")
            @test out["ok"] == true
        finally
            Rest._gateway_initialized[] = prev_init
            set_http_get!(prev_get)
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
