module PlottingTests

using Test
using PlanarCore
using PlanarCore.Plotting
using PlanarCore.Plotting.Makie
using PlanarCore.Metrics
using PlanarCore.Processing
using Random

@testset "Plotting" begin
    @testset "Module loads" begin
        @test isdefined(Plotting, :ohlcv)
        @test isdefined(Plotting, :ohlcv!)
        @test isdefined(Plotting, :tradesticks)
        @test isdefined(Plotting, :tradesticks!)
        @test isdefined(Plotting, :balloons)
    end

    @testset "Basic plot functions exist" begin
        @test isdefined(Plotting, :ohlcv)
        @test isdefined(Plotting, :ohlcv!)
        @test isdefined(Plotting, :tradesticks)
        @test isdefined(Plotting, :tradesticks!)
        @test isdefined(Plotting, :balloons)
    end
end

end