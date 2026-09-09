# Test CcxtGateway types via the real source (no shadow structs).
using Test
using JSON3
using PlanarCore.Ccxt.CcxtGateway.Types: GatewayResponse, parse_response, has_error, get_result
using HTTP

@testset "GatewayResponse constructors" begin
    @test GatewayResponse("test", nothing, nothing).result == "test"
    @test GatewayResponse(nothing, "err", "E001").error == "err"
    r = GatewayResponse(Dict{String,Any}("result" => "x", "error" => nothing, "error_code" => nothing))
    @test get_result(r) == "x"
    e = GatewayResponse(Dict{String,Any}("result" => nothing, "error" => "boom", "error_code" => "E1"))
    @test has_error(e)
    @test_throws ErrorException get_result(e)
end

@testset "JSON3 parsing through real parse_response" begin
    body = JSON3.write(Dict("result" => Dict("symbol" => "BTC/USDT", "last" => 50000.0),
        "error" => nothing, "error_code" => nothing))
    resp = parse_response(HTTP.Response(200, body))
    @test resp.result["symbol"] == "BTC/USDT"
    @test resp.result["last"] == 50000.0
    @test !has_error(resp)
end
