# Tests for CcxtGateway main module
using Test
using PlanarCore.Ccxt.CcxtGateway
using PlanarCore.Ccxt.CcxtGateway.Rest
using PlanarCore.Ccxt.CcxtGateway.Types

@testset "CcxtGateway" begin
    @testset "Module exports" begin
        # Test that key exports are available
        @test isdefined(CcxtGateway, :GatewayClient)
        @test isdefined(CcxtGateway, :GatewayWSClient)
        @test isdefined(CcxtGateway, :call_exchange)
        @test isdefined(CcxtGateway, :start_exchange)
        @test isdefined(CcxtGateway, :stop_exchange)
        @test isdefined(CcxtGateway, :fetch_exchange_has)
        @test isdefined(CcxtGateway, :list_exchanges)
        @test isdefined(CcxtGateway, :ping)
        @test isdefined(CcxtGateway, :spawn_gateway)
        @test isdefined(CcxtGateway, :stop_gateway)
        @test isdefined(CcxtGateway, :restart_gateway)
    end
    
    @testset "GatewayClient" begin
        client = GatewayClient()
        @test client isa GatewayClient
        @test client.host == "localhost"
        @test client.port == 8999
        @test occursin("https://", client.base_url)
    end

    @testset "GatewayWSClient" begin
        ws_client = CcxtGateway.WSClient.GatewayWSClient()
        @test ws_client isa CcxtGateway.WSClient.GatewayWSClient
        @test ws_client.host == "localhost"
        @test ws_client.port == 8999
        @test occursin("wss://", ws_client.url)
    end
    
    @testset "Default client" begin
        # Test that default client is created
        client = default_client()
        @test client isa GatewayClient
    end
    
    @testset "call_exchange routes through mocked HTTP" begin
        using HTTP, JSON3
        prev_init = Rest._gateway_initialized[]
        prev_get = Rest._http_get[]
        got = Ref("")
        try
            Rest._gateway_initialized[] = true
            Rest.set_http_get!((url; kwargs...) -> begin
                got[] = url
                HTTP.Response(200, JSON3.write(Dict("result" => Dict("ok" => true), "error" => nothing, "error_code" => nothing)))
            end)
            out = Rest.call_exchange(GatewayClient(), "binance", "fetch_balance")
            @test endswith(got[], "/exchanges/binance/fetch_balance")
            @test out["ok"] == true
        finally
            Rest._gateway_initialized[] = prev_init
            Rest.set_http_get!(prev_get)
        end
    end

    @testset "Type construction" begin
        # Test that types can be constructed
        resp = GatewayResponse("test", nothing, nothing)
        @test resp.result == "test"

        ticker_payload = Dict{String,Any}("symbol" => "BTC/USDT", "last" => 50000.0)
        r = GatewayResponse(ticker_payload, nothing, nothing)
        @test get_result(r)["symbol"] == "BTC/USDT"
        @test get_result(r)["last"] == 50000.0
    end
    
    @testset "spawn_gateway" begin
        # This test checks if gateway can be spawned
        # It may fail if Python/gateway is not available
        try
            pid = spawn_gateway()
            @test pid isa Integer || pid === nothing
        catch e
            @test_skip "Gateway spawn failed: $e"
        end
    end
    
    @testset "ping" begin
        # Test ping - may fail if gateway not running
        try
            result = ping()
            @test result isa Bool
        catch e
            @test_skip "Ping failed: $e"
        end
    end
end
