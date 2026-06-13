using Test
using StrategyTools
using Statistics: mean

const ST = StrategyTools

@testset "degrees" begin
    @test ST.degrees(0.0) == 0.0
    @test ST.degrees(1.0) ≈ 45.0
    @test ST.degrees(-1.0) ≈ 45.0
    @test ST.degrees(Inf) ≈ 90.0
end

@testset "MovingExtrema" begin
    ext = ST.MovingExtrema(3)
    @test all(ismissing, extrema(ext))

    push!(ext, 2.0)
    push!(ext, 5.0)
    push!(ext, 3.0)
    @test extrema(ext) == (2.0, 5.0)

    push!(ext, 1.0)
    @test extrema(ext) == (1.0, 5.0)

    push!(ext, 10.0)
    @test extrema(ext) == (1.0, 10.0)

    push!(ext, 0.5)
    @test extrema(ext) == (0.5, 10.0)

    push!(ext, 0.5)
    @test extrema(ext) == (0.5, 10.0)

    ext2 = ST.MovingExtrema(4)
    for v in [3.0, 1.0, 4.0, 1.5, 5.0, 9.0, 2.0]
        push!(ext2, v)
    end
    @test extrema(ext2) == (1.5, 9.0)
end

@testset "iscrossed" begin
    @test ST.iscrossed(Val(:above); a=3.0, b=2.0, prev_a=1.0, prev_b=1.5)
    @test !ST.iscrossed(Val(:above); a=2.0, b=3.0, prev_a=1.0, prev_b=1.5)
    @test !ST.iscrossed(Val(:above); a=3.0, b=2.0, prev_a=3.0, prev_b=1.5)

    @test ST.iscrossed(Val(:below); a=2.0, b=3.0, prev_a=3.0, prev_b=2.0)
    @test !ST.iscrossed(Val(:below); a=3.0, b=2.0, prev_a=2.0, prev_b=1.0)
    @test !ST.iscrossed(Val(:below); a=2.0, b=3.0, prev_a=2.0, prev_b=3.0)

    @test ST.iscrossed(Val(:above_now); a=5.0, b=3.0)
    @test !ST.iscrossed(Val(:above_now); a=3.0, b=5.0)

    @test ST.iscrossed(Val(:below_now); a=2.0, b=4.0)
    @test !ST.iscrossed(Val(:below_now); a=4.0, b=2.0)
end

@testset "ismissingvalue" begin
    @test ST.ismissingvalue(NaN)
    @test !ST.ismissingvalue(1.0)
    @test !ST.ismissingvalue(0.0)
    @test ST.ismissingvalue(missing)
    @test !ST.ismissingvalue(nothing)
end

@testset "indicator_scalar" begin
    @test ST.indicator_scalar(42.0) == 42.0
    @test ST.indicator_scalar(0) == 0
    @test ST.indicator_scalar((1.0, 2.0)) == 1.0
    @test ST.indicator_scalar([5.0]) == 5.0
end

@testset "default_dampener" begin
    @test ST.default_dampener(0.5) == 0.5
    @test ST.default_dampener(1.0) == 1.0
    @test ST.default_dampener(2.0) == 2.0
    @test ST.default_dampener(3.0) ≈ log2(3) + 1.0
    @test ST.default_dampener(10.0) ≈ log2(10) + 1.0
    @test ST.default_dampener(0.0) == 0.0
    @test ST.default_dampener(-1.0) == 0.0
end

@testset "timeframe division" begin
    tf_day = ST.TimeTicks.@tf_str("1d")
    result = tf_day / (1000 * 60 * 60 * 24 / 12)
    @test result.value == 12

    tf_hour = ST.TimeTicks.@tf_str("1h")
    result2 = tf_hour / (1000 * 60 * 60 / 4)
    @test result2.value == 4
end
