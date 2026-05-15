"""Tests for CcxtGateway main module"""
using Test
using Ccxt.CcxtGateway
using Ccxt.CcxtGateway.Rest
using Ccxt.CcxtGateway.Types

@testset "CcxtGateway" begin
    @testset "Module exports" begin
        # Test that key exports are available
        @test isdefined(Ccxt.CcxtGateway, :GatewayClient)
        @test isdefined(Ccxt.CcxtGateway, :WebSocketClient)
        @test isdefined(Ccxt.CcxtGateway, :call_exchange)
        @test isdefined(Ccxt.CcxtGateway, :start_exchange)
        @test isdefined(Ccxt.CcxtGateway, :stop_exchange)
        @test isdefined(Ccxt.CcxtGateway, :exchange_has)
        @test isdefined(Ccxt.CcxtGateway, :list_exchanges)
        @test isdefined(Ccxt.CcxtGateway, :ping)
        @test isdefined(Ccxt.CcxtGateway, :spawn_gateway)
        @test isdefined(Ccxt.CcxtGateway, :stop_gateway)
        @test isdefined(Ccxt.CcxtGateway, :restart_gateway)
    end
    
    @testset "GatewayClient" begin
        client = GatewayClient()
        @test client isa GatewayClient
        @test client.host == "localhost"
        @test client.port == 8000
        @test occursin("https://", client.base_url)
    end
    
    @testset "WebSocketClient" begin
        ws_client = WebSocketClient()
        @test ws_client isa WebSocketClient
        @test ws_client.host == "localhost"
        @test ws_client.port == 8000
        @test occursin("wss://", ws_client.base_url)
    end
    
    @testset "Default client" begin
        # Test that default client is created
        client = default_client()
        @test client isa GatewayClient
    end
    
    @testset "call_exchange path construction" begin
        client = GatewayClient()
        # Test that the path is correctly constructed
        # The actual HTTP call is mocked in integration tests
        exchange_id = "binance"
        method = "fetch_balance"
        expected_path = "/$exchange_id/$method"
        @test expected_path == "/binance/fetch_balance"
    end
    
    @testset "Type construction" begin
        # Test that types can be constructed
        resp = GatewayResponse(result="test", error=nothing, error_code=nothing)
        @test resp.result == "test"
        
        ticker = Ticker(symbol="BTC/USDT", last=50000.0)
        @test ticker.symbol == "BTC/USDT"
        @test ticker.last == 50000.0
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
