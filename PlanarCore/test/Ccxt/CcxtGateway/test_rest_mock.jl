# Tests for CcxtGateway.Rest with proper HTTP mocking
using Test
using HTTP
using PlanarCore.Ccxt.CcxtGateway.Rest
using PlanarCore.Ccxt.CcxtGateway.Types
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
    set_http_get!(mock_HTTP_get)
    set_http_post!(mock_HTTP_post)
    set_http_delete!(mock_HTTP_delete)
end

@testset "Rest with Mocking" begin
    @testset "GatewayClient" begin
        client = GatewayClient()
        @test client isa GatewayClient
        @test client.host == "localhost"
        @test client.port == 8999
    end

    @testset "build_url" begin
        client = GatewayClient()
        @test build_url(client, "ping") == "https://localhost:8999/ping"
        @test build_url(client, "binance/fetch_balance") == "https://localhost:8999/binance/fetch_balance"
        custom = GatewayClient(; port=8000)
        @test build_url(custom, "ping") == "https://localhost:8000/ping"
    end
    @testset "call_exchange through mocked HTTP" begin
        prev_init = Rest._gateway_initialized[]
        prev_get = Rest._http_get[]
        prev_post = Rest._http_post[]
        try
            Rest._gateway_initialized[] = true
            setup_mock_http()
            client = GatewayClient()
            @test ping(client)
            bal = call_exchange(client, "binance", "fetch_balance")
            @test bal["USDT"]["total"] == 1500.0
        finally
            Rest._gateway_initialized[] = prev_init
            set_http_get!(prev_get)
            set_http_post!(prev_post)
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

    @testset "Type construction in responses" begin
        # Round-trip a ticker-like payload through the real parse path.
        ticker_data = Dict("symbol" => "BTC/USDT", "last" => 50000.0)
        resp = HTTP.Response(200, JSON3.write(Dict(
            "result" => ticker_data, "error" => nothing, "error_code" => nothing)))
        @test get_result(Rest.check_response(resp))["last"] == 50000.0
    end
end
