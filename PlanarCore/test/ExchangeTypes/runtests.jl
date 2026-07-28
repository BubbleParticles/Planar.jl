using Test
using PlanarCore.ExchangeTypes
using PlanarCore.Ccxt.CcxtGateway: call_exchange, default_client, ping, Rest
using PlanarCore.ExchangeTypes.CcxtGateway: HTTP, JSON3

function _mock_get(url; kwargs...)
    if occursin("/has", url)
        HTTP.Response(200, JSON3.write(Dict("result" => Dict("fetchTicker" => true), "error" => nothing, "error_code" => nothing)))
    elseif occursin("/timeframes", url)
        HTTP.Response(200, JSON3.write(Dict("result" => Dict("1m" => nothing), "error" => nothing, "error_code" => nothing)))
    elseif occursin("/fees", url)
        HTTP.Response(200, JSON3.write(Dict("result" => Dict("trading" => Dict()), "error" => nothing, "error_code" => nothing)))
    elseif occursin("/precisionMode", url)
        HTTP.Response(200, JSON3.write(Dict("result" => 2, "error" => nothing, "error_code" => nothing)))
    elseif occursin("/get_propertynames", url)
        HTTP.Response(200, JSON3.write(Dict("result" => ["fetchTicker", "fetchOHLCV"], "error" => nothing, "error_code" => nothing)))
    elseif occursin("/markets", url)
        HTTP.Response(200, JSON3.write(Dict("result" => Dict("BTC/USDT" => Dict("id" => "BTC/USDT", "type" => "spot", "base" => "BTC", "quote" => "USDT")), "error" => nothing, "error_code" => nothing)))
    elseif occursin("/ping", url)
        HTTP.Response(200, JSON3.write(Dict("result" => "pong", "error" => nothing, "error_code" => nothing)))
    elseif occursin("/exchanges/", url)
        HTTP.Response(200, JSON3.write(Dict("result" => Dict("running" => true), "error" => nothing, "error_code" => nothing)))
    else
        error("Unexpected GET: $url")
    end
end

function _mock_post(url; kwargs...)
    if occursin("/fetchOHLCV", url)
        HTTP.Response(200, JSON3.write(Dict("error" => "not supported", "result" => nothing)))
    else
        HTTP.Response(200, JSON3.write(Dict("status" => "success", "result" => Dict("running" => true), "error" => nothing, "error_code" => nothing)))
    end
end
# ──────────────────────────────────────────────
# ExchangeID
# ──────────────────────────────────────────────
@testset "ExchangeID" begin
    eid = ExchangeID(:binance)
    @test eid isa ExchangeID
    @test eid == :binance
    @test string(eid) == "binance"
end

@testset "ExchangeID equality" begin
    @test ExchangeID(:binance) == ExchangeID(:binance)
    @test ExchangeID(:binance) != ExchangeID(:okx)
end

@testset "ExchangeID hashing" begin
    s = Set([ExchangeID(:binance), ExchangeID(:binance), ExchangeID(:okx)])
    @test length(s) == 2
end

# ──────────────────────────────────────────────
# Exchange type
# ──────────────────────────────────────────────
@testset "Exchange type" begin
    exc = Exchange(:test_exchange)
    @test exc isa Exchange
    @test exc.id == ExchangeID(:test_exchange)
    @test exc.name == "test_exchange"
end

@testset "has" begin
    @test has(Exchange(:test), :fetchTicker) isa Bool
end

# ──────────────────────────────────────────────
# exchangeid function
# ──────────────────────────────────────────────
@testset "exchangeid" begin
    @test exchangeid(ExchangeID(:binance)) == ExchangeID(:binance)
    @test exchangeid(:binance) == ExchangeID(:binance)
    @test exchangeid("binance") == ExchangeID(:binance)
end

# ──────────────────────────────────────────────
# eids / exchanges
# ──────────────────────────────────────────────
@testset "eids" begin
    # eids creates a Union type from symbols for dispatch
    u = eids(:binance, :okx)
    @test u isa Union
    @test (ExchangeID{:binance}) <: u
    @test (ExchangeID{:okx}) <: u
    @test !((ExchangeID{:kraken}) <: u)
end

@testset "exchanges" begin
    @test exchanges isa Dict
    @test sb_exchanges isa Dict
end

@testset "_first" begin
    exc = Exchange(:test_first)

    # No methods in has → _first returns nothing
    @test first(exc, :fetchOHLCVWs, :fetchOHLCV) === nothing

    # Inject methods into has dict (const protects reference, not dict contents)
    exc.has[:fetchOHLCVWs] = true
    exc.has[:fetchOHLCV] = true

    # With methods in has, _first should return a closure
    func = first(exc, :fetchOHLCVWs, :fetchOHLCV)
    @test func isa Function

    # Calling the closure without a running gateway should try the first method
    # (fetchOHLCVWs), fail gracefully, fall through to fetchOHLCV, also fail,
    # and return nothing. No error or crash.
    @test func(; symbol="BTC/USDT", limit=100) === nothing
end
