# Test Rest module with mocked HTTP
# Run with: julia --project=Ccxt -e 'include("test/test_rest_mock.jl")'

using Test
using HTTP
using JSON3

if !isdefined(Main, :RUN_TESTS_VIA_RUNNER)
    using Ccxt
    using .CcxtGateway.Rest

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

    @testset "Rest module with mocked HTTP" begin
        client = Rest.GatewayClient()

        @testset "ping" begin
            empty!(mock_get_calls)
            result = ping(client)
            @test result == true
            @test length(mock_get_calls) == 1
        end

        @testset "list_exchanges" begin
            empty!(mock_get_calls)
            result = list_exchanges(client)
            @test result == ["binance"]
            @test length(mock_get_calls) == 1
        end

        @testset "start_exchange" begin
            empty!(mock_post_calls)
            result = start_exchange(client, "test_exchange")
            @test result == "ok"
            @test length(mock_post_calls) == 1
        end

        @testset "stop_exchange" begin
            empty!(mock_delete_calls)
            result = stop_exchange(client, "test_exchange")
            @test result == "deleted"
            @test length(mock_delete_calls) == 1
        end
    end

    Rest.set_http_get!(HTTP.get)
    Rest.set_http_post!(HTTP.post)
    Rest.set_http_delete!(HTTP.delete)

    println("Rest module tests with mocked HTTP passed!")
end