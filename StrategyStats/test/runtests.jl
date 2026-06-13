module StrategyStatsTests

using Test
using StrategyStats
using StrategyStats: diffn, momentum, slopetoangle, mlr_slope, slopeangle, fltsummary, filterminmax, is_slopebetween
using StrategyStats: up_successrate, down_successrate, is_peaked, is_bottomed, is_uptrend
using Data: PairData
using Data.DataFrames: DataFrame

const Dates = StrategyStats.Misc.TimeTicks.Dates

function test_ohlcv(n=100)
    ts = Dates.DateTime(2024,1,1):Dates.Day(1):Dates.DateTime(2024,1,1)+Dates.Day(n-1)
    DataFrame(
        timestamp=collect(ts),
        open=100.0 .+ cumsum(randn(n)),
        high=102.0 .+ cumsum(randn(n)),
        low=98.0 .+ cumsum(randn(n)),
        close=100.0 .+ cumsum(randn(n)),
        volume=rand(n) .* 1000,
    )
end

@testset "StrategyStats" begin
    @testset "slopetoangle" begin
        @test slopetoangle(0.0) == 0.0
        @test slopetoangle(1.0) ≈ 45.0
        @test slopetoangle(-1.0) ≈ -45.0
        @test slopetoangle(Inf) ≈ 90.0
        @test slopetoangle(-Inf) ≈ -90.0
    end

    @testset "diffn" begin
        x = [1.0, 3.0, 6.0, 10.0]
        dx = diffn(x; n=1)
        @test dx[1] === NaN
        @test dx[2] ≈ 2.0
        @test dx[3] ≈ 3.0
        @test dx[4] ≈ 4.0

        dx2 = diffn(x; n=2)
        @test dx2[1] === NaN
        @test dx2[2] === NaN
        @test dx2[3] ≈ 5.0
        @test dx2[4] ≈ 7.0
    end

    @testset "momentum" begin
        x = [10.0, 12.0, 15.0, 11.0]
        m = momentum(x; n=1)
        @test m[1] === NaN
        @test m[2] ≈ 2.0
        @test m[3] ≈ 3.0
        @test m[4] ≈ -4.0
    end

    @testset "mlr_slope" begin
        y = [1.0, 2.0, 3.0, 4.0, 5.0]
        s = mlr_slope(y; n=3)
        @test s[1] === NaN
        @test s[2] === NaN
        @test s[3] ≈ 1.0
    end

    @testset "slopeangle on array" begin
        arr = [1.0, 2.0, 3.0, 4.0, 5.0]
        angles = slopeangle(arr; n=3)
        @test length(angles) == 5
        @test isnan(angles[1])
        @test isnan(angles[2])
        @test angles[3] isa Float64
    end

    @testset "slopeangle on DataFrame" begin
        df = test_ohlcv(50)
        angles = slopeangle(df; n=20)
        @test length(angles) == 50
        @test all(x -> isnan(x) || x isa Float64, angles)
    end

    @testset "is_slopebetween" begin
        df = test_ohlcv(50)
        @test is_slopebetween(df; mn=-90, mx=90, n=10) isa Bool
    end

    @testset "fltsummary" begin
        pd = PairData(name="BTC/USDT", tf="1m", data=test_ohlcv(10), z=nothing)
        input = Tuple{AbstractFloat,PairData}[(1.5, pd)]
        result = fltsummary(input)
        @test result isa Vector
        @test result[1] == (1.5, "BTC/USDT")
    end

    @testset "up_successrate / down_successrate" begin
        df = test_ohlcv(50)
        df[!, :signal] = rand([0.0, 1.0], 50)
        rate = up_successrate(df, :signal; threshold=0.01)
        @test rate isa Int

        rate_down = down_successrate(df, :signal; threshold=0.01)
        @test rate_down isa Int
    end

    @testset "is_peaked / is_bottomed / is_uptrend" begin
        df = test_ohlcv(100)
        @test is_peaked(df; thresh=0.05, n=26) isa Bool
        @test is_bottomed(df; thresh=0.05, n=26) isa Bool
        @test is_uptrend(df; thresh=0.05, n=26) isa Bool
    end

    @testset "diffn matrix" begin
        X = [1.0 5.0; 2.0 6.0; 3.0 7.0; 4.0 8.0]'
        dX = StrategyStats.diffn(X; n=1)
        @test size(dX) == size(X)
    end
end

end
