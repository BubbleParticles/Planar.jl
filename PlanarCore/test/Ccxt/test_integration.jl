# Integration tests for CcxtGateway REST client
# These tests require the ccxt-gateway to be running
using Test
using HTTP
using JSON3
using PlanarCore
using PlanarCore.Ccxt.CcxtGateway: GatewayClient, Rest, ping, list_exchanges, server_info, memory_usage

function run_integration_tests()
    gateway_url = get(ENV, "CCXT_GATEWAY_URL", "https://localhost:8999")
    println("Testing against gateway at: $gateway_url")

    client = GatewayClient(;
        host="localhost",
        port=8999,
        use_ssl=startswith(gateway_url, "https")
    )

    @testset "REST Integration Tests" begin

        @testset "Ping" begin
            result = ping(client)
            @test result === true
        end

        @testset "List exchanges (empty initially)" begin
            result = list_exchanges(client)
            @test result isa Vector
        end

        @testset "Server info" begin
            result = server_info(client)
            @test result isa Dict
        end

        @testset "Memory usage" begin
            result = memory_usage(client)
            @test result isa Dict
        end

    end

    println("Integration tests completed!")
end
