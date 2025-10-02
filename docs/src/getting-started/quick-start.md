# Quick Start Guide

Get your first Planar strategy running in 15 minutes! This guide will walk you through the essential steps to download data, run a backtest, and visualize results.

## Prerequisites

- Julia 1.11+ installed
- Docker (recommended) or Git for installation
- 15 minutes of your time

## Step 1: Install Planar

### Option A: Docker (Recommended)

The fastest way to get started is with Docker:

```bash
# Pull the interactive image (includes plotting and optimization)
docker pull docker.io/psydyllic/planar-sysimage-interactive

# Run Planar
docker run -it --rm docker.io/psydyllic/planar-sysimage-interactive julia
```

### Option B: From Source

If you prefer to build from source:

```bash
# Clone the repository
git clone --recurse-submodules https://github.com/psydyllic/Planar.jl
cd Planar.jl

# Set up environment
direnv allow  # or manually source .envrc

# Start Julia
julia --project=PlanarInteractive
```

## Step 2: Load Planar

In your Julia REPL:

```julia
# Load Planar with interactive features
using PlanarInteractive

# Bring modules into scope
@environment!
```

You should see output indicating that Planar modules are loading. This may take a moment on first run.

## Step 3: Create Your First Strategy

Load the built-in QuickStart strategy:

```julia
# Create a strategy instance
s = strategy(:QuickStart, exchange=:binance)

# Check the strategy configuration
s.config
```

This creates a strategy instance configured for the Binance exchange. The QuickStart strategy is a simple moving average crossover strategy that's perfect for learning.

## Step 4: Download Market Data

```julia
# Download the last 1000 candles for the strategy's asset
fetch_ohlcv(s, from=-1000)

# Load the data into the strategy
load_ohlcv(s)

# Verify data was loaded
println("Data range: $(first(s.universe.assets).data.timestamp[1]) to $(first(s.universe.assets).data.timestamp[end])")
```

This downloads OHLCV (Open, High, Low, Close, Volume) data for the strategy's configured trading pair.

## Step 5: Run Your First Backtest

```julia
# Run the backtest
start!(s)

# Check the results
println("Final balance: $(cash(s))")
println("Number of trades: $(length(s.history.trades))")
```

The `start!()` function runs the strategy against historical data, simulating trades based on the strategy's logic.

## Step 6: Visualize Results

```julia
# Set up plotting backend
using WGLMakie  # or GLMakie for desktop

# Create a comprehensive plot showing trades
balloons(s)
```

This creates an interactive plot showing:
- OHLCV candlestick chart
- Buy/sell signals as colored balloons
- Balance evolution over time

## Step 7: Analyze Performance

```julia
# Get detailed performance metrics
metrics = performance_metrics(s)
println("Total Return: $(metrics.total_return)")
println("Sharpe Ratio: $(metrics.sharpe_ratio)")
println("Max Drawdown: $(metrics.max_drawdown)")

# View trade history
for trade in s.history.trades[1:min(5, end)]
    println("$(trade.timestamp): $(trade.side) $(trade.amount) at $(trade.price)")
end
```

## Understanding What Happened

Congratulations! You just:

1. **Loaded a strategy** - The QuickStart strategy uses moving average crossovers to generate buy/sell signals
2. **Downloaded data** - Real market data from Binance for backtesting
3. **Ran a simulation** - The strategy made trading decisions based on historical price movements
4. **Visualized results** - Interactive plots show exactly when and why trades were made
5. **Analyzed performance** - Metrics help you understand if the strategy was profitable

## Key Concepts

- **Strategy**: A Julia module that defines trading logic
- **Universe**: The set of assets (trading pairs) your strategy trades
- **OHLCV Data**: Open, High, Low, Close, Volume - the basic market data
- **Backtest**: Running your strategy against historical data to see how it would have performed
- **Simulation Mode**: Planar's default mode that simulates trades without real money

## Next Steps

Now that you have Planar running:

1. **[Complete Installation](installation.md)** - Set up a proper development environment
2. **[Build Your First Strategy](first-strategy.md)** - Learn to create custom trading logic
3. **[Explore Examples](../strategy.md#examples)** - Study more complex strategy patterns
4. **[Learn About Data](../data.md)** - Understand Planar's data management capabilities

## Common Issues

### "Package not found" errors
Make sure you're using the interactive image or have activated the PlanarInteractive project:
```julia
using Pkg; Pkg.activate("PlanarInteractive")
```

### Plotting doesn't work
Ensure you have a plotting backend loaded:
```julia
using WGLMakie  # for web-based plots
# or
using GLMakie   # for native desktop plots
```

### No data downloaded
Check your internet connection and exchange availability:
```julia
# Test exchange connection
exchange_info(:binance)
```

### Strategy fails to start
Verify your data is loaded correctly:
```julia
# Check if data exists
ai = first(s.universe.assets)
println("Data points: $(length(ai.data.timestamp))")
```

## What's Next?

You've successfully run your first Planar strategy! The QuickStart strategy you just used demonstrates the core concepts, but Planar is capable of much more sophisticated strategies.

In the next guides, you'll learn how to:
- Set up a complete development environment
- Create your own custom strategies
- Use advanced features like optimization and multi-timeframe analysis
- Deploy strategies for paper trading and live trading

Ready to dive deeper? Continue with the [Installation Guide](installation.md)!