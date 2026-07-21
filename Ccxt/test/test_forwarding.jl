"""Correct test for CcxtGateway - tests forwarding behavior"""
using Test
using JSON3

# Include the actual types.jl
include("../src/CcxtGateway/types.jl")

@testset "CcxtGateway.Types - Minimal (correct approach)" begin
    @testset "GatewayResponse" begin
        # This is the only type CcxtGateway needs
        # It parses the gateway's response wrapper: {result: ..., error: ...}
        
        resp = GatewayResponse(type="", id=nothing, data=Dict("key" => "value"), 
                               error=nothing, error_code=nothing)
        @test resp.data["key"] == "value"
        @test resp.error === nothing
        
        resp2 = GatewayResponse(type="", id=nothing, data=nothing, 
                                error="err", error_code="E001")
        @test resp2.data === nothing
        @test resp2.error == "err"
    end
    
    @testset "parse_response" begin
        using HTTP
        
        # Simulate a gateway response
        json_body = JSON3.write(Dict("result" => Dict("BTC/USDT" => Dict("last" => 50000.0)),
                                    "error" => nothing, "error_code" => nothing))
        resp = HTTP.Response(200, json_body)
        
        parsed = parse_response(resp)
        @test parsed.data !== nothing
        @test parsed.error === nothing
    end
    
    @testset "has_error" begin
        resp_ok = GatewayResponse(type="", id=nothing, data=Dict(), error=nothing, error_code=nothing)
        @test !has_error(resp_ok)
        
        resp_err = GatewayResponse(type="", id=nothing, data=nothing, error="err", error_code="E001")
        @test has_error(resp_err)
    end
    
    @testset "get_result" begin
        # The downstream package uses this to get the raw data
        resp = GatewayResponse(type="", id=nothing, 
                               data=Dict("result" => Dict("last" => 50000.0)),
                               error=nothing, error_code=nothing)
        result = get_result(resp)
        @test result["result"]["last"] == 50000.0
    end
end

println("\nCorrect approach: CcxtGateway just forwards JSON!")
println("Downstream packages define their own types (Ticker, Order, etc.)")
println("and parse the JSON result into those types.")
