# Your First Strategy Tutorial

In this tutorial, you'll learn to create a custom trading strategy from scratch. We'll build a simple RSI (Relative Strength Index) mean reversion strategy that demonstrates all the key concepts of Planar strategy development.

## What You'll Learn

By the end of this tutorial, you'll understand:

- How Planar strategies are structured
- The three core functions every strategy needs
- How to add technical indicators
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

Every Planar strategy is a Julia module with three core functions:

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
# Start Julia in the Planar directory
using PlanarInteractive
@environment!

# Load your strategy
push!(LOAD_PATH, "user/strategies/MyFirstStrategy/src")
using MyFirstStrategy

# Create strategy instance
s = strategy(:MyFirstStrategy, exchange=:binance, asset="BTC/USDT")

# Download some data
fetch_ohlcv(s, from=-1000)
load_ohlcv(s)

# Run backtest
start!(s)

# Check results
println("Final balance: $(cash(s))")
println("Number of trades: $(length(s.history.trades))")
```

## Step 10: Analyze Results

```julia
# Get detailed metrics
using Plotting
using WGLMakie

# Plot results
balloons(s)

# Performance analysis
total_return = (cash(s) - s.config.cash) / s.config.cash * 100
println("Total return: $(round(total_return, digits=2))%")

# Trade analysis
trades = s.history.trades
if !isempty(trades)
    winning_trades = count(t -> t.pnl > 0, trades)
    win_rate = winning_trades / length(trades) * 100
    println("Win rate: $(round(win_rate, digits=2))%")
    
    avg_win = mean([t.pnl for t in trades if t.pnl > 0])
    avg_loss = mean([t.pnl for t in trades if t.pnl < 0])
    println("Average win: $(round(avg_win, digits=2))")
    println("Average loss: $(round(avg_loss, digits=2))")
end
```

## Step 11: Debug and Improve

### Enable Debug Logging

```julia
# Enable debug logging to see signal analysis
ENV["JULIA_DEBUG"] = "MyFirstStrategy"

# Run again to see detailed logs
start!(s)
```

### Common Issues and Solutions

**No trades executed**:
- Check if indicators are calculating correctly
- Verify buy/sell conditions aren't too restrictive
- Ensure data has enough history for indicators

**Too many trades**:
- Add additional filters
- Increase trend strength requirements
- Add cooldown periods between trades

**Poor performance**:
- Adjust RSI thresholds
- Try different moving average periods
- Add stop-loss or take-profit logic

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
Indicators can use different timeframes:
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

## Next Steps

Congratulations! You've built your first custom Planar strategy. Here's what to explore next:

1. **[Strategy Examples](../strategy.md#examples)** - Study more complex patterns
2. **[Optimization Guide](../optimization.md)** - Learn to optimize parameters
3. **[Data Management](../data.md)** - Work with different data sources
4. **[Paper Trading](../engine/paper.md)** - Test with live data
5. **[Live Trading](../engine/live.md)** - Deploy for real trading

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
# Use different timeframes for different purposes
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