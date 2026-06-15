module PlottingTests

using Test
using Plotting
using Plotting.Makie
using Plotting.Metrics
using Plotting.Processing
using Plotting.Random

@testset "Plotting" begin
    @testset "Module loads" begin
        @test isdefined(Plotting, :plot)
        @test isdefined(Plotting, :plot_equity)
        @test isdefined(Plotting, :plot_trades)
    end

    @testset "Basic plot functions exist" begin
        @test isdefined(Plotting, :plot_equity)
        @test isdefined(Plotting, :plot_trades)
        @test isdefined(Plotting, :plot_drawdown)
        @test isdefined(Plotting, :plot_returns)
    end
end

end