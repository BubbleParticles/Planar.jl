using Test
using ExchangeTypes
using Ccxt.CcxtGateway: call_exchange, default_client, ping

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
