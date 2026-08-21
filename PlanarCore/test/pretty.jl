using Test
using PlanarCore
using PlanarCore.Collections
using PlanarCore.Instances
using PlanarCore.Instances.Instruments: AbstractInstrument, parse
using PlanarCore.Instances.Exchanges.ExchangeTypes.OrderedCollections: OrderedSet
using PlanarCore.Instances.Exchanges.ExchangeTypes
using PlanarCore.Instances.Exchanges.ExchangeTypes:
    CcxtExchange, ExchangeID, ExcPrecisionMode
using PlanarCore.OrderTypes
using PlanarCore.Instances.Exchanges: LeverageTier
using PlanarCore.Instances.Data.TimeTicks: TimeFrame, DateTime, Second
using PlanarCore.Instances.Data.DataFrames: DataFrame
using PlanarCore.Instances.DataStructures: SortedDict
using PlanarCore.Misc: DFT
using PlanarCore.Instances.Misc: NoMargin
using PlanarCore.Instances.TimeTicks: DateRange
using PlanarCore.Misc.TimeToLive: TTL

@testset "pretty printing" begin
    # A `show` method must not throw for any core type.
    shows_ok(x) = (io = IOBuffer(); show(io, MIME("text/plain"), x); true)

    @testset "scalar types" begin
        @test shows_ok(ExchangeID(:binanceusdm))
        @test shows_ok(TimeFrame("1m"))
        @test shows_ok(PlanarCore.Misc.Config())
        @test shows_ok(TTL(Second(1)))
        @test shows_ok(NoMargin())
        @test shows_ok(PlanarCore.Misc.Isolated)
        @test shows_ok(PlanarCore.Misc.IsolatedHedged)
        @test shows_ok(PlanarCore.Misc.CrossHedged)
        @test shows_ok(PlanarCore.Misc.NoMargin)
        @test shows_ok(parse(AbstractInstrument, "BTC/USDT"))
        @test shows_ok(parse(PlanarCore.Instruments.Derivatives.Derivative, "BTC/USDT:USDT"))
        @test shows_ok(DateRange(DateTime(2024, 1, 1), DateTime(2024, 2, 1)))
    end

    @testset "exchange, instance & collection" begin
        id = ExchangeID(:test)

        mock_exc = CcxtExchange{typeof(id)}(
            id,
            "test",
            "",
            OrderedSet{String}(["1m"]),
            Dict{String,Dict{String,Any}}(
                "BTC/USDT" => Dict{String,Any}(
                    "id" => "BTC/USDT",
                    "base" => "BTC",
                    "quote" => "USDT",
                    "type" => "spot",
                    "active" => true,
                    "spot" => true,
                    "precision" => Dict{String,Any}("amount" => 8, "price" => 2),
                    "limits" => Dict{String,Any}(
                        "amount" => Dict{String,Any}("min" => 1e-6, "max" => 1e8),
                        "price" => Dict{String,Any}("min" => 0.01, "max" => 1e6),
                        "cost" => Dict{String,Any}("min" => 1.0, "max" => 1e8),
                    ),
                    "taker" => 0.001,
                    "maker" => 0.001,
                ),
            ),
            Set{Symbol}([:spot]),
            Dict{Symbol,Any}(:taker => 0.001, :maker => 0.001),
            Dict{Symbol,Any}(:fetchTicker => true, :fetchOHLCV => true),
            ExcPrecisionMode(2),
            nothing,
            [:fetchTicker, :fetchOHLCV],
            Dict{String,Any}(),
        )
        tf = TimeFrame("1m")
        base_ts = 1704067200000
        df = DataFrame(
            timestamp=[Int64(base_ts + i * 60000) for i in 0:9],
            open=Float64(50000),
            high=Float64(51000),
            low=Float64(49000),
            close=Float64(50500),
            volume=Float64(1000.0),
        )
        a_btc = parse(AbstractInstrument, "BTC/USDT")
        ai_btc = Instances.InstrumentInstance(
            a_btc,
            SortedDict(tf => df),
            mock_exc,
            NoMargin();
            limits=(
                leverage=(; min=1.0, max=1.0),
                amount=(; min=1e-6, max=1e8),
                price=(; min=0.01, max=1e6),
                cost=(; min=1.0, max=1e8),
            ),
            precision=(; amount=8, price=2),
            fees=(; taker=0.001, maker=0.001, min=0.0, max=0.002),
        )
        coll = Collections.InstrumentCollection([ai_btc])
        @test shows_ok(mock_exc)
        @test shows_ok(ai_btc)
        @test shows_ok(coll)
    end

    @testset "trade & leverage tier" begin
        a = parse(AbstractInstrument, "BTC/USDT")
        eid = ExchangeID(:test)
        o = OrderTypes.Order(
            a, eid, OrderTypes.Order{OrderTypes.MarketOrderType{OrderTypes.Buy}}, OrderTypes.Long;
            price=DFT(50000.0), amount=1.0, date=DateTime(2024, 1, 1),
        )
        t = OrderTypes.Trade(
            o; date=DateTime(2024, 1, 1), amount=1.0, price=DFT(50000.0),
            fees=0.01, size=50000.0, lev=1.0, entryprice=DFT(50000.0), fees_base=0.0,
        )
        @test shows_ok(t)
        tier = LeverageTier(1, 0.0, 100.0, 10.0, 0.01, 0.0, 0.0)
        @test shows_ok(tier)
    end
end
