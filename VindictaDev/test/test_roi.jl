using Test

_roi_1() = begin
    roi = sml.Roi([(0.1, Second(130)), (0.05, Hour(1)), (0.01, Minute(30))])
    @test roi[1] == (0.1, Minute(2))
    @test roi[end] == (0.05, Hour(1))
    @test issorted(roi.timeouts)
    roii = sml.RoiInverted(roi)
    @test reverse(roii.timeouts) == roi.timeouts
    @test roii[1] == (0.05, Hour(1))
end

_roi_2() = begin
    target = 0.1
    next_target = 0.05
    timeout = Minute(10)
    next_timeout = Minute(45)
    w_1 = sml.roiweight(Minute(0), target, timeout, next_target, next_timeout)
    @test next_target <= w_1 <= target
    w_2 = sml.roiweight(Minute(45), target, timeout, next_target, next_timeout)
    @test next_target <= w_2 <= target
    @test next_target < target && w_2 <= w_1
    w_3 = sml.roiweight(Minute(100), target, timeout, next_target, next_timeout)
    @test w_3 <= 0
end

_roi_3() = begin
    roi = sml.Roi([(0.1, Minute(30)), (0.03, Hour(1)), (0, Day(1))], timeframe=tf"5m")
    roii = sml.RoiInverted(roi)
    t = sml.isroi(2, 0.3, roii)
    @test !t[1] && isnan(t[2])
    t = sml.isroi(10, 0.3, roii)
    @test t[1] && isapprox(t[2], 0.0534, atol=1e-4)
    t = sml.isroi(10, -0.5, roii)
    @test !t[1] && isnan(t[2])
    t = sml.isroi(20 * 24, 0, roii)
    @test t[1] && t[2] < 0
end

test_roi() = @testset "roi" begin
    @eval begin
        using TimeTicks
        using .Vindicta.Engine.Simulations: Simulations as sml
        using Data: Data as da
    end
    _roi_1()
    _roi_2()
end
