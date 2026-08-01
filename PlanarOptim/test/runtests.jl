module PlottingTests
    # Tests for the Plotting submodule (moved from PlanarCore to PlanarOptim)
    using Test
    using PlanarOptim.Plotting
    using PlanarOptim.Plotting.Makie
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
