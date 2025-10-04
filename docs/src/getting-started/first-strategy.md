---
title: "Your First Strategy Tutorial"
description: "Build a custom RSI trading strategy from scratch"
category: "getting-started"
difficulty: "beginner"
estimated_time: "20 minutes"
prerequisites: ["quick-start", "julia-basics"]
user_personas: ["new-user", "strategy-developer"]
next_steps: ["strategy-development", "data-management", "optimization"]
related_topics: ["technical-indicators", "backtesting", "performance-analysis"]
topics: [execution-modes, exchanges, data-management, optimization, getting-started, strategy-development, troubleshooting, visualization, configuration]
last_updated: "2025-10-04"---
completion_rate: "92%"
---

# Your First Strategy Tutorial

In this tutorial, you'll learn to create a custom trading strategy from scratch. We'll build a simple RSI-development.md#technical-indicators) (Relative Strength Index) mean reversion strategy that demonstrates all the key concepts of Planar strategy development.

## What You'll Learn

By the end of this tutorial, you'll understand:

- How Planar strategies are structured
- The three core functions every strategy needs
- How to add [technical indicators](../guides/strategy-development.md#technical-indicators)
- How to implement buy/sell logic
- How to test and debug your strategy
- How to analyze performance results

## Prerequisites

- Completed the [Quick Start Guide](quick-start.md)
- Basic understanding of technical analysis (RSI, moving averages)
- Planar installed and working

## Strategy Overview

We'll create a strategy that:
1. Uses RSI to identify oversold/overbought conditions
2. Adds a trend filter using moving averages
3. Only trades when conditions align
4. Includes proper risk management

## Step 1: Understanding Strategy Structure

Every Planar strategy is a [Julia](https://julialang.org/) module with three core functions:

```julia
function setsignals!(s)
    # Initialize indicators - called once at startup
end

function isbuy(s::SC, ai, ats)
    # Buy signal logic - called every polling cycle
    # Return true when buy conditions are met
end

function issell(s::SC, ai, ats)
    # Sell signal logic - called every polling cycle  
    # Return true when sell conditions are met
end
```

### Function Parameters

- **`s::SC`**: Strategy instance (SC = Strategy Container)
- **`ai`**: Asset instance (the trading pair, e.g., BTC/USDT)
- **`ats`**: Available timestamp for signal evaluation

## Step 2: Create Strategy Directory

First, let's create a new strategy directory:

```bash
# Navigate to user strategies directory
cd user/strategies

# Create our new strategy
mkdir MyFirstStrategy
cd MyFirstStrategy

# Create the basic structure
mkdir src
touch Project.toml
touch src/MyFirstStrategy.jl
```

## Step 3: Define the Strategy Module

Edit `src/MyFirstStrategy.jl`:

```julia
module MyFirstStrategy

# Import required modules
using Planar
using Planar.Strategies
using Planar.Data: ohlcv, dateindex
using OnlineTechnicalIndicators as oti

# Strategy type - this must match your module name
const SC = Strategy{:MyFirstStrategy}

# Export the main functions
export setsignals!, isbuy, issell

# We'll implement these functions next...

end # module
```

## Step 4: Implement Signal Setup

Add the `setsignals!` function to initialize our indicators:

```julia
function setsignals!(s)
    attrs = s.attrs
    attrs[:signals_set] = false  # Required initialization
    
    # Define our indicators
    sigdefs = attrs[:signals_def] = signals(
        # RSI for momentum
        :rsi => (; type=oti.RSI{DFT}, tf=tf"1m", params=(; period=14)),
        
        # Moving averages for trend
        :sma_short => (; type=oti.SMA{DFT}, tf=tf"1m", params=(; period=10)),
        :sma_long => (; type=oti.SMA{DFT}, tf=tf"1m", params=(; period=20)),
    )
    
    # Initialize trend tracking (required)
    inittrends!(s, keys(sigdefs.defs))
    
    # Store strategy parameters
    attrs[:rsi_oversold] = 30.0
    attrs[:rsi_overbought] = 70.0
    attrs[:min_trend_strength] = 0.005  # 0.5% minimum trend
end
```

### Key Points:

- **`attrs[:signals_set] = false`**: Required initialization
- **`signals(...)`**: Defines which indicators to calculate
- **`tf"1m"`**: Uses 1-minute timeframe data
- **`inittrends!(...)`**: Required to initialize the indicators
- **Strategy parameters**: Store configuration in `attrs` for easy modification

## Step 5: Implement Buy Logic

Add the `isbuy` function:

```julia
function isbuy(s::SC, ai, ats)
    # Get indicator values
    rsi = signal_value(s, ai, :rsi, ats)
    sma_short = signal_value(s, ai, :sma_short, ats)
    sma_long = signal_value(s, ai, :sma_long, ats)
    
    # Validate signals (CRITICAL!)
    if isnothing(rsi) || isnothing(sma_short) || isnothing(sma_long)
        return false
    end
    
    # Get strategy parameters
    params = s.attrs
    
    # Buy conditions:
    # 1. RSI indicates oversold condition
    rsi_oversold = rsi < params[:rsi_oversold]
    
    # 2. Trend filter: short MA above long MA
    uptrend = sma_short > sma_long
    
    # 3. Trend strength: require minimum difference
    trend_strength = (sma_short - sma_long) / sma_long
    strong_trend = trend_strength > params[:min_trend_strength]
    
    # All conditions must be true
    buy_signal = rsi_oversold && uptrend && strong_trend
    
    # Optional: Add logging for debugging
    @ldebug 1 "Buy analysis" ai ats rsi rsi_oversold uptrend strong_trend buy_signal
    
    return buy_signal
end
```

### Key Points:

- **Always validate signals**: Check for `nothing` before using values
- **Multiple conditions**: Combine different indicators for better signals
- **Logging**: Use `@ldebug` for debugging (won't show in production)

## Step 6: Implement Sell Logic

Add the `issell` function:

```julia
function issell(s::SC, ai, ats)
    # Get indicator values
    rsi = signal_value(s, ai, :rsi, ats)
    sma_short = signal_value(s, ai, :sma_short, ats)
    sma_long = signal_value(s, ai, :sma_long, ats)
    
    # Validate signals
    if isnothing(rsi) || isnothing(sma_short) || isnothing(sma_long)
        return false
    end
    
    # Get strategy parameters
    params = s.attrs
    
    # Sell conditions (any can trigger):
    # 1. RSI indicates overbought condition
    rsi_overbought = rsi > params[:rsi_overbought]
    
    # 2. Trend reversal: short MA below long MA
    downtrend = sma_short < sma_long
    
    # Sell if either condition is met
    sell_signal = rsi_overbought || downtrend
    
    # Optional: Add logging for debugging
    @ldebug 1 "Sell analysis" ai ats rsi rsi_overbought downtrend sell_signal
    
    return sell_signal
end
```

## Step 7: Create Project Configuration

Edit `Project.toml`:

```toml
name = "MyFirstStrategy"
uuid = "12345678-1234-1234-1234-123456789abc"  # Generate a unique UUID
version = "0.1.0"

[deps]
Planar = "..."
OnlineTechnicalIndicators = "..."

[compat]
julia = "1.11"
```

## Step 8: Complete Strategy File

Here's your complete `src/MyFirstStrategy.jl`:

```julia
module MyFirstStrategy

using Planar
using Planar.Strategies
using Planar.Data: ohlcv, dateindex
using OnlineTechnicalIndicators as oti

const SC = Strategy{:MyFirstStrategy}

export setsignals!, isbuy, issell

function setsignals!(s)
    attrs = s.attrs
    attrs[:signals_set] = false
    
    sigdefs = attrs[:signals_def] = signals(
        :rsi => (; type=oti.RSI{DFT}, tf=tf"1m", params=(; period=14)),
        :sma_short => (; type=oti.SMA{DFT}, tf=tf"1m", params=(; period=10)),
        :sma_long => (; type=oti.SMA{DFT}, tf=tf"1m", params=(; period=20)),
    )
    
    inittrends!(s, keys(sigdefs.defs))
    
    attrs[:rsi_oversold] = 30.0
    attrs[:rsi_overbought] = 70.0
    attrs[:min_trend_strength] = 0.005
end

function isbuy(s::SC, ai, ats)
    rsi = signal_value(s, ai, :rsi, ats)
    sma_short = signal_value(s, ai, :sma_short, ats)
    sma_long = signal_value(s, ai, :sma_long, ats)
    
    if isnothing(rsi) || isnothing(sma_short) || isnothing(sma_long)
        return false
    end
    
    params = s.attrs
    rsi_oversold = rsi < params[:rsi_oversold]
    uptrend = sma_short > sma_long
    trend_strength = (sma_short - sma_long) / sma_long
    strong_trend = trend_strength > params[:min_trend_strength]
    
    buy_signal = rsi_oversold && uptrend && strong_trend
    
    @ldebug 1 "Buy analysis" ai ats rsi rsi_oversold uptrend strong_trend buy_signal
    
    return buy_signal
end

function issell(s::SC, ai, ats)
    rsi = signal_value(s, ai, :rsi, ats)
    sma_short = signal_value(s, ai, :sma_short, ats)
    sma_long = signal_value(s, ai, :sma_long, ats)
    
    if isnothing(rsi) || isnothing(sma_short) || isnothing(sma_long)
        return false
    end
    
    params = s.attrs
    rsi_overbought = rsi > params[:rsi_overbought]
    downtrend = sma_short < sma_long
    
    sell_signal = rsi_overbought || downtrend
    
    @ldebug 1 "Sell analysis" ai ats rsi rsi_overbought downtrend sell_signal
    
    return sell_signal
end

end # module
```

## Step 9: Test Your Strategy

Now let's test the strategy:

```julia
# Start [Julia](https://julialang.org/) in the Planar directory
using PlanarInteractive
@environment!

# Load your strategy
push!(LOAD_PATH, "user/strategies/MyFirstStrategy/src")
using MyFirstStrategy

# Create strategy instance
s = strategy(:MyFirstStrategy, exchange.md)=:binance, asset="BTC/USDT")

# Download some data
fetch_ohlcv(s, from=-1000)
load_ohlcv(s)

# Run [backtest](../guides/execution-modes.md#simulation-mode)
start!(s)

# Check results
println("Final balance: $(cash(s))")
println("Number of trades: $(length(s.history.trades))")
```

## Step 10: Comprehensive Performance Analysis

### Basic Performance Metrics

```julia
# Load plotting for visualization
using Plotting
using WGLMakie

# Create the main visualization
balloons(s)

# Calculate key performance metrics
initial_balance = s.config.cash
final_balance = cash(s)
total_return = (final_balance - initial_balance) / initial_balance * 100

println("📊 PERFORMANCE SUMMARY")
println("=" ^ 40)
println("Initial Balance: \$(initial_balance)")
println("Final Balance: \$(round(final_balance, digits=2))")
println("Total Return: $(round(total_return, digits=2))%")
println("Absolute Profit: \$(round(final_balance - initial_balance, digits=2))")
```

### Trade Analysis

```julia
trades = s.history.trades

if !isempty(trades)
    # Basic trade statistics
    total_trades = length(trades)
    winning_trades = count(t -> t.pnl > 0, trades)
    losing_trades = count(t -> t.pnl < 0, trades)
    win_rate = winning_trades / total_trades * 100
    
    println("\n🔄 TRADE ANALYSIS")
    println("=" ^ 40)
    println("Total Trades: $total_trades")
    println("Winning Trades: $winning_trades")
    println("Losing Trades: $losing_trades")
    println("Win Rate: $(round(win_rate, digits=1))%")
    
    # Profit/Loss analysis
    winning_pnls = [t.pnl for t in trades if t.pnl > 0]
    losing_pnls = [t.pnl for t in trades if t.pnl < 0]
    
    if !isempty(winning_pnls)
        avg_win = mean(winning_pnls)
        max_win = maximum(winning_pnls)
        println("Average Win: \$(round(avg_win, digits=2))")
        println("Largest Win: \$(round(max_win, digits=2))")
    end
    
    if !isempty(losing_pnls)
        avg_loss = mean(losing_pnls)
        max_loss = minimum(losing_pnls)  # Most negative
        println("Average Loss: \$(round(avg_loss, digits=2))")
        println("Largest Loss: \$(round(max_loss, digits=2))")
        
        # Risk-reward ratio
        if !isempty(winning_pnls)
            risk_reward = abs(mean(winning_pnls) / mean(losing_pnls))
            println("Risk/Reward Ratio: $(round(risk_reward, digits=2)):1")
        end
    end
    
    # Show recent trades
    println("\n📋 RECENT TRADES")
    println("=" ^ 40)
    recent_trades = trades[max(1, end-4):end]
    for (i, trade) in enumerate(recent_trades)
        side_emoji = trade.side == "buy" ? "🟢" : "🔴"
        pnl_emoji = trade.pnl > 0 ? "💚" : (trade.pnl < 0 ? "❤️" : "💛")
        println("$i. $side_emoji $(trade.side) at \$(round(trade.price, digits=2)) $pnl_emoji P&L: \$(round(trade.pnl, digits=2))")
    end
else
    println("\n⚠️  No trades executed")
    println("This could mean:")
    println("- Market conditions didn't meet your strategy criteria")
    println("- Strategy parameters are too restrictive")
    println("- Not enough data for indicators to initialize")
end
```

### Advanced Performance Metrics

```julia
# Calculate additional metrics if we have trades
if !isempty(trades)
    # Drawdown analysis
    balance_history = []
    running_balance = initial_balance
    
    for trade in trades
        running_balance += trade.pnl
        push!(balance_history, running_balance)
    end
    
    if length(balance_history) > 1
        # Calculate maximum drawdown
        peak = balance_history[1]
        max_drawdown = 0.0
        
        for balance in balance_history
            if balance > peak
                peak = balance
            else
                drawdown = (peak - balance) / peak
                max_drawdown = max(max_drawdown, drawdown)
            end
        end
        
        println("\n📉 RISK ANALYSIS")
        println("=" ^ 40)
        println("Maximum Drawdown: $(round(max_drawdown * 100, digits=2))%")
        
        # Sharpe ratio approximation (simplified)
        if length(balance_history) > 2
            returns = [balance_history[i] / balance_history[i-1] - 1 for i in 2:length(balance_history)]
            if std(returns) > 0
                sharpe_approx = mean(returns) / std(returns) * sqrt(252)  # Annualized
                println("Sharpe Ratio (approx): $(round(sharpe_approx, digits=2))")
            end
        end
    end
    
    # Trading frequency analysis
    if length(trades) >= 2
        ai = first(s.universe.assets)
        total_periods = length(ai.data.timestamp)
        trade_frequency = length(trades) / total_periods * 100
        
        println("\n⏱️  TRADING FREQUENCY")
        println("=" ^ 40)
        println("Trades per 100 periods: $(round(trade_frequency, digits=1))")
        
        # Time between trades
        buy_trades = filter(t -> t.side == "buy", trades)
        if length(buy_trades) > 1
            time_diffs = [buy_trades[i].timestamp - buy_trades[i-1].timestamp for i in 2:length(buy_trades)]
            avg_time_between = mean(time_diffs)
            println("Average time between entries: $(round(avg_time_between, digits=1)) periods")
        end
    end
end
```

### Strategy Effectiveness Assessment

```julia
# Compare against buy-and-hold
ai = first(s.universe.assets)
start_price = ai.data.close[1]
end_price = ai.data.close[end]
buy_hold_return = (end_price - start_price) / start_price * 100

println("\n🏆 STRATEGY vs BUY & HOLD")
println("=" ^ 40)
println("Strategy Return: $(round(total_return, digits=2))%")
println("Buy & Hold Return: $(round(buy_hold_return, digits=2))%")
println("Excess Return: $(round(total_return - buy_hold_return, digits=2))%")

if total_return > buy_hold_return
    println("✅ Strategy outperformed buy & hold!")
else
    println("❌ Strategy underperformed buy & hold")
    println("💡 Consider: parameter tuning, different indicators, or market timing")
end

# Overall assessment
println("\n🎯 STRATEGY ASSESSMENT")
println("=" ^ 40)

assessment_score = 0
feedback = []

# Profitability check
if total_return > 0
    assessment_score += 25
    push!(feedback, "✅ Profitable strategy")
else
    push!(feedback, "❌ Strategy lost money")
end

# Win rate check
if !isempty(trades)
    win_rate = count(t -> t.pnl > 0, trades) / length(trades) * 100
    if win_rate > 50
        assessment_score += 25
        push!(feedback, "✅ Good win rate (>50%)")
    else
        push!(feedback, "⚠️  Low win rate (<50%)")
    end
    
    # Trade frequency check
    if length(trades) > 5
        assessment_score += 25
        push!(feedback, "✅ Adequate trading activity")
    else
        push!(feedback, "⚠️  Low trading frequency")
    end
    
    # Outperformance check
    if total_return > buy_hold_return
        assessment_score += 25
        push!(feedback, "✅ Outperformed market")
    else
        push!(feedback, "❌ Underperformed market")
    end
else
    push!(feedback, "❌ No trades executed")
end

println("Overall Score: $assessment_score/100")
for fb in feedback
    println(fb)
end

if assessment_score >= 75
    println("\n🌟 Excellent strategy! Consider live testing.")
elseif assessment_score >= 50
    println("\n👍 Good foundation. Try [parameter optimization](../guides/strategy-development.md).md).")
elseif assessment_score >= 25
    println("\n🔧 Needs improvement. Review logic and parameters.")
else
    println("\n🚨 Strategy needs major revision.")
end
```

## Step 11: Debug and Improve Your Strategy

### Enable Detailed Debugging

```julia
# Enable debug logging to see every signal calculation
ENV["JULIA_DEBUG"] = "MyFirstStrategy"

# Clear previous results and run with debugging
reset!(s)
start!(s)
```

**What you'll see**: Detailed logs showing RSI values, trend analysis, and buy/sell decisions for every time step.

### Systematic Debugging Approach

#### 1. Check Indicator Values
```julia
# Manually inspect indicator calculations
ai = first(s.universe.assets)
timestamps = ai.data.timestamp[end-10:end]  # Last 10 data points

for ts in timestamps
    rsi = signal_value(s, ai, :rsi, ts)
    sma_short = signal_value(s, ai, :sma_short, ts)
    sma_long = signal_value(s, ai, :sma_long, ts)
    
    println("$ts: RSI=$rsi, SMA_short=$sma_short, SMA_long=$sma_long")
end
```

#### 2. Test Individual Conditions
```julia
# Test your buy logic step by step
function debug_buy_logic(s, ai, ats)
    rsi = signal_value(s, ai, :rsi, ats)
    sma_short = signal_value(s, ai, :sma_short, ats)
    sma_long = signal_value(s, ai, :sma_long, ats)
    
    println("=== Buy Logic Debug for $ats ===")
    println("RSI: $rsi (oversold if < 30)")
    println("SMA Short: $sma_short")
    println("SMA Long: $sma_long")
    println("Uptrend: $(sma_short > sma_long)")
    
    if !isnothing(rsi) && !isnothing(sma_short) && !isnothing(sma_long)
        trend_strength = (sma_short - sma_long) / sma_long
        println("Trend strength: $(round(trend_strength * 100, digits=2))% (need > 0.5%)")
        
        buy_signal = (rsi < 30) && (sma_short > sma_long) && (trend_strength > 0.005)
        println("BUY SIGNAL: $buy_signal")
    else
        println("❌ Some indicators are null - not enough data")
    end
end

# Test on recent data
debug_buy_logic(s, first(s.universe.assets), ai.data.timestamp[end-5])
```

#### 3. Analyze Strategy Performance Issues

**Problem: No trades executed**
```julia
# Check data sufficiency
ai = first(s.universe.assets)
println("Data points: $(length(ai.data.timestamp))")
println("Need at least 20 points for indicators")

# Check indicator initialization
if length(ai.data.timestamp) < 20
    println("❌ Not enough data - download more")
    fetch_ohlcv(s, from=-1000)
    load_ohlcv(s)
end
```

**Problem: Too many trades (overtrading)**
```julia
# Add trade cooldown
function isbuy(s::SC, ai, ats)
    # ... existing logic ...
    
    # Add cooldown: no new trades within 10 periods
    if haskey(s.attrs, :last_buy_time)
        last_buy = s.attrs[:last_buy_time]
        cooldown_periods = 10
        if ats - last_buy < cooldown_periods
            @ldebug 1 "Cooldown active" ai ats last_buy
            return false
        end
    end
    
    if buy_signal
        s.attrs[:last_buy_time] = ats
    end
    
    return buy_signal
end
```

**Problem: Poor performance**
```julia
# Analyze individual trade performance
trades = s.history.trades
if !isempty(trades)
    # Find worst performing trades
    worst_trades = sort(trades, by=t -> t.pnl)[1:min(3, length(trades))]
    println("Worst trades:")
    for trade in worst_trades
        println("  $(trade.timestamp): $(trade.side) at \$(trade.price), P&L: \$(round(trade.pnl, digits=2))")
    end
    
    # Analyze trade timing
    buy_trades = filter(t -> t.side == "buy", trades)
    sell_trades = filter(t -> t.side == "sell", trades)
    
    if length(buy_trades) > 0 && length(sell_trades) > 0
        avg_hold_time = mean([sell.timestamp - buy.timestamp for (buy, sell) in zip(buy_trades, sell_trades)])
        println("Average holding time: $avg_hold_time periods")
    end
end
```

### Performance Optimization Techniques

#### 1. Parameter Sensitivity Analysis
```julia
# Test different RSI thresholds
function test_rsi_thresholds()
    results = []
    
    for oversold in [25, 30, 35]
        for overbought in [65, 70, 75]
            # Create new strategy with different parameters
            s_test = strategy(:MyFirstStrategy, exchange.md)=:binance, asset="BTC/USDT")
            fetch_ohlcv(s_test, from=-1000)
            load_ohlcv(s_test)
            
            # Modify parameters
            s_test.attrs[:rsi_oversold] = oversold
            s_test.attrs[:rsi_overbought] = overbought
            
            # Run [backtest](../guides/execution-modes.md#simulation-mode)
            start!(s_test)
            
            # Record results
            initial = s_test.config.cash
            final = cash(s_test)
            return_pct = (final - initial) / initial * 100
            
            push!(results, (oversold=oversold, overbought=overbought, return=return_pct, trades=length(s_test.history.trades)))
        end
    end
    
    # Show results
    println("RSI Threshold Analysis:")
    for r in sort(results, by=x -> x.return, rev=true)
        println("Oversold: $(r.oversold), Overbought: $(r.overbought) → Return: $(round(r.return, digits=2))%, Trades: $(r.trades)")
    end
end

test_rsi_thresholds()
```

#### 2. Market Condition Analysis
```julia
# Analyze performance in different market conditions
function analyze_market_conditions(s)
    ai = first(s.universe.assets)
    prices = ai.data.close
    
    # Calculate overall market trend
    start_price = prices[1]
    end_price = prices[end]
    market_return = (end_price - start_price) / start_price * 100
    
    println("Market Analysis:")
    println("Market return: $(round(market_return, digits=2))%")
    
    # Calculate strategy vs market performance
    strategy_return = (cash(s) - s.config.cash) / s.config.cash * 100
    excess_return = strategy_return - market_return
    
    println("Strategy return: $(round(strategy_return, digits=2))%")
    println("Excess return: $(round(excess_return, digits=2))%")
    
    if excess_return > 0
        println("✅ Strategy outperformed the market!")
    else
        println("❌ Strategy underperformed - consider buy-and-hold")
    end
end

analyze_market_conditions(s)
```

## Step 12: Advanced Improvements

### Add Stop Loss

```julia
function issell(s::SC, ai, ats)
    # ... existing logic ...
    
    # Add stop loss
    if hasposition(s, ai)
        entry_price = position_entry_price(s, ai)
        current_price = current_price(ai, ats)
        
        # 2% stop loss
        stop_loss = (entry_price - current_price) / entry_price > 0.02
        
        if stop_loss
            @ldebug 1 "Stop loss triggered" ai ats entry_price current_price
            return true
        end
    end
    
    return sell_signal
end
```

### Add Position Sizing

```julia
function isbuy(s::SC, ai, ats)
    # ... existing buy logic ...
    
    if buy_signal
        # Risk-based position sizing
        account_balance = cash(s)
        risk_per_trade = 0.02  # Risk 2% per trade
        
        # Calculate position size based on ATR or volatility
        # This is a simplified example
        position_size = account_balance * risk_per_trade
        
        # Store position size for order execution
        s.attrs[:position_size] = position_size
    end
    
    return buy_signal
end
```

## Understanding Key Concepts

### Signal Validation
Always check if indicators return valid values:
```julia
if isnothing(rsi) || isnan(rsi) || isinf(rsi)
    return false
end
```

### Timeframes
Indicators can use different [timeframes](../guides/data-management.md#timeframes):
```julia
:rsi_1m => (; type=oti.RSI{DFT}, tf=tf"1m", params=(; period=14)),
:rsi_5m => (; type=oti.RSI{DFT}, tf=tf"5m", params=(; period=14)),
```

### Strategy State
Use `s.attrs` to store strategy-specific data:
```julia
s.attrs[:last_trade_time] = ats
s.attrs[:consecutive_losses] = 0
```


## See Also

- **[Quick Start](getting-started/quick-start.md)** - 15-minute getting started tutorial
- **[Strategy Development](guides/strategy-development.md)** - Complete strategy development guide
- **[Data Management](guides/data-management.md)** - Working with market data

## Next Steps: From Beginner to Advanced

Congratulations! You've built your first custom Planar strategy from scratch. Here's your roadmap to becoming a sophisticated algorithmic trader:

### Immediate Improvements (Next 1-2 Hours)

#### 1. Optimize Your Current Strategy
```julia
# Try different parameter combinations
test_parameters = [
    (rsi_oversold=25, rsi_overbought=75, trend_strength=0.01),
    (rsi_oversold=35, rsi_overbought=65, trend_strength=0.005),
    (rsi_oversold=30, rsi_overbought=70, trend_strength=0.02)
]

best_return = -Inf
best_params = nothing

for params in test_parameters
    s_test = strategy(:MyFirstStrategy, exchange.md)=:binance, asset="BTC/USDT")
    fetch_ohlcv(s_test, from=-1000)
    load_ohlcv(s_test)
    
    # Apply parameters
    s_test.attrs[:rsi_oversold] = params.rsi_oversold
    s_test.attrs[:rsi_overbought] = params.rsi_overbought
    s_test.attrs[:min_trend_strength] = params.trend_strength
    
    start!(s_test)
    
    return_pct = (cash(s_test) - s_test.config.cash) / s_test.config.cash * 100
    println("Params: $params → Return: $(round(return_pct, digits=2))%")
    
    if return_pct > best_return
        best_return = return_pct
        best_params = params
    end
end

println("Best parameters: $best_params with $(round(best_return, digits=2))% return")
```

#### 2. Test Different Assets
```julia
# Test your strategy on different cryptocurrencies
assets_to_test = ["ETH/USDT", "ADA/USDT", "SOL/USDT", "MATIC/USDT"]

for asset in assets_to_test
    s_test = strategy(:MyFirstStrategy, exchange=:binance, asset=asset)
    try
        fetch_ohlcv(s_test, from=-1000)
        load_ohlcv(s_test)
        start!(s_test)
        
        return_pct = (cash(s_test) - s_test.config.cash) / s_test.config.cash * 100
        trades = length(s_test.history.trades)
        println("$asset: $(round(return_pct, digits=2))% return, $trades trades")
    catch e
        println("$asset: Failed - $e")
    end
end
```

#### 3. Add Risk Management
```julia
# Enhance your strategy with stop-loss and take-profit
function issell(s::SC, ai, ats)
    # ... existing sell logic ...
    
    # Add risk management
    if hasposition(s, ai)
        entry_price = position_entry_price(s, ai)
        current_price = current_price(ai, ats)
        
        # 3% stop loss
        stop_loss_triggered = (entry_price - current_price) / entry_price > 0.03
        
        # 6% take profit (2:1 risk/reward)
        take_profit_triggered = (current_price - entry_price) / entry_price > 0.06
        
        if stop_loss_triggered
            @ldebug 1 "Stop loss triggered" ai ats entry_price current_price
            return true
        end
        
        if take_profit_triggered
            @ldebug 1 "Take profit triggered" ai ats entry_price current_price
            return true
        end
    end
    
    return sell_signal
end
```

### Short-term Learning (Next Week)

#### 1. **[Strategy Development Guide](../guides/strategy-development.md)**
Learn advanced patterns:
- Multi-timeframe analysis
- Portfolio strategies
- Advanced indicators
- Risk management systems

#### 2. **[Parameter Optimization](../guides/strategy-development.md).md)**
Systematic improvement:
- Grid search [optimization](../optimization.md)
- Genetic algorithms
- Walk-forward analysis
- Overfitting prevention

#### 3. **[Data Management](../data.md)**
Master Planar's data system:
- Multiple data sources
- Custom data feeds
- Data quality checks
- Historical [data management](../guides/data-management.md)

### Medium-term Goals (Next Month)

#### 1. **[Paper Trading](../engine/paper.md)**
Test with live data:
- Real-time market simulation
- Order book dynamics
- Slippage and fees
- Performance monitoring

#### 2. **[Multi-Exchange Trading](../advanced/multi-exchange.md)**
Scale your operations:
- Arbitrage opportunities
- Risk diversification
- Exchange-specific features
- Portfolio management

#### 3. **[Custom Indicators](../customizations/indicators.md)**
Build proprietary signals:
- Custom [technical indicators](../guides/strategy-development.md#technical-indicators)
- Machine learning integration
- Alternative data sources
- Signal combination techniques

### Advanced Mastery (Next 3 Months)

#### 1. **[Live Trading](../engine/live.md)**
Deploy for real money:
- Risk management protocols
- Position sizing algorithms
- Emergency stop procedures
- Performance monitoring

#### 2. **[Optimization at Scale](../advanced/optimization.md)**
Professional-grade optimization:
- Cloud computing integration
- Parallel backtesting
- Statistical significance testing
- Production deployment

#### 3. **[Custom Exchange Integration](../customizations/exchanges.md)**
Expand your reach:
- New exchange APIs
- Custom order types
- Specialized markets
- Institutional features

## Learning Resources by Experience Level

### 📚 Beginner Resources
- **[Strategy Examples](../strategy.md#examples)** - Study proven patterns
- **[Common Patterns](../guides/common-patterns.md)** - Reusable strategy components
- **[Troubleshooting Guide](../troubleshooting/index.md).md)** - Solve common issues

### 🔬 Intermediate Resources
- **[Advanced Indicators](../reference/indicators.md)** - Technical analysis deep dive
- **[Backtesting Best Practices](../guides/strategy-development.md).md)** - Avoid common pitfalls
- **[Performance Analysis](../guides/performance.md)** - Professional metrics

### 🚀 Advanced Resources
- **[API Reference](../reference/api/)** - Complete function documentation
- **[Architecture Guide](../advanced/architecture.md)** - Understand Planar internals
- **[Contributing Guide](../resources/contributing.md)** - Extend Planar itself

## Community and Support

- **[Discord Community](../contacts.md#discord)** - Get help from other traders
- **[GitHub Discussions](../contacts.md#github)** - Technical questions and feature requests
- **[Example Strategies Repository](../contacts.md#examples)** - Community-contributed strategies

## Your Strategy Development Checklist

Track your progress as you advance:

### ✅ Beginner Level (You are here!)
- [x] Built first custom strategy
- [x] Understand buy/sell logic
- [x] Can run backtests
- [x] Interpret basic performance metrics
- [ ] Optimize parameters manually
- [ ] Test multiple assets
- [ ] Add basic risk management

### 🎯 Intermediate Level
- [ ] Use systematic [parameter optimization](../optimization.md)
- [ ] Implement multi-timeframe strategies
- [ ] Deploy [paper trading](../guides/execution-modes.md#paper-mode)
- [ ] Build portfolio strategies
- [ ] Create custom indicators
- [ ] Understand statistical significance

### 🏆 Advanced Level
- [ ] Deploy live trading strategies
- [ ] Manage multiple exchange accounts
- [ ] Build machine learning models
- [ ] Contribute to Planar development
- [ ] Mentor other traders

**Ready for the next challenge?** Pick one immediate improvement and start coding! 🚀

## Best Practices

1. **Start Simple**: Begin with basic logic, add complexity gradually
2. **Test Thoroughly**: Use multiple time periods and market conditions
3. **Validate Everything**: Always check indicator values before using
4. **Log Decisions**: Use debug logging to understand strategy behavior
5. **Risk Management**: Always include stop losses and position sizing
6. **Backtest Extensively**: Test on different market conditions

## Common Patterns

### Multi-Timeframe Analysis
```julia
# Use different [timeframes](../guides/data-management.md#timeframes) for different purposes
:trend_daily => (; type=oti.EMA{DFT}, tf=tf"1d", params=(; period=20)),
:signal_hourly => (; type=oti.RSI{DFT}, tf=tf"1h", params=(; period=14)),
:entry_minute => (; type=oti.MACD{DFT}, tf=tf"1m", params=(; fast=12, slow=26, signal=9)),
```

### Confirmation Signals
```julia
# Require multiple confirmations
rsi_oversold = rsi < 30
macd_bullish = macd_line > macd_signal
volume_high = current_volume > volume_ma * 1.5

buy_signal = rsi_oversold && macd_bullish && volume_high
```

### Adaptive Parameters
```julia
# Adjust parameters based on market conditions
volatility = atr / current_price
rsi_threshold = volatility > 0.03 ? 25.0 : 30.0  # More aggressive in volatile markets
```

You now have a solid foundation for building Planar strategies! The key is to start simple, test thoroughly, and iterate based on results. Happy trading! 🚀