using Test
using Data
const Dates = Data.Misc.TimeTicks.Dates

# ──────────────────────────────────────────────
# ZarrInstance creation
# ──────────────────────────────────────────────
@testset "ZarrInstance" begin
    zi = Data.zinstance()
    @test zi isa ZarrInstance
end

# ──────────────────────────────────────────────
# Module has expected exports
# ──────────────────────────────────────────────
@testset "Exports" begin
    @test isdefined(Data, :Candle)
    @test isdefined(Data, :PairData)
    @test isdefined(Data, :OHLCV_COLUMNS)
    @test isdefined(Data, :OHLCVTuple)
    @test isdefined(Data, :contiguous_ts)
end

# ──────────────────────────────────────────────
# Candle construction
# ──────────────────────────────────────────────
@testset "Candle" begin
    ts = Dates.DateTime(2024, 1, 1)
    c = Candle(timestamp=ts, open=1.0, high=2.0, low=0.5, close=1.5, volume=100.0)
    @test c isa Data.Candle
    @test c.timestamp == ts
    @test c.open == 1.0
    @test c.high == 2.0
    @test c.low == 0.5
    @test c.close == 1.5
    @test c.volume == 100.0
end
