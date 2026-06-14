using Test
using StrategyTools
using Statistics: mean

const ST = StrategyTools
const CB = ST.egn.Data.DataStructures.CircularBuffer

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

@testset "get_signal_value" begin
    ct = (; a=(; state=(; value=42.0)), b=(; state=(; value=99.0)))
    @test ST.get_signal_value(ct, :a) == 42.0
    @test ST.get_signal_value(ct, :b) == 99.0
end

@testset "signal_value / signal_prev with kw" begin
    sig = (; state=(; value=7.5), prev=3.0)
    @test ST.signal_value(nothing; sig) == 7.5
    @test ST.signal_prev(nothing; sig) == 3.0
end

@testset "cmpab" begin
    mutable struct MockSig
        state
        trend
    end
    ms = MockSig((; value=(; a=10.0, b=5.0)), ST.Stationary)
    @test ST.cmpab(ms, :a, :b) == true
    @test ms.trend == ST.Up
    @test ST.cmpab(ms, :b, :a) == true
    @test ms.trend == ST.Down
    @test ST.cmpab(ms, :a, :a) == true
    @test ms.trend == ST.Stationary
end

@testset "rateab" begin
    mutable struct MockSig2
        state
        trend
    end
    ms = MockSig2((; value=(; a=10.0, b=5.0)), ST.Stationary)
    a, b = ST.rateab(ms, :a, :b)
    @test a ≈ 2.0
    @test b ≈ 0.5
end

@testset "ismissingvalue" begin
    @test ST.ismissingvalue(NaN)
    @test !ST.ismissingvalue(1.0)
    @test !ST.ismissingvalue(0.0)
    @test ST.ismissingvalue(missing)
    @test !ST.ismissingvalue(nothing)
end

@testset "SignalState4 iteration" begin
    ss = ST.SignalState4{Int,Float64}(
        prev=0.0, trace=CB{Float64}(5), state=42
    )
    # iterate returns getfield(state, 1) = date (field 1)
    val, idx = iterate(ss)
    @test val == ss.date
    @test idx == 1
    # next iteration: getfield(state, 2) = trend (field 2)
    val2, idx2 = iterate(ss, 1)
    @test val2 == ss.trend
    @test idx2 == 2
end

@testset "calculate_slope" begin
    trace = CB{Float64}(10)
    push!(trace, 1.0)
    push!(trace, 2.0)
    push!(trace, 3.0)
    sig = (; trace)
    @test ST.calculate_slope(sig) ≈ 1.0  # (3-1)/2

    # Single element → 0.0
    trace2 = CB{Float64}(5)
    push!(trace2, 5.0)
    sig2 = (; trace=trace2)
    @test ST.calculate_slope(sig2) == 0.0

    # Empty → 0.0
    trace3 = CB{Float64}(5)
    sig3 = (; trace=trace3)
    @test ST.calculate_slope(sig3) == 0.0
end

@testset "oti type dispatch" begin
    using .ST.oti: StochRSIVal, VTXVal
    # Missing-typed value
    @test ST.ismissing(StochRSIVal{Missing}(missing, missing))
    # Float64-typed values
    @test !ST.ismissing(StochRSIVal{Float64}(0.5, 0.3))
    # Partial missing via Union
    @test ST.ismissing(StochRSIVal{Union{Float64, Missing}}(missing, 0.3))
    @test ST.ismissing(StochRSIVal{Union{Float64, Missing}}(0.5, missing))

    # oti.VTXVal scalar extraction
    vtx = VTXVal(1.5, 0.5)
    @test ST.indicator_scalar(vtx) == 1.5
end
