# Test WebSocket client module
using Test
using JSON3

include("../src/CcxtGateway/websocket.jl")
using .WSClient

@testset "GatewayWSClient construction" begin
    @testset "Default values" begin
        client = GatewayWSClient()
        @test client.host == "localhost"
        @test client.port == 8999
        @test client.url == "wss://localhost:8999/ws"
        @test client.use_ssl == true
        @test client.ssl_config !== nothing
        @test isempty(client.subscriptions)
    end
    
    @testset "Custom host and port" begin
        client = GatewayWSClient(; host="127.0.0.1", port=8080)
        @test client.host == "127.0.0.1"
        @test client.port == 8080
        @test client.url == "wss://127.0.0.1:8080/ws"
    end
    
    @testset "SSL disabled" begin
        client = GatewayWSClient(; use_ssl=false)
        @test client.url == "ws://localhost:8999/ws"
        @test client.ssl_config === nothing
        @test client.use_ssl == false
    end
    
    @testset "Show method" begin
        client = GatewayWSClient()
        str = string(client)
        @test occursin("localhost", str)
        @test occursin("8999", str)
    end
end

@testset "WSMessages struct" begin
    @testset "Full message" begin
        msg_dict = Dict{String, Any}(
            "type" => "update",
            "data" => Dict{String, Any}("price" => 50000.0),
            "subscription_id" => "sub-123",
            "error" => nothing,
            "exchange_id" => "binance",
            "method" => "watch_ticker"
        )
        msg = WSMessages(msg_dict)
        @test msg.type == "update"
        @test msg.data == Dict{String, Any}("price" => 50000.0)
        @test msg.subscription_id == "sub-123"
        @test msg.error === nothing
        @test msg.exchange_id == "binance"
        @test msg.method == "watch_ticker"
    end
    
    @testset "Minimal message" begin
        msg_dict = Dict{String, Any}("type" => "ping")
        msg = WSMessages(msg_dict)
        @test msg.type == "ping"
        @test msg.data === nothing
        @test msg.subscription_id === nothing
        @test msg.error === nothing
        @test msg.exchange_id === nothing
        @test msg.method === nothing
    end
    
    @testset "Error message" begin
        msg_dict = Dict{String, Any}(
            "type" => "error",
            "subscription_id" => "sub-456",
            "error" => "Invalid subscription"
        )
        msg = WSMessages(msg_dict)
        @test msg.type == "error"
        @test msg.error == "Invalid subscription"
        @test msg.subscription_id == "sub-456"
    end
    
    @testset "Subscribed message" begin
        msg_dict = Dict{String, Any}(
            "type" => "subscribed",
            "subscription_id" => "sub-789",
            "exchange_id" => "binance",
            "method" => "watch_trades"
        )
        msg = WSMessages(msg_dict)
        @test msg.type == "subscribed"
        @test msg.subscription_id == "sub-789"
        @test msg.exchange_id == "binance"
        @test msg.method == "watch_trades"
    end
end

@testset "UUID generation" begin
    @testset "UUID format" begin
        id = WSClient.uuid4()
        @test id isa String
        @test length(id) == 36
        @test occursin("-", id)
    end
    
    @testset "UUID uniqueness" begin
        ids = [WSClient.uuid4() for _ in 1:100]
        @test length(unique(ids)) == 100
    end
end

println("WebSocket unit tests passed!")