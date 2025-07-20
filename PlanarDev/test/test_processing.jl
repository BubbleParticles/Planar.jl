using PlanarDev.Stubs
using Test

function test_processing()
    @eval begin
        using PlanarDev.Planar.Engine: Engine as egn
        using .egn.Misc: Misc as ms
        using .egn.Data: Data as da
        using .egn.Lang: Lang as lg
        using .egn.Processing: Processing as pr
        using .egn.Data.TimeTicks: TimeFrame
        PlanarDev.@environment!
    end

    @testset "Processing.upsample" begin
        # 1. Standard case (already present)
        tf_large = TimeFrame(Minute(5))
        tf_small = TimeFrame(Minute(1))
        df = da.DataFrame(
            timestamp=[DateTime(2024,1,1,0,5), DateTime(2024,1,1,0,10)],
            open=[1.0, 2.0], high=[1.5, 2.5], low=[0.5, 1.5], close=[1.2, 2.2], volume=[10.0, 20.0]
        )
        result = pr.upsample(df, tf_large, tf_small)
        @test da.nrow(result) == 10
        @test all(result.open[1:5] .== 1.0)
        @test all(result.open[6:10] .== 2.0)
        @test all(result.volume[1:5] .== 2.0)
        @test all(result.volume[6:10] .== 4.0)
        @test result.timestamp[1] == DateTime(2024,1,1,0,1)
        @test result.timestamp[5] == DateTime(2024,1,1,0,5)
        @test result.timestamp[6] == DateTime(2024,1,1,0,6)
        @test result.timestamp[10] == DateTime(2024,1,1,0,10)

        # 2. Single row input
        df1 = da.DataFrame(timestamp=[DateTime(2024,1,1,0,5)], open=[1.0], high=[1.5], low=[0.5], close=[1.2], volume=[10.0])
        result1 = pr.upsample(df1, tf_large, tf_small)
        @test da.nrow(result1) == 5
        @test all(result1.open .== 1.0)
        @test all(result1.volume .== 2.0)
        @test result1.timestamp[1] == DateTime(2024,1,1,0,1)
        @test result1.timestamp[5] == DateTime(2024,1,1,0,5)

        # 3. Empty DataFrame
        df_empty = da.DataFrame(timestamp=DateTime[], open=Float64[], high=Float64[], low=Float64[], close=Float64[], volume=Float64[])
        result_empty = pr.upsample(df_empty, tf_large, tf_small)
        @test da.nrow(result_empty) == 0

        # 4. Non-divisible timeframes (should throw)
        tf_bad = TimeFrame(Minute(5))
        tf_small = TimeFrame(Minute(3))
        @test_throws AssertionError pr.upsample(df1, tf_bad, tf_small)

        # 5. Equal timeframes (should throw)
        tf_equal = TimeFrame(Minute(1))
        @test_throws AssertionError pr.upsample(df1, tf_equal, tf_equal)

        # 6. Zero volume
        df_zero = da.DataFrame(timestamp=[DateTime(2024,1,1,0,5)], open=[1.0], high=[1.5], low=[0.5], close=[1.2], volume=[0.0])
        @test_throws AssertionError pr.upsample(df_zero, tf_large, tf_small)
        tf_small = TimeFrame(Minute(1))
        result_zero = pr.upsample(df_zero, tf_large, tf_small)
        @test all(result_zero.volume .== 0.0)

        # 7. Non-monotonic timestamps (should still work, but output will be odd)
        df_nonmono = da.DataFrame(timestamp=[DateTime(2024,1,1,0,10), DateTime(2024,1,1,0,5)], open=[2.0, 1.0], high=[2.5, 1.5], low=[1.5, 0.5], close=[2.2, 1.2], volume=[20.0, 10.0])
        result_nonmono = pr.upsample(df_nonmono, tf_large, tf_small)
        @test da.nrow(result_nonmono) == 10
        # Should be two blocks of 5, but order is as in input
        @test all(result_nonmono.open[1:5] .== 2.0)
        @test all(result_nonmono.open[6:10] .== 1.0)

        # 8. NaN/Inf/missing values
        pr.upsample(df1, tf_large, tf_small)
        df_nan = da.DataFrame(timestamp=[DateTime(2024,1,1,0,5)], open=[NaN], high=[Inf], low=[-Inf], close=[missing], volume=[10.0])
        @test_throws MethodError pr.upsample(df_nan, tf_large, tf_small)

        # 9. Duplicate timestamps
        df_dup = da.DataFrame(timestamp=[DateTime(2024,1,1,0,5), DateTime(2024,1,1,0,5)], open=[1.0, 2.0], high=[1.5, 2.5], low=[0.5, 1.5], close=[1.2, 2.2], volume=[10.0, 20.0])
        result_dup = pr.upsample(df_dup, tf_large, tf_small)
        @test da.nrow(result_dup) == 10
        @test all(result_dup.open[1:5] .== 1.0)
        @test all(result_dup.open[6:10] .== 2.0)

        # 10. Very large DataFrame (performance, not correctness)
        nrows = 1000
        df_large = da.DataFrame(
            timestamp=[DateTime(2024,1,1,0,0) + Minute(5*(i-1)) for i in 1:nrows],
            open=ones(nrows), high=ones(nrows), low=ones(nrows), close=ones(nrows), volume=ones(nrows)
        )
        result_large = pr.upsample(df_large, tf_large, tf_small)
        @test da.nrow(result_large) == nrows * 5
    end
end 