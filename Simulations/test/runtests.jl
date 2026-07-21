module Runtests

using Test
using Simulations
using Simulations.TimeTicks: DateTime, Minute, Second

@testset "Simulations" begin
    @testset "types.jl" begin
        @testset "PricePair and lasttwo" begin
            arr = [1.0, 2.0, 3.0, 4.0, 5.0]
            pair = Simulations.lasttwo(arr)
            @test pair.prev == 4.0
            @test pair.this == 5.0
            @test pair isa Simulations.PricePair
        end

        @testset "DF constant" begin
            @test Simulations.DF == Union{DateTime,Float64}
        end
    end

    @testset "profits.jl" begin
        @testset "profitat" begin
            p = Simulations.profitat(100.0, 100.0, 0.001; digits=8)
            @test p ≈ -0.001998 atol=1e-6

            p2 = Simulations.profitat(100.0, 110.0, 0.001; digits=8)
            @test p2 ≈ 0.0978022 atol=1e-6

            p3 = Simulations.profitat(100.0, 100.0, 0.0; digits=8)
            @test p3 == 0.0

            p4 = Simulations.profitat(100.0, 90.0, 0.001; digits=8)
            @test p4 ≈ -0.1017982 atol=1e-6

            p5 = Simulations.profitat(100.0, 105.0, 0.001; digits=2)
            @test p5 == 0.05
        end

        @testset "ishighfirst" begin
            @test Simulations.ishighfirst(110.0, 90.0) == true
            @test Simulations.ishighfirst(90.0, 110.0) == false
            @test Simulations.ishighfirst(100.0, 100.0) == true
        end
    end

    @testset "spread.jl" begin
        @testset "rawspread" begin
            @test Simulations.rawspread(100.0, 100.0, 100.0) == 0.0
            s = Simulations.rawspread(110.0, 90.0, 105.0)
            @test s ≈ 10.0
            s2 = Simulations.rawspread(110.0, 90.0, 90.0)
            @test s2 ≈ 40.0
            s3 = Simulations.rawspread(110.0, 90.0, 110.0)
            @test s3 == 0.0
        end

        @testset "opclspread" begin
            @test Simulations.opclspread(100.0, 105.0) == 5.0
            @test Simulations.opclspread(105.0, 100.0) == 5.0
            @test Simulations.opclspread(100.0, 100.0) == 0.0
        end

        @testset "spread dispatch" begin
            @test Simulations.spread(100.0, 105.0) == 5.0
            @test Simulations.spread(Val(:opcl), 100.0, 105.0) == 5.0
            @test Simulations.spread(Val(:raw), 110.0, 90.0, 105.0) ≈ 10.0
            @test Simulations.spread(Val(:abra), 110.0, 90.0, 105.0) ≈ 0.042938 atol=1e-5
        end

        @testset "edge2spread" begin
            @test Simulations.edge2spread(110.0, 90.0, 105.0, 95.0) ≈ 0.055928 atol=1e-5
            @test Simulations.edge2spread(100.0, 100.0, 100.0, 100.0) == 0
        end

        @testset "logspread" begin
            ts = (prev=DateTime(2020,1,1,0,1), this=DateTime(2020,1,1,0,2))
            o = (prev=100.0, this=102.0)
            h = (prev=105.0, this=108.0)
            l = (prev=95.0, this=98.0)
            c = (prev=102.0, this=105.0)
            v = (prev=1000.0, this=1100.0)
            l2 = Simulations.LastTwo((timestamp=ts, open=o, high=h, low=l, close=c, volume=v))
            ls = Simulations.logspread(l2)
            @test ls >= 0.0
            @test ls isa Float64
        end

        @testset "sqrtspread" begin
            @test Simulations.sqrtspread([100.0, 102.0, 101.0, 103.0, 99.0]) ≈ 0.894427 atol=1e-5
            @test Simulations.sqrtspread([100.0]) == 0.0
        end

        @testset "coschspread" begin
            high = [105.0, 108.0, 107.0, 110.0, 106.0, 109.0, 111.0, 112.0]
            low  = [95.0,  98.0,  97.0,  90.0,  94.0,  93.0,  92.0,  91.0]
            cs = Simulations.coschspread(high, low; window=0)
            @test cs isa Float64
            @test 0.0 <= cs <= 1.0

            cs2 = Simulations.coschspread(high, low; window=3)
            @test cs2 isa Float64
        end

        @testset "rollspread" begin
            rs = Simulations.rollspread([100.0, 102.0, 101.0, 103.0])
            @test rs isa Float64
            @test rs >= 0.0
        end

        @testset "edgespread" begin
            high = [105.0, 108.0, 107.0]
            low  = [95.0,  98.0,  97.0]
            es = Simulations.edgespread(high, low)
            @test es isa Float64
            @test es >= 0.0

            @test Simulations.edgespread(100.0, 100.0) == 0.0
            @test Simulations.edgespread(110.0, 90.0) > 0.0

            high2 = [105.0, 108.0, 107.0, 110.0]
            low2  = [95.0,  98.0,  97.0,  90.0]
            es2 = Simulations.edgespread(high2, low2)
            @test es2 isa Float64
        end

        @testset "edge2spread scalar" begin
            @test Simulations.edge2spread(110.0, 90.0, 105.0, 95.0) ≈ 0.055928 atol=1e-5
            @test Simulations.edge2spread(100.0, 100.0, 100.0, 100.0) == 0
        end

        @testset "abraspread" begin
            ab = Simulations.abraspread(110.0, 90.0, 105.0)
            @test ab isa Float64
            @test ab >= 0.0

            ab2 = Simulations.abraspread(100.0, 100.0, 100.0)
            @test ab2 == 0.0
        end

        @testset "spread dispatch all variants" begin
            @test Simulations.spread(Val(:sqrt), [100.0, 102.0, 101.0]) isa Float64
            h = [105.0, 108.0, 107.0, 110.0]
            l = [95.0, 98.0, 97.0, 90.0]
            @test Simulations.spread(Val(:cosch), h, l; window=0) isa Float64
            @test Simulations.spread(Val(:roll), [100.0, 102.0, 101.0]) isa Float64
            @test Simulations.spread(Val(:edge), [105.0, 108.0], [95.0, 98.0]) isa Float64
            @test Simulations.spread(Val(:edge2), 110.0, 90.0, 105.0, 95.0) isa Float64
            @test Simulations.spread(Val(:abra), 110.0, 90.0, 105.0) isa Float64
        end
    end

    @testset "liq.jl" begin
        @testset "liquidity" begin
            liq = Simulations.liquidity(1000.0, 100.0, 110.0, 90.0)
            @test liq ≈ log10(1000.0 * 100.0 / 20.0)
        end

        @testset "liqat" begin
            vol = [100.0, 200.0, 300.0]
            close = [90.0, 100.0, 110.0]
            high = [95.0, 105.0, 115.0]
            low = [85.0, 95.0, 105.0]
            liq = Simulations.liqat(3, vol, close, high, low)
            @test liq ≈ log10((300.0 * 110.0) / (115.0 - 105.0))
        end

        @testset "illiqat" begin
            close = collect(1.0:200.0)
            volume = collect(100.0:299.0)
            illiq = Simulations.illiqat(200, close, volume; window=120)
            @test illiq isa Float64
            @test illiq > 0.0

            @test Simulations.illiqat(50, close, volume; window=120) === missing
        end
    end

    @testset "stoploss.jl" begin
        @testset "Stoploss3 constructor" begin
            sl = Simulations.Stoploss3(0.05, 0.1, 0.02)
            @test sl isa Simulations.Stoploss
            @test sl.minloss == 0.001
            @test sl.maxloss == 0.99
            @test sl.loss ≈ 0.05
            @test sl.loss_target ≈ 0.95
            @test sl.trailing_loss ≈ 0.1
            @test sl.trailing_loss_target ≈ 0.9
            @test sl.trailing_offset ≈ 0.02
        end

        @testset "Stoploss3 clamping" begin
            sl = Simulations.Stoploss3(0.0, 1.5, -0.1)
            @test sl.loss ≈ 0.001
            @test sl.trailing_loss ≈ 0.99
            @test sl.trailing_offset ≈ 0.001
        end

        @testset "stoploss!" begin
            sl = Simulations.Stoploss3(0.05)
            Simulations.stoploss!(sl, 0.1)
            @test sl.loss ≈ 0.1
            @test sl.loss_target ≈ 0.9

            Simulations.stoploss!(sl, 0.0)
            @test sl.loss ≈ 0.001
        end

        @testset "trailing!" begin
            sl = Simulations.Stoploss3(0.05)
            Simulations.trailing!(sl, 0.15)
            @test sl.trailing_loss ≈ 0.15
            @test sl.trailing_loss_target ≈ 0.85
        end

        @testset "offset!" begin
            sl = Simulations.Stoploss3(0.05)
            Simulations.offset!(sl, 0.03)
            @test sl.trailing_offset ≈ 0.03
        end

        @testset "stopat" begin
            sl = Simulations.Stoploss3(0.05)
            @test Simulations.stopat(100.0, sl) == 95.0

            cdl = Simulations.Candle(DateTime(2020,1,1), 100.0, 110.0, 90.0, 105.0, 1000.0)
            @test Simulations.stopat(cdl, sl) == 95.0
        end

        @testset "triggered" begin
            sl = Simulations.Stoploss3(0.05)
            cdl = Simulations.Candle(DateTime(2020,1,1), 100.0, 110.0, 95.0, 105.0, 1000.0)
            @test Simulations.triggered(sl, cdl, 96.0) == true
            @test Simulations.triggered(sl, cdl, 95.0) == true
            @test Simulations.triggered(sl, cdl, 94.0) == false

            @test Simulations.triggered(cdl, 96.0) == true
            @test Simulations.triggered(cdl, 94.0) == false
        end

        @testset "trailing_stop" begin
            sl = Simulations.Stoploss3(0.05, 0.1, 0.02)
            @test Simulations.trailing_stop(sl, 95.0, 110.0, 0.15) > 95.0

            sl2 = Simulations.Stoploss3(0.05, NaN, 0.02)
            @test Simulations.trailing_stop(sl2, 95.0, 110.0, 0.15) ≈ 95.0

            sl3 = Simulations.Stoploss3(0.05, 0.0, 0.02)
            @test Simulations.trailing_stop(sl3, 95.0, 110.0, 0.01) ≈ 95.0
        end
    end

    @testset "ema.jl" begin
        @testset "first_valid" begin
            @test Simulations.first_valid([1.0, 2.0, 3.0]) == 1
            @test Simulations.first_valid([NaN, NaN, 3.0]) == 3
            @test Simulations.first_valid([NaN, 2.0, 3.0]) == 2
            @test Simulations.first_valid([NaN, NaN, NaN]) == 0
        end

        @testset "ema vector" begin
            x = collect(1.0:20.0)
            e = Simulations.ema(x; n=3, alpha=0.5)
            @test length(e) == 20
            @test all(isnan, e[1:5])

            val = Simulations.ema(10.0, 9.5; n=6, alpha=0.5)
            @test val ≈ 0.5 * (10.0 - 9.5) + 9.5
        end

        @testset "ema scalar" begin
            val = Simulations.ema(10.0, 9.0)
            @test val ≈ (2.0/6 + 1.0) * (10.0 - 9.0) + 9.0
        end
    end

    @testset "synth.jl" begin
        @testset "synthcandle" begin
            ts = DateTime(2020, 1, 1, 0, 0, 0)
            candle = Simulations.synthcandle(ts, 100.0, 1000.0; u_price=1.0, u_vol=10.0, bound_price=5.0, bound_vol=50.0)
            @test candle isa Tuple
            @test length(candle) == 6
            @test candle[1] == ts
            open, high, low, close, volume = candle[2:6]
            @test all(v -> v > 0.0, (open, high, low, close))
            @test volume >= 0.0
            @test high >= open
        end

        @testset "synthohlcv" begin
            data = Simulations.synthohlcv(50; seed_price=100.0, seed_vol=1000.0)
            @test length(data) == 6
            @test length(data[1]) == 51
            @test data[1][1] == DateTime(2020, 1, 1)
        end

        @testset "_setorappend" begin
            d = Dict{String, Vector{Int}}()
            Simulations._setorappend(d, "a", [1, 2, 3])
            @test d["a"] == [1, 2, 3]

            Simulations._setorappend(d, "a", [4, 5])
            @test d["a"] == [1, 2, 3, 4, 5]
        end
    end

    @testset "rois.jl" begin
        @testset "Roi5" begin
            tups = [(0.5, Minute(5)), (0.8, Minute(10)), (1.0, Minute(15))]
            tf1m = Base.parse(Simulations.TimeFrame, "1m")
            roi = Simulations.Roi5(tups; timeframe=tf1m)
            @test roi isa Simulations.Roi
            @test length(roi) == 3
            @test roi.targets[1] == 0.5
            @test roi.timeouts[1] == Minute(5)
            @test roi.targets[3] == 1.0
            @test roi.timeouts[3] == Minute(15)
        end

        @testset "Roi5 zip constructor" begin
            targets = (1.0, 0.5)
            timeouts = (Minute(10), Minute(5))
            roi = Simulations.Roi5(targets, timeouts; timeframe=Base.parse(Simulations.TimeFrame, "1m"))
            @test roi.targets[1] == 0.5
            @test roi.timeouts[1] == Minute(5)
            @test roi.targets[2] == 1.0
            @test roi.timeouts[2] == Minute(10)
        end

        @testset "RoiInverted" begin
            tups = [(0.5, Minute(5)), (1.0, Minute(15))]
            roi = Simulations.Roi5(tups; timeframe=Base.parse(Simulations.TimeFrame, "1m"))
            inv = Simulations.RoiInverted(roi)
            @test inv isa Simulations.RoiInverted
            @test length(inv) == 2
            @test inv.targets[1] == 1.0
            @test inv.timeouts[1] == Minute(15)
            @test inv.targets[2] == 0.5
            @test inv.timeouts[2] == Minute(5)
        end

        @testset "roiweight" begin
            w = Simulations.roiweight(Second(30), 0.5, Second(0), 1.0, Second(60))
            @test w == 0.75

            w2 = Simulations.roiweight(Second(90), 0.5, Second(0), 1.0, Second(60))
            @test w2 == 1.25

            w3 = Simulations.roiweight(Second(30), 0.5, Second(60), 1.0, Second(60))
            @test w3 == 1.0
        end

        @testset "isroi" begin
            tups = [(0.1, Minute(3)), (0.05, Minute(5)), (0.025, Minute(10))]
            roi = Simulations.Roi5(tups; timeframe=Base.parse(Simulations.TimeFrame, "1m"))
            inv = Simulations.RoiInverted(roi)
            hit, target = Simulations.isroi(6, 0.1, inv)
            @test hit == true
            @test target ≈ 0.045 atol=1e-6

            hit2, target2 = Simulations.isroi(1, 0.2, inv)
            @test hit2 == false
            @test isnan(target2)

            inv2 = Simulations.RoiInverted(roi)
            @test inv2[1] isa Tuple
            @test length(inv2) == 3
        end


    end

    @testset "mootils.jl" begin
        @testset "unit_range" begin
            arr = [10.0, 20.0, 30.0, 40.0, 50.0]
            result = Simulations.Mootils.unit_range(arr)
            @test all(0.0 .<= result .<= 1.0)
            @test result[1] == 0.0
            @test result[end] == 1.0
        end

        @testset "unzip" begin
            tuples = [(1, "a"), (2, "b"), (3, "c")]
            a, b = Simulations.Mootils.unzip(tuples)
            @test a == [1, 2, 3]
            @test b == ["a", "b", "c"]
        end

        @testset "lagged" begin
            v = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0]
            lag = Simulations.Mootils.lagged(v, 3; idx=7, n=2)
            @test lag == [3.0, 4.0, 5.0]
            @test lag isa SubArray
        end

        @testset "filsoc" begin
            arr = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]
            match = [2.0, 4.0, 6.0, 8.0, 10.0, 12.0]
            result = Simulations.Mootils.filsoc(arr, 3.0, match)
            @test length(result) >= 1
            @test result[1] > 3.0

            result2 = Simulations.Mootils.filsoc(arr, 3.0, nothing; concat=false)
            @test length(result2) >= 1
        end

        @testset "filsoc with inv" begin
            arr = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]
            match = [2.0, 4.0, 6.0, 8.0, 10.0, 12.0]
            result = Simulations.Mootils.filsoc(arr, 4.0, match; inv=true)
            @test length(result) >= 1
            @test result[1] < 4.0
        end

        @testset "pipe overloads" begin
            @test (1.0, 2.0) |> (+) == 3.0
            @test (1.0, 2.0, 3.0) |> (a, b, c) -> a + b + c == 6.0
        end
    end

end

end
