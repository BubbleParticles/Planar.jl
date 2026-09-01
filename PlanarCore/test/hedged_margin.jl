using Test
using PlanarCore.Instances
using PlanarCore.Instances.Exchanges.ExchangeTypes
using PlanarCore.Instances.Exchanges.ExchangeTypes: CcxtExchange, ExchangeID, ExcPrecisionMode
using PlanarCore.Instances.Exchanges.ExchangeTypes.OrderedCollections: OrderedSet
using PlanarCore.Instances.Data.TimeTicks: TimeFrame
using PlanarCore.Instances.Data.DataFrames: DataFrame
using PlanarCore.Instances.DataStructures: SortedDict
using PlanarCore.Instances.Instruments.Derivatives: Derivative, parse
using PlanarCore.Misc: IsolatedHedged, CrossHedged, Isolated, Cross, IsolatedMargin, CrossMargin, Hedged, NotHedged, DFT
using PlanarCore.Instances: Long, Short, Position, marginmode, ishedged, isopen, position, PositionOpen, PositionClose

# Minimal mock exchange
function _make_exchange(name::Symbol)
    id = ExchangeID{name}()
    CcxtExchange{typeof(id)}(
        id,
        string(name),
        "",
        OrderedSet{String}(["1m"]),
        Dict{String,Dict{String,Any}}(
            "BTC/USDT" => Dict{String,Any}(
                "id" => "BTC/USDT", "base" => "BTC", "quote" => "USDT",
                "type" => "spot", "active" => true, "spot" => true,
                "precision" => Dict{String,Any}("amount" => 8, "price" => 2),
                "limits" => Dict{String,Any}(
                    "amount" => Dict{String,Any}("min" => 1e-6, "max" => 1e8),
                    "price" => Dict{String,Any}("min" => 0.01, "max" => 1e6),
                    "cost" => Dict{String,Any}("min" => 1.0, "max" => 1e8),
                ),
                "taker" => 0.001, "maker" => 0.001,
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
end

const mock_exc = _make_exchange(:test)

function _make_instance(sym::String, price::Float64, margin)
    tf = TimeFrame("1m")
    base_ts = 1704067200000
    df = DataFrame(
        timestamp = [Int64(base_ts + i * 60000) for i in 0:9],
        open = Float64(price), high = Float64(price + price * 0.02),
        low = Float64(price - price * 0.02), close = Float64(price + price * 0.01),
        volume = Float64(1000.0),
    )
    da = parse(Derivative, sym)
    Instances.InstrumentInstance(
        da, SortedDict(tf => df), mock_exc, margin;
        limits=(; leverage=(; min=1.0, max=1.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8)),
        precision=(; amount=8, price=2),
        fees=(; taker=0.001, maker=0.001, min=0.0, max=0.002),
    )
end

@testset "Hedged margin mode" begin
    @testset "IsolatedHedged instance constructs with both positions" begin
        ii = _make_instance("BTC/USDT:USDT", 50000.0, IsolatedHedged())
        @test marginmode(ii) isa IsolatedMargin{Hedged}
        @test ishedged(ii) == true
        # Both long and short positions must be constructed (distinct Options)
        longpos = position(ii, Long())
        shortpos = position(ii, Short())
        @test longpos !== shortpos
        @test longpos isa Union{Nothing, Position}
        @test shortpos isa Union{Nothing, Position}
        # Initially neither is open (no trades yet)
        @test !isopen(ii, Long())
        @test !isopen(ii, Short())
    end

    @testset "CrossHedged instance constructs with both positions" begin
        ii = _make_instance("BTC/USDT:USDT", 50000.0, CrossHedged())
        @test marginmode(ii) isa CrossMargin{Hedged}
        @test ishedged(ii) == true
        longpos = position(ii, Long())
        shortpos = position(ii, Short())
        @test longpos !== shortpos
        @test longpos isa Union{Nothing, Position}
        @test shortpos isa Union{Nothing, Position}
    end

    @testset "Isolated (non-hedged) still works" begin
        ii = _make_instance("BTC/USDT:USDT", 50000.0, Isolated())
        @test marginmode(ii) isa IsolatedMargin{NotHedged}
        @test ishedged(ii) == false
        @test position(ii, Long()) isa Union{Nothing, Position}
        @test position(ii, Short()) isa Union{Nothing, Position}
    end

    @testset "Cross (non-hedged) still works" begin
        ii = _make_instance("BTC/USDT:USDT", 50000.0, Cross())
        @test marginmode(ii) isa CrossMargin{NotHedged}
        @test ishedged(ii) == false
    end

    @testset "iszero/isopen per-side in hedged mode" begin
        ii = _make_instance("BTC/USDT:USDT", 50000.0, IsolatedHedged())
        # Initially both sides are zero and not open
        @test !isopen(ii, Long())
        @test !isopen(ii, Short())
        @test Base.iszero(ii)
        @test Base.iszero(ii, Long())
        @test Base.iszero(ii, Short())

        # Open and fund the Long position
        Instances.cash!(ii, DFT(1.0), Long())
        Instances.status!(ii, Long(), PositionOpen())
        @test isopen(ii, Long())
        @test !isopen(ii, Short())
        # ii is not zero because Long has cash
        @test !Base.iszero(ii)
        @test !Base.iszero(ii, Long())
        @test Base.iszero(ii, Short())

        # Reset Long — cash should be zeroed by reset!
        Instances.reset!(ii, Long())
        @test !isopen(ii, Long())
        @test Base.iszero(ii, Long())
        @test Base.iszero(ii)
    end

    @testset "reset! only affects the specified side in hedged mode" begin
        ii = _make_instance("BTC/USDT:USDT", 50000.0, CrossHedged())
        # Open and fund both sides
        Instances.cash!(ii, DFT(1.0), Long())
        Instances.status!(ii, Long(), PositionOpen())
        Instances.cash!(ii, DFT(2.0), Short())
        Instances.status!(ii, Short(), PositionOpen())
        @test isopen(ii, Long())
        @test isopen(ii, Short())
        @test !Base.iszero(ii)

        # Reset only Long — Short should remain open with cash
        Instances.reset!(ii, Long())
        @test !isopen(ii, Long())
        @test isopen(ii, Short())
        @test !Base.iszero(ii)         # Short still has cash
        @test Base.iszero(ii, Long())  # Long is reset
        @test !Base.iszero(ii, Short()) # Short still active

        # Reset Short too — now both sides zero
        Instances.reset!(ii, Short())
        @test !isopen(ii, Long())
        @test !isopen(ii, Short())
        @test Base.iszero(ii)
    end
end
