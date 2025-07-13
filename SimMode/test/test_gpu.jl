using Test
using SimMode
using SimMode.GPU
using OnlineTechnicalIndicators
using StrategyTools
using Exchanges
using Instruments
using OrderTypes

struct TestStrategy <: Strategy{Sim}
    universe::Vector{Asset}
    indicators::Vector{OnlineIndicator}
end

function Executors.call!(s::TestStrategy, ai::Asset, dt::DateTime, ctx)
    # A simple strategy that buys if the indicator is above a certain value
    if value(s.indicators[1]) > 45.0
        order!(s, ai, 1.0, Buy, MarketOrder())
    end
end

@testset "GPU Backtest" begin
    # Create a test strategy
    assets = [Asset("BTC/USDT", "binance")]
    indicators = [SMA(period=5)]
    strategy = TestStrategy(assets, indicators)

    # Create a backtest
    backtest = Backtest(strategy, DateTime(2023, 1, 1), DateTime(2023, 1, 10))

    # Run the CPU backtest
    cpu_backtest = deepcopy(backtest)
    SimMode.run!(cpu_backtest)

    # Run the GPU backtest
    gpu_backtest = deepcopy(backtest)
    # Manually convert internal buffers to oneAPI arrays for testing
    gpu_backtest.strategy.indicators[1].input_values.buffer = oneAPI.oneArray(gpu_backtest.strategy.indicators[1].input_values.buffer)
    SimMode.run!(gpu_backtest, use_gpu=true)

    # Compare the results
    @test cpu_backtest.broker.balance ≈ gpu_backtest.broker.balance atol=1e-5
    @test length(cpu_backtest.broker.trades) == length(gpu_backtest.broker.trades)
end
