# Test edge cases for CcxtGateway types and REST module
using Test
using JSON3

include("../src/CcxtGateway/types.jl")
using .Types

@testset "GatewayResponse edge cases" begin
    @testset "Empty dict" begin
        resp = Types.GatewayResponse(Dict{String, Any}())
        @test resp.result isa Dict
        @test length(resp.result) == 0
        @test resp.error === nothing
    end
    
    @testset "Nested dict result" begin
        nested = Dict("level1" => Dict("level2" => "value"))
        resp = Types.GatewayResponse(nested, nothing, nothing)
        @test resp.result["level1"]["level2"] == "value"
    end
    
    @testset "Array result" begin
        arr = [1, 2, 3]
        resp = Types.GatewayResponse(arr, nothing, nothing)
        @test resp.result == [1, 2, 3]
    end
    
    @testset "String result" begin
        resp = Types.GatewayResponse("simple string", nothing, nothing)
        @test resp.result == "simple string"
    end
    
    @testset "Number result" begin
        resp = Types.GatewayResponse(42.5, nothing, nothing)
        @test resp.result == 42.5
    end
    
    @testset "Boolean result" begin
        resp = Types.GatewayResponse(true, nothing, nothing)
        @test resp.result === true
    end
    
    @testset "Error with null values" begin
        resp = Types.GatewayResponse(nothing, "Error message", nothing)
        @test Types.has_error(resp)
        @test resp.error == "Error message"
    end
    
    @testset "Only error_code" begin
        resp = Types.GatewayResponse(nothing, nothing, "ERR_001")
        @test Types.has_error(resp)
        @test resp.error_code == "ERR_001"
    end
    
    @testset "Both error and error_code" begin
        resp = Types.GatewayResponse(nothing, "Error message", "ERR_001")
        @test Types.has_error(resp)
        @test resp.error == "Error message"
        @test resp.error_code == "ERR_001"
    end
    
    @testset "Ping response format" begin
        body = Dict("status" => "pong")
        resp = Types.GatewayResponse(body)
        @test resp.result == "pong"
        @test resp.error === nothing
    end
    
    @testset "Result wrapper format" begin
        body = Dict("result" => Dict("price" => 100.0), "error" => nothing)
        resp = Types.GatewayResponse(body)
        @test resp.result["price"] == 100.0
    end
    
    @testset "Direct response format (no result wrapper)" begin
        body = Dict("symbol" => "BTC/USDT", "last" => 50000.0)
        resp = Types.GatewayResponse(body)
        @test resp.result["symbol"] == "BTC/USDT"
        @test resp.result["last"] == 50000.0
    end
end

@testset "has_error edge cases" begin
    @testset "No error fields" begin
        resp = Types.GatewayResponse(Dict("key" => "value"), nothing, nothing)
        @test !Types.has_error(resp)
    end
    
    @testset "Empty string error" begin
        resp = Types.GatewayResponse(nothing, "", nothing)
        @test Types.has_error(resp)
    end
    
    @testset "Empty string error_code" begin
        resp = Types.GatewayResponse(nothing, nothing, "")
        @test Types.has_error(resp)
    end
    
    @testset "Null in both" begin
        resp = Types.GatewayResponse(nothing, nothing, nothing)
        @test !Types.has_error(resp)
    end
end

@testset "get_result edge cases" begin
    @testset "Normal result" begin
        resp = Types.GatewayResponse("test result", nothing, nothing)
        @test Types.get_result(resp) == "test result"
    end
    
    @testset "Error throws" begin
        resp = Types.GatewayResponse(nothing, "Something went wrong", nothing)
        @test_throws ErrorException Types.get_result(resp)
    end
    
    @testset "Error with code throws" begin
        resp = Types.GatewayResponse(nothing, "Error", "ERR_001")
        @test_throws ErrorException Types.get_result(resp)
    end
end

println("Edge case tests for types.jl passed!")