using Test
using Processing
using Data
const DF = Data.DataFrames
const TimeFrame = Processing.Misc.TimeTicks.TimeFrame
const Dates = Processing.Misc.TimeTicks.Dates

# ──────────────────────────────────────────────
# upsample (ported from PlanarDev/test/test_processing.jl)
# ──────────────────────────────────────────────
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
end
