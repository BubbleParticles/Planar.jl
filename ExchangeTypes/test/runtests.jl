using Test
using ExchangeTypes

@testset "ExchangeTypes" begin

@testset "ExchangeID" begin
    @testset "Parametric creation" begin
        id = ExchangeID{:test_exchange}()
        @test id isa ExchangeID{:test_exchange}
        @test id isa ExchangeID
        @test nameof(id) == :test_exchange
        @test Symbol(id) == :test_exchange
        @test string(id) == "test_exchange"
        @test convert(Symbol, id) == :test_exchange
        @test convert(String, id) == "test_exchange"
    end

    @testset "Empty exchange ID" begin
        id = ExchangeID()
        @test nameof(id) == Symbol()
    end

    @testset "Equality with symbol" begin
        id = ExchangeID{:binance}()
        @test id == :binance
        @test !(id == :coinbase)
    end

    @testset "exchangeid helper" begin
        id1 = ExchangeID{:kraken}()
        @test id1 isa ExchangeID
        @test nameof(id1) == :kraken

        id2 = exchangeid(id1)
        @test id2 === id1
    end

    @testset "eids helper" begin
        u = eids(:binance, :coinbase)
        @test ExchangeID{:binance} <: u
        @test ExchangeID{:coinbase} <: u
    end

    @testset "Display" begin
        id = ExchangeID{:bybit}()
        str = sprint(show, id)
        @test occursin("bybit", str)
        @test occursin("ExchangeID", str)
    end
end

@testset "GatewayExchange (without gateway)" begin
    @testset "Empty exchange" begin
        e = Exchange()
        @test isempty(e)
        @test nameof(e) == Symbol()
    end

    @testset "Exchange from symbol" begin
        e = Exchange(:test_only)
        @test e isa GatewayExchange
        @test e.name == "test_only"
        @test string(e.id) == "test_only"
        @test !ExchangeTypes.isempty(e)
    end

    @testset "Exchange from string" begin
        e = Exchange("test_exchange")
        @test e isa GatewayExchange
        @test e.name == "test_exchange"
    end

    @testset "has function" begin
        e = Exchange(:test_exchange)
        @test ExchangeTypes.has(e, :nonexistent_feature) == false
        @test ExchangeTypes.has(e, (:nonexistent1, :nonexistent2)) == false
        @test ExchangeTypes._has(e, :fetchTicker) == false
    end

    @testset "Exchange properties" begin
        e = Exchange(:test_exchange; account="test_account")
        @test account(e) == "test_account"
        @test exchangeid(e) == e.id
        @test exchange(e) === e
    end

    @testset "Hash and equality" begin
        e1 = Exchange(:test_exchange)
        e2 = Exchange(:test_exchange)
        @test hash(e1) == hash(e2)
        @test hash(e1) == hash(e1.id)
    end

    @testset "Property access" begin
        e = Exchange(:test_exchange)
        @test e.id isa ExchangeID
        @test e.name == "test_exchange"
        @test e.account == ""
    end
end

@testset "CcxtExchange" begin
    @testset "CcxtExchange type exists" begin
        @test isdefined(ExchangeTypes, :CcxtExchange)
    end

    @testset "CcxtExchange creation without Python" begin
        @test_throws ErrorException Exchange(nothing, nothing, "")
    end
end

@testset "Exchange cache" begin
    @testset "Empty initial state" begin
        empty!(ExchangeTypes.exchanges)
        empty!(ExchangeTypes.sb_exchanges)
        @test isempty(ExchangeTypes.exchanges)
        @test isempty(ExchangeTypes.sb_exchanges)
    end

    @testset "closeall on empty" begin
        empty!(ExchangeTypes.exchanges)
        empty!(ExchangeTypes.sb_exchanges)
        ExchangeTypes._closeall()
        @test isempty(ExchangeTypes.exchanges)
        @test isempty(ExchangeTypes.sb_exchanges)
    end
end

@testset "Exchange display" begin
    @testset "show method" begin
        e = Exchange(:test_exchange)
        str = sprint(show, e)
        @test occursin("test_exchange", str)
    end

    @testset "print method" begin
        e = Exchange(:test_exchange)
        str = sprint(print, e)
        @test occursin("Exchange:", str)
    end
end

end # @testset "ExchangeTypes"
