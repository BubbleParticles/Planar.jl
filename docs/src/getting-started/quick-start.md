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
# Load Planar with all features
using PlanarInteractive

# Initialize the environment
@environment!
```

**Expected output**: You'll see modules loading. First run takes ~60 seconds.

**✅ Success indicator**: No red error messages, ends with a clean `julia>` prompt.

**⚠️ Seeing errors?** Check [Installation Issues](../troubleshooting/installation-issues.md) for dependency and setup problems.

## Step 3: Create Your First Strategy (1 minute)

```julia
# Load the built-in demo strategy
s = strategy(:QuickStart, exchange.md)=:binance)

# Verify it loaded correctly
println("Strategy: $(s.config.name)")
println("Exchange: $(s.config.exchange.md))")
println("Asset: $(first(s.universe.assets).asset)")
```

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
fetch_ohlcv(s, from=-500)  # Last 500 candles (~8 hours of 1-minute data)

# Load data into the strategy
load_ohlcv(s)

# Verify data loaded
ai = first(s.universe.assets)
println("Downloaded $(length(ai.data.timestamp)) data points")
println("From: $(ai.data.timestamp[1])")
println("To: $(ai.data.timestamp[end])")
```

**Expected output**: Should show ~500 data points with recent timestamps.

**✅ Success indicator**: No errors, timestamps are recent (within last day).

**⚠️ Data fetch failing?** See [Exchange Issues](../troubleshooting/exchange-issues.md) for connectivity and API problems.

## Step 5: Run Your First Backtest (1 minute)

```julia
# Execute the trading strategy on historical data
start!(s)

# Check the results immediately
initial_balance = s.config.cash
final_balance = cash(s)
profit_loss = final_balance - initial_balance
return_pct = (profit_loss / initial_balance) * 100

println("🏦 Initial balance: $(initial_balance)")
println("💰 Final balance: $(round(final_balance, digits=2))")
println("📈 Profit/Loss: $(round(profit_loss, digits=2)) ($(round(return_pct, digits=2))%)")
println("🔄 Number of trades: $(length(s.history.trades))")
```

**Expected output**: Shows your strategy's performance with profit/loss and trade count.

**✅ Success indicator**: No errors, shows realistic balance changes and some trades executed.

## Step 6: Visualize Results (3 minutes)

```julia
# Load plotting system
using WGLMakie  # Web-based interactive plots

# Create the main visualization
balloons(s)
```

**What you'll see**: An interactive chart with:
- 📊 Bitcoin price candlesticks
- 🟢 Green balloons = Buy signals  
- 🔴 Red balloons = Sell signals
- 📈 Balance line showing profit/loss over time

**✅ Success indicator**: A chart opens in your browser showing price data with colored trade markers.

**⚠️ Plotting not working?** See [Installation Issues](../troubleshooting/installation-issues.md#plotting-backend-issues) for plotting setup solutions. Your backtest still worked!

## Step 7: Analyze Performance (3 minutes)

```julia
# Quick performance summary
trades = s.history.trades
if !isempty(trades)
    winning_trades = count(t -> t.pnl > 0, trades)
    win_rate = winning_trades / length(trades) * 100
    
    println("📊 PERFORMANCE SUMMARY")
    println("Win Rate: $(round(win_rate, digits=1))%")
    println("Total Trades: $(length(trades))")
    
    # Show last few trades
    println("\n🔄 RECENT TRADES:")
    for trade in trades[max(1, end-2):end]
        side_emoji = trade.side == "buy" ? "🟢" : "🔴"
        pnl_emoji = trade.pnl > 0 ? "💚" : "❤️"
        println("$side_emoji $(trade.side) at \$(round(trade.price, digits=2)) $pnl_emoji P&L: \$(round(trade.pnl, digits=2))")
    end
else
    println("ℹ️  No trades executed - try different [market data](../guides/data-management.md) or strategy parameters")
end
```

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
- **[Strategy Development](guides/strategy-development.md)** - Complete strategy development guide

## Next Steps

Now that you have Planar running:

1. **[Complete Installation](installation.md)** - Set up a proper development environment
2. **[Build Your First Strategy](first-strategy.md)** - Learn to create custom trading logic
3. **[Explore Examples](../strategy.md#examples)** - Study more complex strategy patterns
4. **[Learn About Data](../data.md)** - Understand Planar's [data management](../guides/data-management.md) capabilities

## Quick Troubleshooting

**❌ "Package not found" errors** → [Installation Issues](../troubleshooting/installation-issues.md#dependency-conflicts)
```julia
# Ensure correct project is active
using Pkg; Pkg.activate("PlanarInteractive")
```

**❌ Plotting doesn't work** → [Installation Issues](../troubleshooting/installation-issues.md#plotting-backend-issues)
- Skip plotting for now - your backtest still worked!
- Try: `using GLMakie` instead of `WGLMakie`

**❌ No data downloaded** → [Exchange Issues](../troubleshooting/exchange-issues.md#network-connectivity-problems)
```julia
# Test internet connection
fetch_ohlcv(s, from=-10)  # Try smaller download
```

**❌ No trades executed** → [Strategy Problems](../troubleshooting/strategy-problems.md#signal-generation-problems)
```julia
# Check data loaded
ai = first(s.universe.assets)
println("Data points: $(length(ai.data.timestamp))")
# Try different time period: fetch_ohlcv(s, from=-2000)
```

**❌ Docker issues** → [Installation Issues](../troubleshooting/installation-issues.md#docker-installation-issues)
```bash
# Restart Docker and try again
docker system prune
docker run -it --rm docker.io/psydyllic/planar-sysimage-interactive julia
```

**Need more help?** Visit the [Troubleshooting Guide](../troubleshooting/) for comprehensive solutions.

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
- **[Parameter Optimization](../guides/strategy-development.md).md)** - Systematically improve your strategies  
- **[Paper Trading](../engine/paper.md)** - Test with live market data
- **[Live Trading](../engine/live.md)** - Deploy for real money (when you're ready!)

## Keep Experimenting!

Try modifying the QuickStart strategy:
```julia
# Try different assets
s2 = strategy(:QuickStart, exchange.md)=:binance, asset="ETH/USDT")

# Try different time periods  
fetch_ohlcv(s2, from=-2000)  # More data
load_ohlcv(s2)
start!(s2)
```

**Ready to build your own strategy?** Continue with [First Strategy Tutorial](first-strategy.md)!