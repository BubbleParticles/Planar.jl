module StrategyStatsTests

using Test
using StrategyStats
using StrategyStats: diffn, momentum, slopetoangle, mlr_slope, slopeangle, fltsummary, filterminmax, is_slopebetween
using StrategyStats: up_successrate, down_successrate, is_peaked, is_bottomed, is_uptrend
using StrategyStats: find_bottomed, find_peaked
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

    @testset "find_bottomed / find_peaked" begin
        df = test_ohlcv(100)
        pd1 = PairData(name="BTC/USDT", tf="1m", data=df, z=nothing)
        pd2 = PairData(name="ETH/USDT", tf="1m", data=df, z=nothing)
        pairs_vec = [pd1, pd2]
        pairs_dict = Dict("BTC/USDT" => pd1, "ETH/USDT" => pd2)

        bottomed_vec = find_bottomed(pairs_vec; bb_thresh=0.05, up_thresh=0.05, n=12)
        @test bottomed_vec isa Dict

        bottomed_dict = find_bottomed(pairs_dict; bb_thresh=0.05, up_thresh=0.05, n=12)
        @test bottomed_dict isa Dict

        peaked_vec = find_peaked(pairs_vec; bb_thresh=-0.05, up_thresh=0.05, n=12)
        @test peaked_vec isa Dict

        peaked_dict = find_peaked(pairs_dict; bb_thresh=-0.05, up_thresh=0.05, n=12)
        @test peaked_dict isa Dict
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

        # custom x vector
        x_custom = [0.0, 1.0, 2.0, 3.0, 4.0]
        s2 = mlr_slope(y; n=3, x=x_custom)
        @test s2[3] ≈ 1.0
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

    @testset "slopeangle with insufficient data" begin
        arr = [1.0, 2.0]  # only 2 elements, n=10
        result = slopeangle(arr; n=10)
        @test isequal(result, [missing])
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

        pd_vec = PairData[PairData(name="BTC/USDT", tf="1m", data=test_ohlcv(10), z=nothing),
                          PairData(name="ETH/USDT", tf="1m", data=test_ohlcv(10), z=nothing)]
        result2 = fltsummary(pd_vec)
        @test result2 isa Vector
        @test result2[1] == "BTC/USDT"
    end

    @testset "filterminmax" begin
        df = test_ohlcv(50)
        pd = PairData(name="BTC/USDT", tf="1m", data=df, z=nothing)
        pairs_dict = Dict("BTC/USDT" => pd)
        pred = x -> slopeangle(x; n=10)[end]
        result = filterminmax(pred, pairs_dict, -90.0, 90.0)
        @test result isa Vector
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
        X = [1.0 5.0; 2.0 6.0; 3.0 7.0; 4.0 8.0]
        dX = StrategyStats.diffn(X; n=1)
        @test size(dX) == size(X)
        @test isnan(dX[1, 1])
        @test dX[2, 1] ≈ 1.0
        @test dX[3, 1] ≈ 1.0
        @test dX[4, 1] ≈ 1.0
        @test isnan(dX[1, 2])
        @test dX[2, 2] ≈ 1.0
    end

    @testset "diffn edge cases" begin
        # n=1 with 2-element vector
        x2 = [1.0, 3.0]
        dx2 = diffn(x2; n=1)
        @test isnan(dx2[1])
        @test dx2[2] ≈ 2.0

        # n > length
        @test_throws AssertionError diffn([1.0, 2.0]; n=5)
    end

    @testset "momentum edge cases" begin
        x = Float64[5, 7, 10, 6, 3]
        m = momentum(x; n=2)
        @test isnan(m[1])
        @test isnan(m[2])
        @test m[3] ≈ 5.0
        @test m[4] ≈ -1.0
        @test m[5] ≈ -7.0
    end

    @testset "queries.jl functions" begin
        df = test_ohlcv(100)
        pd1 = PairData(name="BTC/USDT", tf="1m", data=df, z=nothing)
        pd2 = PairData(name="ETH/USDT", tf="1m", data=df, z=nothing)
        mrkts = Dict("BTC/USDT" => pd1, "ETH/USDT" => pd2)

        @testset "average_roc" begin
            result = StrategyStats.Query.average_roc(mrkts)
            @test result isa DataFrame
            @test hasproperty(result, :positive)
            @test hasproperty(result, :negative)
            @test hasproperty(result, :ratio)
        end

        @testset "cbot / cpek" begin
            hs = DataFrame(pair=["BTC/USDT", "ETH/USDT"], score_sum=[1.0, 2.0])
            result_cbot = StrategyStats.Query.cbot(hs, mrkts; n=30:-3:15, min_n=1)
            @test result_cbot isa DataFrame

            result_cpek = StrategyStats.Query.cpek(hs, mrkts; n=30:-3:15, min_n=1)
            @test result_cpek isa DataFrame
        end
    end
    @testset "slopefilter parameter name" begin
        # Verify slopefilter passes correct keyword to slopeangle
        # The kwarg "window" in slopefilter should be passed as "n" to slopeangle
        @test hasmethod(StrategyStats.slopefilter, Tuple{AbstractDict})
        # Can't call slopefilter without exchange, but verify the dict dispatch exists
    end
end

end
