using Test
using ExchangeTypes

@testset "ExchangeTypes" begin

@testset "Module structure" begin
    @testset "All exported names are defined" begin
        expected = [:Exchange, :ExchangeID, :EIDType, :ExcPrecisionMode,
                     :GatewayExchange, :exchange, :exchangeid, :exchanges,
                     :sb_exchanges, :has, :account, :eids]
        for name in expected
            @test isdefined(ExchangeTypes, name)
        end
    end

    @testset "Key internal names are defined" begin
        internal = [:close_exc, :_closeall, :decimal_to_size, :HOOKS,
                    :exchangeIds, :_has, :OptionsDict]
        for name in internal
            @test isdefined(ExchangeTypes, name)
        end
    end

    @testset "GatewayExchange subtypes Exchange" begin
        @test GatewayExchange{ExchangeID{:test}} <: Exchange
    end

    @testset "ExchangeID subtypes" begin
        @test ExchangeID{:test} <: ExchangeID
        @test ExchangeID{:binance} <: ExchangeID
    end

    @testset "EIDType alias" begin
        @test EIDType == Type{<:ExchangeID}
    end

    @testset "ExcPrecisionMode enum values" begin
        @test ExcPrecisionMode(2) == ExchangeTypes.excDecimalPlaces
        @test ExcPrecisionMode(3) == ExchangeTypes.excSignificantDigits
        @test ExcPrecisionMode(4) == ExchangeTypes.excTickSize
    end

    @testset "OptionsDict alias" begin
        @test ExchangeTypes.OptionsDict == Dict{String, Dict{String, Any}}
    end

    @testset "_doinit runs without error" begin
        ExchangeTypes._doinit()
        @test true
    end

    @testset "precompile.jl loads without error" begin
        include("../src/precompile.jl")
        @test true
    end

    @testset "_has with symbol feature (static)" begin
        result = ExchangeTypes._has(:fetchTicker)
        @test result isa Vector{String}
    end

    @testset "exchangeIds is a Vector" begin
        @test ExchangeTypes.exchangeIds isa Vector{Symbol}
    end
end

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

    @testset "Broadcast" begin
        id = ExchangeID{:binance}()
        bc = Base.Broadcast.broadcastable(id)
        @test bc isa Base.RefValue{ExchangeID{:binance}}
    end
end

@testset "GatewayExchange" begin
    @testset "Empty exchange" begin
        e = Exchange()
        @test isempty(e)
        @test nameof(e) == Symbol()
        @test e isa GatewayExchange
    end

    @testset "Exchange from symbol" begin
        e = Exchange(:test_only)
        @test e isa GatewayExchange
        @test e.name == "test_only"
        @test string(e.id) == "test_only"
        @test !ExchangeTypes.isempty(e)
        @test ExchangeTypes.nameof(e) == :test_only
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
        @test ExchangeTypes._has(e, :fetchTicker, :fetchOrderBook) == false
    end

    @testset "has with populated dict" begin
        e = Exchange(:test_exchange)
        push!(e.has, :fetchTicker => true)
        push!(e.has, :fetchBalance => true)
        @test ExchangeTypes.has(e, :fetchTicker) == true
        @test ExchangeTypes.has(e, (:fetchTicker, :fetchBalance)) == true
        @test ExchangeTypes._has(e, :fetchTicker) == true
        @test ExchangeTypes._has(e, :fetchTicker, :fetchOrderBook) == true
        ExchangeTypes.has(e, (:fetchTicker, :nonexistent)) == false
        delete!(e.has, :fetchTicker)
        delete!(e.has, :fetchBalance)
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

    @testset "Standard field access" begin
        e = Exchange(:test_exchange)
        @test e.id isa ExchangeID
        @test e.name == "test_exchange"
        @test e.account == ""
    end

    @testset "Non-field access via gateway" begin
        e = Exchange(:test_exchange)
        try
            # Should call call_exchange on the gateway (will fail without running gateway)
            e.fetchTicker
        catch err
            @test occursin("fetchTicker", string(err)) || occursin("connect", lowercase(string(err)))
        end
    end

    @testset "Empty exchange getproperty" begin
        e = Exchange()
        @test_throws Union{String, ErrorException} ExchangeTypes.getproperty(e, :nonexistent)
    end

    @testset "propertynames" begin
        e = Exchange(:test_exchange)
        names = Base.propertynames(e)
        @test :name in names
        @test :id in names
        @test :has in names
        @test :account in names
    end

    @testset "first on empty has" begin
        e = Exchange(:test_exchange)
        result = ExchangeTypes.first(e, :fetchTicker, :fetchBalance)
        @test result === nothing
    end

    @testset "first with populated has" begin
        e = Exchange(:test_exchange)
        push!(e.has, :fetchTicker => true)
        result = ExchangeTypes.first(e, :fetchTicker, :fetchBalance)
        @test result isa Function
        delete!(e.has, :fetchTicker)
    end

    @testset "first without args" begin
        e = Exchange(:test_exchange)
        result = ExchangeTypes.first(e)
        @test result === nothing
    end

    @testset "close removes from caches" begin
        empty!(ExchangeTypes.exchanges)
        empty!(ExchangeTypes.sb_exchanges)
        e = Exchange(:test_close)
        ExchangeTypes.exchanges[(:test_close, "")] = e
        ExchangeTypes.sb_exchanges[(:test_close, "")] = e
        @test haskey(ExchangeTypes.exchanges, (:test_close, ""))
        @test haskey(ExchangeTypes.sb_exchanges, (:test_close, ""))
        ExchangeTypes.close_exc(e)
        @test !haskey(ExchangeTypes.exchanges, (:test_close, ""))
        @test !haskey(ExchangeTypes.sb_exchanges, (:test_close, ""))
    end

    @testset "close_exc on uncached exchange" begin
        e = Exchange(:test_uncached)
        ExchangeTypes.close_exc(e)
        @test true
    end

    @testset "nameof" begin
        e = Exchange(:test_naming)
        @test ExchangeTypes.nameof(e) == :test_naming
    end

    @testset "timeframes, markets, types, fees fields" begin
        e = Exchange(:test_fields)
        @test isa(e.timeframes, AbstractSet)
        @test isempty(e.timeframes)
        @test e.markets isa Dict
        @test isempty(e.markets)
        @test e.types isa Set
        @test isempty(e.types)
        @test e.fees isa Dict
        @test isempty(e.fees)
    end

    @testset "precision field" begin
        e = Exchange(:test_precision)
        @test e.precision == ExchangeTypes.excTickSize
        e.precision = ExchangeTypes.excDecimalPlaces
        @test e.precision == ExchangeTypes.excDecimalPlaces
    end

    @testset "_trace field" begin
        e = Exchange(:test_trace)
        @test e._trace === nothing
        e._trace = "test trace"
        @test e._trace == "test trace"
    end
end

@testset "Exchange cache" begin
    @testset "Empty initial state" begin
        empty!(ExchangeTypes.exchanges)
        empty!(ExchangeTypes.sb_exchanges)
        @test isempty(ExchangeTypes.exchanges)
        @test isempty(ExchangeTypes.sb_exchanges)
    end

    @testset "add and remove from exchanges dict" begin
        empty!(ExchangeTypes.exchanges)
        e = Exchange(:test_cache)
        ExchangeTypes.exchanges[(:test_cache, "main")] = e
        @test length(ExchangeTypes.exchanges) == 1
        @test ExchangeTypes.exchanges[(:test_cache, "main")] === e
        delete!(ExchangeTypes.exchanges, (:test_cache, "main"))
        @test isempty(ExchangeTypes.exchanges)
    end

    @testset "add and remove from sb_exchanges dict" begin
        empty!(ExchangeTypes.sb_exchanges)
        e = Exchange(:test_sb)
        ExchangeTypes.sb_exchanges[(:test_sb, "sandbox")] = e
        @test length(ExchangeTypes.sb_exchanges) == 1
        delete!(ExchangeTypes.sb_exchanges, (:test_sb, "sandbox"))
        @test isempty(ExchangeTypes.sb_exchanges)
    end

    @testset "closeall with exchanges" begin
        empty!(ExchangeTypes.exchanges)
        empty!(ExchangeTypes.sb_exchanges)
        e1 = Exchange(:test_a)
        e2 = Exchange(:test_b)
        ExchangeTypes.exchanges[(:test_a, "")] = e1
        ExchangeTypes.exchanges[(:test_b, "")] = e2
        ExchangeTypes._closeall()
        @test isempty(ExchangeTypes.exchanges)
        @test isempty(ExchangeTypes.sb_exchanges)
    end

    @testset "closeall with sb_exchanges" begin
        empty!(ExchangeTypes.exchanges)
        empty!(ExchangeTypes.sb_exchanges)
        e = Exchange(:test_sb_close)
        ExchangeTypes.sb_exchanges[(:test_sb_close, "sandbox")] = e
        ExchangeTypes._closeall()
        @test isempty(ExchangeTypes.exchanges)
        @test isempty(ExchangeTypes.sb_exchanges)
    end

    @testset "closeall with both caches" begin
        empty!(ExchangeTypes.exchanges)
        empty!(ExchangeTypes.sb_exchanges)
        e1 = Exchange(:test_both)
        e2 = Exchange(:test_both_sb)
        ExchangeTypes.exchanges[(:test_both, "main")] = e1
        ExchangeTypes.sb_exchanges[(:test_both_sb, "sandbox")] = e2
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
        @test occursin("| 0 markets | 0 timeframes", str)
    end

    @testset "display method" begin
        e = Exchange(:test_exchange)
        ExchangeTypes.Base.display(e)
        @test true
    end

    @testset "display on empty exchange" begin
        e = Exchange()
        str = sprint(show, e)
        @test occursin(":", str)
    end
end

@testset "decimal_to_size" begin
    @testset "Decimal places with integer" begin
        result = ExchangeTypes.decimal_to_size(100, ExchangeTypes.excDecimalPlaces)
        @test result == 100
    end

    @testset "Decimal places with non-integer" begin
        result = ExchangeTypes.decimal_to_size(100.5, ExchangeTypes.excDecimalPlaces)
        @test result == 100.5
    end

    @testset "Significant digits" begin
        result = ExchangeTypes.decimal_to_size(1.2345, ExchangeTypes.excSignificantDigits)
        @test result == 1.2345
    end

    @testset "Tick size" begin
        result = ExchangeTypes.decimal_to_size(0.01, ExchangeTypes.excTickSize)
        @test result == 0.01
    end

    @testset "Default precision mode" begin
        e = Exchange(:test_exchange)
        @test e.precision == ExchangeTypes.excTickSize
    end
end

@testset "HOOKS" begin
    @testset "HOOKS is empty by default" begin
        @test isempty(ExchangeTypes.HOOKS)
    end

    @testset "HOOKS with registered function" begin
        hook_called = Ref(false)
        ExchangeTypes.HOOKS[:test_hook_exchange] = [e -> (hook_called[] = true)]
        e = Exchange(:test_hook_exchange)
        @test hook_called[] == true
        delete!(ExchangeTypes.HOOKS, :test_hook_exchange)
    end
end

end # @testset "ExchangeTypes"
