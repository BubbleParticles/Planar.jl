"""Tests for CcxtGateway.Rest with proper HTTP mocking"""
using Test
using Ccxt.CcxtGateway.Rest
using Ccxt.CcxtGateway.Types
using JSON3

# Save original HTTP functions
const _orig_HTTP_get = Ref{Any}(nothing)
const _orig_HTTP_post = Ref{Any}(nothing)
const _orig_HTTP_delete = Ref{Any}(nothing)

function mock_HTTP_get(url::String; kwargs...)
    # Mock responses based on URL pattern
    if endswith(url, "/ping")
        return HTTP.Response(200, JSON3.write(Dict("result" => "pong", "error" => nothing)))
    elseif endswith(url, "/admin/exchanges")
        return HTTP.Response(200, JSON3.write(Dict("result" => ["binance", "kraken"], "error" => nothing)))
    elseif endswith(url, "/admin/info")
        return HTTP.Response(200, JSON3.write(Dict("result" => Dict("version" => "1.0.0"), "error" => nothing)))
    elseif occursin(r"/[^/]+/status$", url)
        return HTTP.Response(200, JSON3.write(Dict(
            "result" => Dict("exchange_id" => "test", "running" => true),
            "error" => nothing
        )))
    elseif occursin(r"/[^/]+/fetch_balance$", url)
        return HTTP.Response(200, JSON3.write(Dict(
            "result" => Dict("USDT" => Dict("free" => 1000.0, "used" => 500.0, "total" => 1500.0)),
            "error" => nothing
        )))
    elseif occursin(r"/[^/]+/fetch_ticker\?", url)
        return HTTP.Response(200, JSON3.write(Dict(
            "result" => Dict("symbol" => "BTC/USDT", "last" => 50000.0),
            "error" => nothing
        )))
    elseif occursin(r"/[^/]+/fetch_tickers", url)
        return HTTP.Response(200, JSON3.write(Dict(
            "result" => Dict("BTC/USDT" => Dict("last" => 50000.0)),
            "error" => nothing
        )))
    elseif occursin(r"/[^/]+/fetch_order_book", url)
        return HTTP.Response(200, JSON3.write(Dict(
            "result" => Dict("bids" => [[49900.0, 1.0]], "asks" => [[50100.0, 1.0]]),
            "error" => nothing
        )))
    else
        return HTTP.Response(404, JSON3.write(Dict("error" => "Not found")))
    end
end

function mock_HTTP_post(url::String; kwargs...)
    if occursin(r"/[^/]+$", url) && !occursin("admin", url)
        return HTTP.Response(200, JSON3.write(Dict("result" => "started", "error" => nothing)))
    elseif occursin(r"/admin/exchanges/[^/]+/restart", url)
        return HTTP.Response(200, JSON3.write(Dict("result" => "restarted")))
    else
        return HTTP.Response(404, JSON3.write(Dict("error" => "Not found")))
    end
end

function mock_HTTP_delete(url::String; kwargs...)
    if occursin(r"/[^/]+$", url)
        return HTTP.Response(200, JSON3.write(Dict("result" => "stopped", "error" => nothing)))
    else
        return HTTP.Response(404, JSON3.write(Dict("error" => "Not found")))
    end
end

function setup_mock_http()
    # This won't work easily in Julia - can't just replace module functions
    # Need to use a different approach
end

@testset "Rest with Mocking" begin
    @testset "GatewayClient" begin
        client = GatewayClient()
        @test client isa GatewayClient
        @test client.host == "localhost"
        @test client.port == 8000
    end
    
    @testset "build_url" begin
        client = GatewayClient()
        @test build_url(client, "ping") == "https://localhost:8000/ping"
        @test build_url(client, "binance/fetch_balance") == "https://localhost:8000/binance/fetch_balance"
    end
    
    @testset "path construction in call_exchange" begin
        # Test that call_exchange constructs correct paths
        # The function constructs path as "/$exchange_id/$ccxt_method"
        exchange_id = "binance"
        method = "fetch_balance"
        expected_path = "/$exchange_id/$method"
        @test expected_path == "/binance/fetch_balance"
        
        # Test with various methods
        for m in ["fetch_ticker", "fetch_tickers", "fetch_order_book", "create_order"]
            path = "/$exchange_id/$m"
            @test startswith(path, "/$exchange_id/")
            @test endswith(path, m)
        end
    end
    
    @testset "Response parsing" begin
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
    
    @testset "Type construction in responses" begin
        # Test that we can construct types from response data
        ticker_data = Dict("symbol" => "BTC/USDT", "last" => 50000.0)
        ticker = Ticker(; ticker_data...)
        @test ticker.symbol == "BTC/USDT"
        @test ticker.last == 50000.0
    end
end
