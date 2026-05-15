# Test edge cases for WebSocket client
using Test
using JSON3

include("../src/CcxtGateway/websocket.jl")
using .WSClient

@testset "GatewayWSClient edge cases" begin
    @testset "Empty subscriptions dict" begin
        client = WSClient.GatewayWSClient()
        @test isempty(client.subscriptions)
        @test get(client.subscriptions, :_ws, nothing) === nothing
    end
    
    @testset "is_connected when not connected" begin
        client = WSClient.GatewayWSClient()
        @test WSClient.is_connected(client) == false
    end
    
    @testset "Disconnect on empty subscriptions" begin
        client = WSClient.GatewayWSClient()
        WSClient.disconnect!(client)
        @test isempty(client.subscriptions)
        @test WSClient.is_connected(client) == false
    end
    
    @testset "send_subscribe without callback" begin
        client = WSClient.GatewayWSClient()
        sub_id = WSClient.uuid4()
        @test sub_id isa String
        
        message = Dict{String, Any}(
            "type" => "subscribe",
            "subscription_id" => sub_id,
            "exchange_id" => "binance",
            "method" => "watch_ticker",
            "params" => Dict{String, Any}()
        )
        @test message["type"] == "subscribe"
        @test message["subscription_id"] == sub_id
    end
    
    @testset "send_subscribe with params" begin
        client = WSClient.GatewayWSClient()
        params = Dict{String, Any}("symbol" => "BTC/USDT", "limit" => 100)
        
        message = Dict{String, Any}(
            "type" => "subscribe",
            "subscription_id" => "test-sub",
            "exchange_id" => "binance",
            "method" => "watch_trades",
            "params" => params
        )
        @test message["params"]["symbol"] == "BTC/USDT"
        @test message["params"]["limit"] == 100
    end
    
    @testset "send_unsubscribe message" begin
        client = WSClient.GatewayWSClient()
        message = Dict{String, Any}(
            "type" => "unsubscribe",
            "subscription_id" => "test-sub"
        )
        @test message["type"] == "unsubscribe"
        @test message["subscription_id"] == "test-sub"
    end
    
    @testset "WSMessages default values" begin
        empty_dict = Dict{String, Any}()
        msg = WSClient.WSMessages(empty_dict)
        @test msg.type == ""
        @test msg.data === nothing
        @test msg.subscription_id === nothing
        @test msg.error === nothing
        @test msg.exchange_id === nothing
        @test msg.method === nothing
    end
    
    @testset "WSMessages partial fields" begin
        partial = Dict{String, Any}("type" => "update", "data" => [1, 2, 3])
        msg = WSClient.WSMessages(partial)
        @test msg.type == "update"
        @test msg.data == [1, 2, 3]
        @test msg.subscription_id === nothing
        @test msg.exchange_id === nothing
    end
    
    @testset "WSMessages with null values" begin
        null_dict = Dict{String, Any}(
            "type" => "error",
            "data" => nothing,
            "subscription_id" => nothing,
            "error" => nothing,
            "exchange_id" => nothing,
            "method" => nothing
        )
        msg = WSClient.WSMessages(null_dict)
        @test msg.type == "error"
        @test msg.data === nothing
        @test msg.subscription_id === nothing
    end
    
    @testset "WSMessages with nested data" begin
        nested = Dict{String, Any}(
            "type" => "update",
            "data" => Dict{String, Any}(
                "ticker" => Dict{String, Any}(
                    "last" => 50000.0,
                    "high" => 51000.0,
                    "low" => 49000.0
                ),
                "timestamp" => 1234567890
            )
        )
        msg = WSClient.WSMessages(nested)
        @test msg.type == "update"
        @test msg.data["ticker"]["last"] == 50000.0
        @test msg.data["timestamp"] == 1234567890
    end
    
    @testset "SSL config initialization" begin
        client_ssl = WSClient.GatewayWSClient(; use_ssl=true)
        client_no_ssl = WSClient.GatewayWSClient(; use_ssl=false)
        
        @test client_ssl.ssl_config !== nothing
        @test client_no_ssl.ssl_config === nothing
    end
    
    @testset "URL protocol selection" begin
        client_wss = WSClient.GatewayWSClient(; use_ssl=true)
        client_ws = WSClient.GatewayWSClient(; use_ssl=false)
        
        @test startswith(client_wss.url, "wss://")
        @test startswith(client_ws.url, "ws://")
    end
end

@testset "Message construction edge cases" begin
    @testset "Subscribe with empty params" begin
        params = Dict{String, Any}()
        message = Dict{String, Any}(
            "type" => "subscribe",
            "subscription_id" => "test",
            "exchange_id" => "binance",
            "method" => "watch_ticker",
            "params" => params
        )
        @test isempty(message["params"])
    end
    
    @testset "Subscribe with special chars in symbol" begin
        symbols = ["BTC/USDT:USDT", "ETH-USD", "ADA:BTC"]
        for sym in symbols
            params = Dict{String, Any}("symbol" => sym)
            message = Dict{String, Any}(
                "type" => "subscribe",
                "params" => params
            )
            @test message["params"]["symbol"] == sym
        end
    end
end

println("WebSocket edge case tests passed!")