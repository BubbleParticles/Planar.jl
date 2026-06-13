using Test
using Processing
using Data
using Statistics: mean, std
const DF = Data.DataFrames
const TimeFrame = Processing.Misc.TimeTicks.TimeFrame
const Dates = Processing.Misc.TimeTicks.Dates

# ──────────────────────────────────────────────
# upsample (ported from PlanarDev/test/test_processing.jl)
# ──────────────────────────────────────────────
# ──────────────────────────────────────────────
# isleftadj / isrightadj / isadjacent
# ──────────────────────────────────────────────
@testset "Processing.adjacency" begin
    tf = TimeFrame(Dates.Minute(5))
    dt1 = Dates.DateTime(2024,1,1,0,0)
    dt2 = Dates.DateTime(2024,1,1,0,5)
    dt3 = Dates.DateTime(2024,1,1,0,10)
    @test Processing.isleftadj(dt1, dt2, tf)
    @test !Processing.isleftadj(dt1, dt3, tf)
    @test Processing.isrightadj(dt2, dt1, tf)
    @test !Processing.isrightadj(dt3, dt1, tf)
    @test Processing.isadjacent(dt1, dt2, tf)
    @test !Processing.isadjacent(dt1, dt3, tf)
end

# ──────────────────────────────────────────────
# isincomplete / iscomplete
# ──────────────────────────────────────────────
@testset "Processing.isincomplete/iscomplete" begin
    tf = TimeFrame(Dates.Minute(5))
    # Far past — definitely complete
    past = Dates.DateTime(2020,1,1)
    @test Processing.iscomplete(past, tf)
    @test !Processing.isincomplete(past, tf)
    # Far future — definitely incomplete
    future = Dates.DateTime(2099,1,1)
    @test !Processing.iscomplete(future, tf)
    @test Processing.isincomplete(future, tf)
end

# ──────────────────────────────────────────────
# trail! — trailing window
# ──────────────────────────────────────────────
@testset "Processing.trail!" begin
    tf = TimeFrame(Dates.Minute(5))
    base = Dates.DateTime(2024,1,1,0,0)
    df = DF.DataFrame(
        timestamp=[base + Dates.Minute(5*(i-1)) for i in 1:3],
        open=[1.0,2.0,3.0], high=[1.5,2.5,3.5], low=[0.5,1.5,2.5],
        close=[1.2,2.2,3.2], volume=[10.0,20.0,30.0]
    )
    to = base + Dates.Minute(20)
    Processing.trail!(df, tf; to=to)
    @test DF.nrow(df) == 4
    @test df.timestamp[end] == Dates.DateTime(2024,1,1,0,15)
    @test df.close[end] == df.close[end-1]
    @test df.volume[end] == 0.0
    # trail! adds candles with same close price and zero volume
    @test df.open[4] == df.close[3]
    @test df.high[4] == df.close[3]
    @test df.low[4] == df.close[3]
end

# ──────────────────────────────────────────────
# trimzeros! — remove unix epoch rows
# ──────────────────────────────────────────────
@testset "Processing.trimzeros!" begin
    base = Dates.DateTime(2024,1,1)
    df = DF.DataFrame(
        timestamp=[base, base, base + Dates.Minute(5)],
        open=[1.0,2.0,3.0], high=[1.5,2.5,3.5], low=[0.5,1.5,2.5],
        close=[1.2,2.2,3.2], volume=[10.0,20.0,30.0]
    )
    Processing.trimzeros!(df)
    @test DF.nrow(df) == 3
    # No unix epoch timestamps, nothing removed

    epoch = Dates.unix2datetime(0)
    df2 = DF.DataFrame(
        timestamp=[epoch, epoch, base + Dates.Minute(5)],
        open=[1.0,2.0,3.0], high=[1.5,2.5,3.5], low=[0.5,1.5,2.5],
        close=[1.2,2.2,3.2], volume=[10.0,20.0,30.0]
    )
    Processing.trimzeros!(df2)
    @test DF.nrow(df2) == 1
    @test df2.timestamp[1] == base + Dates.Minute(5)
end

# ──────────────────────────────────────────────
# fill_missing_candles! — gap filling
# ──────────────────────────────────────────────
@testset "Processing.fill_missing_candles!" begin
    tf = TimeFrame(Dates.Minute(5))
    base = Dates.DateTime(2024,1,1,0,0)
    # Create DataFrame with a gap at 0:10
    df = DF.DataFrame(
        timestamp=[base, base + Dates.Minute(5), base + Dates.Minute(15)],
        open=[1.0,2.0,4.0], high=[1.5,2.5,4.5], low=[0.5,1.5,3.5],
        close=[1.2,2.2,4.2], volume=[10.0,20.0,40.0]
    )
    result = Processing._fill_missing_candles(df, Dates.Minute(5);
        strategy=:close, inplace=false, def_strategy=Processing.novol_candle)
    @test DF.nrow(result) == 4
    @test result.timestamp[3] == base + Dates.Minute(10)
    # Filled with close of previous (2.2)
    @test result.open[3] == 2.2
    @test result.high[3] == 2.2
    @test result.low[3] == 2.2
    @test result.close[3] == 2.2
    @test result.volume[3] == 0.0
end

# ──────────────────────────────────────────────
# _normalize — array normalization
# ──────────────────────────────────────────────
@testset "Processing.normalize" begin
    arr = [1.0, 2.0, 3.0, 4.0, 5.0]
    # Z-score normalization
    n = Processing._normalize(arr; unit=false, copy=true)
    @test length(n) == 5
    @test mean(n) ≈ 0.0 atol=1e-10
    @test std(n) ≈ 1.0

    # Unit range normalization
    n2 = Processing._normalize(arr; unit=true, copy=true)
    @test minimum(n2) ≈ 0.0
    @test maximum(n2) ≈ 1.0
end

# ──────────────────────────────────────────────
# to_ohlcv — DataFrame to OHLCV conversion
# ──────────────────────────────────────────────
@testset "Processing.to_ohlcv" begin
    base = Dates.DateTime(2024,1,1,0,0)
    df = DF.DataFrame(
        timestamp=[base, base, base + Dates.Minute(5), base + Dates.Minute(5)],
        price=[1.0, 1.5, 2.0, 3.0],
        amount=[10.0, 20.0, 30.0, 40.0]
    )
    # This is from TradesOHLCV submodule
    ohlcv = Processing.TradesOHLCV.to_ohlcv(df)
    @test DF.nrow(ohlcv) == 2
    @test ohlcv.open[1] == 1.0
    @test ohlcv.high[1] == 1.5
    @test ohlcv.low[1] == 1.0
    @test ohlcv.close[1] == 1.5
    @test ohlcv.volume[1] == 30.0
    @test ohlcv.open[2] == 2.0
    @test ohlcv.high[2] == 3.0
end

# ──────────────────────────────────────────────
# _remove_incomplete_candle
# ──────────────────────────────────────────────
@testset "Processing._remove_incomplete_candle" begin
    tf = TimeFrame(Dates.Minute(5))
    base = Dates.DateTime(2024,1,1,0,0)
    df = DF.DataFrame(
        timestamp=[base, base + Dates.Minute(5), base + Dates.Minute(10)],
        open=[1.0,2.0,3.0], high=[1.5,2.5,3.5], low=[0.5,1.5,2.5],
        close=[1.2,2.2,3.2], volume=[10.0,20.0,30.0]
    )
    # Past timestamp should not be removed
    result = Processing._remove_incomplete_candle(df, tf)
    @test DF.nrow(result) == 3
end

@testset "Processing.upsample" begin
    tf_large = TimeFrame(Dates.Minute(5))
    tf_small = TimeFrame(Dates.Minute(1))

    # 1. Standard case
    df = DF.DataFrame(
        timestamp=[Dates.DateTime(2024,1,1,0,5), Dates.DateTime(2024,1,1,0,10)],
        open=[1.0, 2.0], high=[1.5, 2.5], low=[0.5, 1.5],
        close=[1.2, 2.2], volume=[10.0, 20.0]
    )
    result = Processing.upsample(df, tf_large, tf_small)
    @test DF.nrow(result) == 10
    @test all(result.open[1:5] .== 1.0)
    @test all(result.open[6:10] .== 2.0)
    @test all(result.volume[1:5] .== 2.0)
    @test all(result.volume[6:10] .== 4.0)
    @test result.timestamp[1] == Dates.DateTime(2024,1,1,0,1)
    @test result.timestamp[5] == Dates.DateTime(2024,1,1,0,5)
    @test result.timestamp[6] == Dates.DateTime(2024,1,1,0,6)
    @test result.timestamp[10] == Dates.DateTime(2024,1,1,0,10)

    # 2. Single row input
    df1 = DF.DataFrame(
        timestamp=[Dates.DateTime(2024,1,1,0,5)], open=[1.0], high=[1.5], low=[0.5],
        close=[1.2], volume=[10.0]
    )
    result1 = Processing.upsample(df1, tf_large, tf_small)
    @test DF.nrow(result1) == 5
    @test all(result1.open .== 1.0)
    @test all(result1.volume .== 2.0)
    @test result1.timestamp[1] == Dates.DateTime(2024,1,1,0,1)
    @test result1.timestamp[5] == Dates.DateTime(2024,1,1,0,5)

    # 3. Empty DataFrame
    df_empty = DF.DataFrame(
        timestamp=Dates.DateTime[], open=Float64[], high=Float64[], low=Float64[],
        close=Float64[], volume=Float64[]
    )
    result_empty = Processing.upsample(df_empty, tf_large, tf_small)
    @test DF.nrow(result_empty) == 0

    # 4. Non-divisible timeframes
    tf_bad = TimeFrame(Dates.Minute(5))
    tf_small_bad = TimeFrame(Dates.Minute(3))
    @test_throws AssertionError Processing.upsample(df1, tf_bad, tf_small_bad)

    # 5. Equal timeframes
    tf_equal = TimeFrame(Dates.Minute(1))
    @test_throws AssertionError Processing.upsample(df1, tf_equal, tf_equal)

    # 6. Zero volume — gracefully handled
    df_zero = DF.DataFrame(
        timestamp=[Dates.DateTime(2024,1,1,0,5)], open=[1.0], high=[1.5], low=[0.5],
        close=[1.2], volume=[0.0]
    )
    result_zero = Processing.upsample(df_zero, tf_large, tf_small)
    @test all(result_zero.volume .== 0.0)
    @test all(result_zero.open .== 1.0)

    # 7. Non-monotonic timestamps
    df_nonmono = DF.DataFrame(
        timestamp=[Dates.DateTime(2024,1,1,0,10), Dates.DateTime(2024,1,1,0,5)],
        open=[2.0, 1.0], high=[2.5, 1.5], low=[1.5, 0.5],
        close=[2.2, 1.2], volume=[20.0, 10.0]
    )
    result_nonmono = Processing.upsample(df_nonmono, tf_large, tf_small)
    @test DF.nrow(result_nonmono) == 10
    @test all(result_nonmono.open[1:5] .== 2.0)
    @test all(result_nonmono.open[6:10] .== 1.0)

    # 8. Duplicate timestamps
    df_dup = DF.DataFrame(
        timestamp=[Dates.DateTime(2024,1,1,0,5), Dates.DateTime(2024,1,1,0,5)],
        open=[1.0, 2.0], high=[1.5, 2.5], low=[0.5, 1.5],
        close=[1.2, 2.2], volume=[10.0, 20.0]
    )
    result_dup = Processing.upsample(df_dup, tf_large, tf_small)
    @test DF.nrow(result_dup) == 10
    @test all(result_dup.open[1:5] .== 1.0)
    @test all(result_dup.open[6:10] .== 2.0)

    # 9. NaN/Inf/missing values — throws MethodError
    df_nan = DF.DataFrame(
        timestamp=[Dates.DateTime(2024,1,1,0,5)], open=[NaN], high=[Inf], low=[-Inf],
        close=[missing], volume=[10.0]
    )
    @test_throws MethodError Processing.upsample(df_nan, tf_large, tf_small)

    # 10. Large DataFrame (1000 rows, performance not correctness)
    nrows = 1000
    df_large = DF.DataFrame(
        timestamp=[Dates.DateTime(2024,1,1,0,0) + Dates.Minute(5*(i-1)) for i in 1:nrows],
        open=ones(nrows), high=ones(nrows), low=ones(nrows),
        close=ones(nrows), volume=ones(nrows)
    )
    result_large = Processing.upsample(df_large, tf_large, tf_small)
    @test DF.nrow(result_large) == nrows * 5
end
