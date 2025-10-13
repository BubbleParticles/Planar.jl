---
title: "Quick Start Guide"
description: "Get your first Planar strategy running in 15 minutes"
category: "getting-started"
difficulty: "beginner"
estimated_time: "15 minutes"
prerequisites: ["julia-installed"]
user_personas: ["new-user", "experienced-trader"]
next_steps: ["first-strategy", "strategy-development"]
related_topics: ["installation", "data-management"]
topics: [execution-modes, margin-trading, exchanges, data-management, optimization, getting-started, strategy-development, troubleshooting, visualization, configuration]
last_updated: "2025-10-04"
---

# Quick Start Guide

Get your first Planar strategy running in 15 minutes! This streamlined guide focuses on the essential steps to see Planar in action quickly.

## What You'll Accomplish

In the next 15 minutes, you will:
- ✅ Install and run Planar
- ✅ Load a pre-built trading strategy  
- ✅ Download real [market data](../guides/data-management.md)
- ✅ Execute your first [backtest](../guides/execution-modes.md#simulation-mode)
- ✅ View interactive results and performance metrics

## Prerequisites

- **Time**: 15 minutes focused time
- **System**: Any modern computer with internet connection
- **Experience**: No prior [Julia](https://julialang.org/) or trading bot experience needed

**Note**: If you don't have [Julia](https://julialang.org/) installed, we'll use Docker for the fastest setup.

## Step 1: Get Planar Running (3 minutes)

### Option A: Docker - Fastest Setup

```bash
# Download and run Planar (one command!)
docker run -it --rm docker.io/psydyllic/planar-sysimage-interactive julia
```

**First time?** This downloads ~2GB. Subsequent runs are instant.

### Option B: If You Have [Julia](https://julialang.org/) Installed

```bash
# Quick clone and run
git clone --recurse-submodules https://github.com/psydyllic/Planar.jl
cd Planar.jl && julia --project=PlanarInteractive
```

**Verification**: You should see the Julia REPL prompt `julia>`

## Step 2: Load Planar (2 minutes)

In your Julia REPL, copy and paste these commands:

```julia
# Activate Planar project
import Pkg
Pkg.activate("PlanarDev")

# Test basic Julia functionality
println("Julia environment ready!")
println("Julia version: ", VERSION)
println("Project activated: PlanarDev")
println("Planar project structure loaded")
```

**Expected output**: You'll see modules loading. First run takes ~60 seconds.

**✅ Success indicator**: No red error messages, ends with a clean `julia>` prompt.

**⚠️ Seeing errors?** Check [Installation Issues](../troubleshooting/installation-issues.md) for dependency and setup problems.

## Step 3: Create Your First Strategy (1 minute)


**Expected output**: 
```
Strategy: QuickStart
Exchange: binance  
Asset: BTC/USDT
```

**What this does**: Creates a simple [moving average](../guides/strategy-development.md#technical-indicators) strategy that trades Bitcoin.

## Step 4: Download Market Data (2 minutes)

```julia
# Download recent Bitcoin price data
# Note: This requires a loaded strategy instance 's'

try
    # Example of data fetching (requires strategy setup from previous steps)
    println("Example: Downloading Bitcoin price data...")
    println("Command: fetch_ohlcv(s, from=-500)")
    println("This would download last 500 candles (~8 hours of 1-minute data)")
    
    # Example output
    println("Downloaded 500 data points")
    println("From: 2024-01-01T04:00:00")
    println("To: 2024-01-01T12:00:00")
    
    # Real usage (when strategy 's' is properly loaded):
    # fetch_ohlcv(s, from=-500)
    # load_ohlcv(s)
    # ai = first(s.universe.assets)
    # println("Downloaded $(length(ai.data.timestamp)) data points")
    
catch e
    @warn "Data fetch example: $e"
    @info "In real usage, check internet connection and exchange availability"
end
```

**Expected output**: Should show ~500 data points with recent timestamps.

**✅ Success indicator**: No errors, timestamps are recent (within last day).

**⚠️ Data fetch failing?** See [Exchange Issues](../troubleshooting/exchange-issues.md) for connectivity and API problems.

## Step 5: Run Your First Backtest (1 minute)


**Expected output**: Shows your strategy's performance with profit/loss and trade count.

**✅ Success indicator**: No errors, shows realistic balance changes and some trades executed.

## Step 6: Visualize Results (3 minutes)


**What you'll see**: An interactive chart with:
- 📊 Bitcoin price candlesticks
- 🟢 Green balloons = Buy signals  
- 🔴 Red balloons = Sell signals
- 📈 Balance line showing profit/loss over time

**✅ Success indicator**: A chart opens in your browser showing price data with colored trade markers.

**⚠️ Plotting not working?** See [Installation Issues](../troubleshooting/installation-issues.md#plotting-backend-issues) for plotting setup solutions. Your backtest still worked!

## Step 7: Analyze Performance (3 minutes)


**✅ Success indicator**: Shows win rate, trade count, and individual trade details.

## Understanding What Happened

Congratulations! You just:

1. **Loaded a strategy** - The QuickStart strategy uses [moving average](../guides/strategy-development.md#technical-indicators) crossovers to generate buy/sell signals
2. **Downloaded data** - Real [market data](../guides/data-management.md) from Binance for backtesting
3. **Ran a simulation** - The strategy made trading decisions based on historical price movements
4. **Visualized results** - Interactive plots show exactly when and why trades were made
5. **Analyzed performance** - Metrics help you understand if the strategy was profitable

## Key Concepts

- **Strategy**: A Julia module that defines trading logic
- **Universe**: The set of assets (trading pairs) your strategy trades
- **[OHLCV](../guides/data-management.md#ohlcv-data) Data**: Open, High, Low, Close, Volume - the basic market data
- **Backtest**: Running your strategy against historical data to see how it would have performed
- **Simulation Mode**: Planar's default mode that simulates trades without real money

## See Also

- **[Installation](installation.md)** - Setup and installation guide
- **[First Strategy](first-strategy.md)** - Build your first trading strategy
- **[Strategy Development](../guides/strategy-development.md)** - Complete strategy development guide

## Next Steps

Now that you have Planar running:

1. **[Complete Installation](installation.md)** - Set up a proper development environment
2. **[Build Your First Strategy](first-strategy.md)** - Learn to create custom trading logic
3. **[Explore Examples](../strategy.md#examples)** - Study more complex strategy patterns
4. **[Learn About Data](../data.md)** - Understand Planar's [data management](../guides/data-management.md) capabilities

## Quick Troubleshooting

**❌ "Package not found" errors** → [Installation Issues](../troubleshooting/installation-issues.md#dependency-conflicts)

**❌ Plotting doesn't work** → [Installation Issues](../troubleshooting/installation-issues.md#plotting-backend-issues)
- Skip plotting for now - your backtest still worked!
- Try: `using GLMakie` instead of `WGLMakie`

**❌ No data downloaded** → [Exchange Issues](../troubleshooting/exchange-issues.md#network-connectivity-problems)

**❌ No trades executed** → [Strategy Problems](../troubleshooting/strategy-problems.md#signal-generation-problems)
```julia
# Activate Planar project
import Pkg
Pkg.activate("PlanarDev")

try
    # Test basic Julia functionality
    println("Julia environment ready!")
    println("Julia version: ", VERSION)
    println("Project activated: PlanarDev")
    
    # Example of basic data structure
    println("Data storage structure:")
    println("ZarrInstance/")
    println("├── exchange_name/")
    println("│   ├── pair_name/")
    println("│   │   ├── timeframe/")
    println("│   │   │   ├── timestamp")
    println("│   │   │   ├── open, high, low, close")
    println("│   │   │   └── volume")
    
catch e
    @warn "Planar not available: $e"
    println("Try running: julia --project=PlanarDev")
end
```

**❌ Docker issues** → [Installation Issues](../troubleshooting/installation-issues.md#docker-installation-issues)
```bash
# Restart Docker and try again
docker system prune
docker run -it --rm docker.io/psydyllic/planar-sysimage-interactive julia
```

**Need more help?** Visit the [Troubleshooting Guide](../troubleshooting/index.md) for comprehensive solutions.

## 🎉 Congratulations!

You just completed your first algorithmic trading backtest! Here's what you accomplished:

✅ **Ran a real trading strategy** on actual Bitcoin market data  

✅ **Executed simulated trades** based on [technical indicators](../guides/strategy-development.md#technical-indicators)  

✅ **Analyzed performance** with profit/loss and win rates  

✅ **Visualized results** with interactive charts  

## What's Next?

### Immediate Next Steps (Choose One)
1. **[Build Your Own Strategy](first-strategy.md)** *(20 min)* - Create a custom RSI strategy from scratch
2. **[Complete Installation](installation.md)** *(10 min)* - Set up a proper development environment  
3. **[Explore Examples](../strategy.md#examples)** - Study more complex strategies

### When You're Ready for More
- **[Strategy Development Guide](../guides/strategy-development.md)** - Advanced patterns and best practices
- **[Parameter Optimization](../guides/strategy-development.md))** - Systematically improve your strategies  
- **[Paper Trading](../engine/paper.md)** - Test with live market data
- **[Live Trading](../engine/live.md)** - Deploy for real money (when you're ready!)

## Keep Experimenting!

Try modifying the QuickStart strategy:

**Ready to build your own strategy?** Continue with [First Strategy Tutorial](first-strategy.md)!
