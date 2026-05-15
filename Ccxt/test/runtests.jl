# Test runner for Ccxt - runs all unit tests
# Run with: julia --project=Ccxt test/runtests.jl

# Set flag to prevent tests from running at include-time
const RUN_TESTS_VIA_RUNNER = true

using Test

println("=== Running Ccxt Unit Tests ===")

@testset "CcxtGateway" begin
    @testset "Types" begin
        include("test_types.jl")
    end
    
    @testset "Types edge cases" begin
        include("test_types_edge_cases.jl")
    end
    
    @testset "REST logic" begin
        include("test_rest_logic.jl")
    end
    
    @testset "REST edge cases" begin
        include("test_rest_edge_cases.jl")
    end
    
    @testset "REST mock tests" begin
        include("test_rest_mock.jl")
    end
    
    @testset "WebSocket unit tests" begin
        include("test_websocket.jl")
    end
    
    @testset "WebSocket edge cases" begin
        include("test_websocket_edge_cases.jl")
    end
    
    if get(ENV, "RUN_INTEGRATION_TESTS", "false") == "true"
        @testset "Integration Tests" begin
            include("test_integration.jl")
        end
    end
end

println("\n=== All Unit Tests Passed ===")