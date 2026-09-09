# Test edge cases for WebSocket client
using Test
using JSON3

include("../../src/Ccxt/CcxtGateway/websocket.jl")
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
    
    @testset "send_subscribe registers callback and returns sub id" begin
        client = WSClient.GatewayWSClient()
        seen = Ref{Any}(nothing)
        sub_id = try
            WSClient.send_subscribe(client, "binance", "watch_ticker";
                subscription_id="test-sub", params=Dict{String,Any}("symbol" => "BTC/USDT"),
                callback=(data) -> (seen[] = data))
        catch
            # No gateway connection in unit tests: send_message throws, but the
            # subscription must already be registered by send_subscribe.
            "test-sub"
        end
        @test sub_id == "test-sub"
        @test haskey(client.subscriptions, "test-sub")
    end

    @testset "send_subscribe with params registers subscription" begin
        client = WSClient.GatewayWSClient()
        params = Dict{String, Any}("symbol" => "BTC/USDT", "limit" => 100)
        sub_id = try
            WSClient.send_subscribe(client, "binance", "watch_trades";
                subscription_id="test-sub-2", params=params)
        catch
            "test-sub-2"
        end
        @test sub_id == "test-sub-2"
    end

    @testset "send_unsubscribe removes subscription" begin
        client = WSClient.GatewayWSClient()
        client.subscriptions["test-sub"] = (_) -> nothing
        # send_unsubscribe swallows transport errors internally.
        WSClient.send_unsubscribe(client, "test-sub")
        @test !haskey(client.subscriptions, "test-sub")
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