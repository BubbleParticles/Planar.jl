# Test Rest module with mocked HTTP (uses real PlanarCore modules so mocks
# land on the shared Rest singleton; a local include() copy diverged types).
using Test
using HTTP
using JSON3
using PlanarCore.Ccxt.CcxtGateway.Rest


mock_get_calls = []
mock_post_calls = []
mock_delete_calls = []

function mock_get(url; kwargs...)
    push!(mock_get_calls, (url, kwargs))
    if url == "https://localhost:8999/ping"
        return HTTP.Response(200, JSON3.write(Dict("result" => "pong", "error" => nothing)))
    elseif url == "https://localhost:8999/admin/exchanges"
        return HTTP.Response(200, JSON3.write(Dict("result" => ["binance"], "error" => nothing)))
    elseif occursin("/status", url) && match(r"/[^/]+/status$", url) !== nothing
        return HTTP.Response(200, JSON3.write(Dict("result" => Dict("exchange_id" => "test"), "error" => nothing)))
    else
        return HTTP.Response(200, JSON3.write(Dict("result" => nothing, "error" => "Not found")))
    end
end

function mock_post(url; kwargs...)
    push!(mock_post_calls, (url, kwargs))
    return HTTP.Response(200, JSON3.write(Dict("result" => "ok", "error" => nothing)))
end

function mock_delete(url; kwargs...)
    push!(mock_delete_calls, (url, kwargs))
    return HTTP.Response(200, JSON3.write(Dict("result" => "deleted", "error" => nothing)))
end

Rest.set_http_get!(mock_get)
Rest.set_http_post!(mock_post)
Rest.set_http_delete!(mock_delete)

# Pre-initialize the gateway so _ensure_gateway_running skips its /ping
# health-check (which would route through the mocked _http_get and add a
# second GET call to api_call endpoints).
Rest._gateway_initialized[] = true

@testset "Rest module with mocked HTTP" begin
    client = Rest.GatewayClient()

    @testset "ping" begin
        empty!(mock_get_calls)
        result = Rest.ping(client)
        @test result == true
        @test length(mock_get_calls) == 1
    end

    @testset "list_exchanges" begin
        empty!(mock_get_calls)
        result = Rest.list_exchanges(client)
        @test result == ["binance"]
        @test length(mock_get_calls) == 1  # only list_exchanges
    end

    @testset "start_exchange" begin
        empty!(mock_post_calls)
        result = Rest.start_exchange(client, "test_exchange")
        @test length(mock_post_calls) == 1
    end

    @testset "stop_exchange" begin
        empty!(mock_delete_calls)
        result = Rest.stop_exchange(client, "test_exchange")
        @test length(mock_delete_calls) == 1
    end
end

Rest.set_http_get!(HTTP.get)
Rest.set_http_post!(HTTP.post)
Rest.set_http_delete!(HTTP.delete)
# Restore the init flag so later suites in the same process perform the real
# gateway health-check instead of inheriting the mock bypass.
Rest._gateway_initialized[] = false

println("Rest module tests with mocked HTTP passed!")