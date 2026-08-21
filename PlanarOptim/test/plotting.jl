module PlottingTests

using Test
using PlanarOptim
using PlanarOptim.Plotting
using PlanarOptim.Plotting.Makie
using PlanarCore
using PlanarCore.Strategies: Strategy
using PlanarCore.Instances: InstrumentInstance, ohlcv, trades, ohlcv_dict
using PlanarCore.Stubs: stub_strategy
using PlanarCore.Collections: snapshot
using Random
using Statistics

# Set Makie to non-interactive backend for testing
import Makie
Makie.inline!(false)

@testset "Plotting" begin
    @testset "Module loads" begin
        @test isdefined(Plotting, :ohlcv)
        @test isdefined(Plotting, :ohlcv!)
        @test isdefined(Plotting, :tradesticks)
        @test isdefined(Plotting, :tradesticks!)
        @test isdefined(Plotting, :balloons)
        @test isdefined(Plotting, :plot_results)
    end

    @testset "Basic plot functions exist" begin
        @test isdefined(Plotting, :ohlcv)
        @test isdefined(Plotting, :ohlcv!)
        @test isdefined(Plotting, :tradesticks)
        @test isdefined(Plotting, :tradesticks!)
        @test isdefined(Plotting, :balloons)
        @test isdefined(Plotting, :plot_results)
    end

    @testset "plot_results with synthetic strategy" begin
        # Create a synthetic strategy with OHLCV data and trades
        s = stub_strategy(; dostub=true)
        
        # Verify the strategy has data
        @test !isempty(s.universe)
        ii = first(s.universe)
        @test !isempty(PlanarCore.Instances.ohlcv(ii))
        # Trades may be empty depending on stub data
        
        # Test plot_results returns a Figure
        fig = plot_results(s)
        @test fig isa Makie.Figure
        
        # Verify figure has content (axes)
        @test length(fig.content) > 0
        
        # Should have price axis
        @test haskey(fig.attributes, :price_ax)
        price_ax = fig.attributes[:price_ax][]
        @test price_ax isa Makie.Axis
    end

    @testset "plot_results with InstrumentInstance" begin
        s = stub_strategy(; dostub=true)
        ii = first(s.universe)
        
        fig = plot_results(ii)
        @test fig isa Makie.Figure
        @test length(fig.content) > 0
        @test haskey(fig.attributes, :price_ax)
    end

    @testset "plot_results with indicators" begin
        s = stub_strategy(; dostub=true)
        ii = first(s.universe)
        ohlcv_data = PlanarCore.Instances.ohlcv(ii)
        # Create some dummy indicator data (e.g., SMA)
        close_prices = Float32.(ohlcv_data.close)
        sma_period = 10
        sma = Float32[]
        for i in 1:length(close_prices)
            if i < sma_period
                push!(sma, NaN)
            else
                push!(sma, Statistics.mean(close_prices[i-sma_period+1:i]))
            end
        end
        
        fig = plot_results(s; indicators=[sma])
        @test fig isa Makie.Figure
    end

    @testset "plot_results with channels" begin
        s = stub_strategy(; dostub=true)
        ii = first(s.universe)
        ohlcv_data = PlanarCore.Instances.ohlcv(ii)
        
        # Create dummy channel data (e.g., Bollinger Bands)
        close_prices = Float32.(ohlcv_data.close)
        period = 20
        upper = Float32[]
        lower = Float32[]
        for i in 1:length(close_prices)
            if i < period
                push!(upper, NaN)
                push!(lower, NaN)
            else
                window = close_prices[i-period+1:i]
                m = Statistics.mean(window)
                sd = Statistics.std(window)
                push!(upper, m + 2*sd)
                push!(lower, m - 2*sd)
            end
        end
        fig = plot_results(s; channels=[lower, upper])
        @test fig isa Makie.Figure
    end

    @testset "plot_results without trades" begin
        s = stub_strategy(; dostub=true)
        
        fig = plot_results(s; show_trades=false)
        @test fig isa Makie.Figure
    end

    @testset "plot_results without balance" begin
        s = stub_strategy(; dostub=true)
        
        fig = plot_results(s; show_balance=false)
        @test fig isa Makie.Figure
        # Should only have 1 row (price) instead of 2 (price + balance)
        @test length(fig.layout.content) >= 1
    end

    @testset "plot_results with asset selection" begin
        s = stub_strategy(; dostub=true)
        
        # Test with index
        fig1 = plot_results(s; asset=1)
        @test fig1 isa Makie.Figure
        
        # Test with symbol
        first_asset = first(s.universe).asset.bc
        fig2 = plot_results(s; asset=first_asset)
        @test fig2 isa Makie.Figure
        
        # Test with instance
        fig3 = plot_results(s; asset=first(s.universe))
        @test fig3 isa Makie.Figure
    end

    @testset "plot_results with custom timeframe" begin
        s = stub_strategy(; dostub=true)
        ii = first(s.universe)
        
        # Test with a specific timeframe
        available_tfs = collect(keys(PlanarCore.Instances.ohlcv_dict(ii)))
        filter!(tf -> tf != PlanarCore.TimeTicks.TICK_TIMEFRAME, available_tfs)
        if !isempty(available_tfs)
            tf = first(available_tfs)
            fig = plot_results(s; tf=tf)
            @test fig isa Makie.Figure
        end
    end
end

end # module