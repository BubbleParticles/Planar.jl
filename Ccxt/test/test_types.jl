# Test CcxtGateway types (minimal, no doc strings)
using Test
using JSON3

include("../src/CcxtGateway/types.jl")
using .Types

@testset "GatewayResponse" begin
    resp = GatewayResponse(nothing, nothing, nothing)
    @test resp.result === nothing
    @test resp.error === nothing
    @test resp.error_code === nothing
    
    resp2 = GatewayResponse(Dict("key" => "value"), nothing, nothing)
    @test resp2.result["key"] == "value"
    
    resp3 = GatewayResponse(nothing, "error message", "E001")
    @test resp3.error == "error message"
    @test resp3.error_code == "E001"
end

@testset "parse_response" begin
    json_body = JSON3.write(Dict("result" => Dict("BTC/USDT" => Dict("last" => 50000.0)),
                                "error" => nothing, "error_code" => nothing))
    body_dict = JSON3.parse(json_body)
    @test haskey(body_dict, "result")
    
    ping_body = JSON3.write(Dict("status" => "pong"))
    body_dict2 = JSON3.parse(ping_body)
    @test body_dict2["status"] == "pong"
end

@testset "has_error" begin
    resp_ok = GatewayResponse(Dict(), nothing, nothing)
    @test !has_error(resp_ok)
    
    resp_err = GatewayResponse(nothing, "err", "E001")
    @test has_error(resp_err)
    
    resp_err2 = GatewayResponse(nothing, nothing, "E002")
    @test has_error(resp_err2)
end

println("Types tests passed!")
