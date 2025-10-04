---
title: "Basic Strategy Structure"
description: "Simple strategy template and structure"
category: "examples"
difficulty: "beginner"
prerequisites: ["getting-started"]
topics: ["examples", "strategy", "template"]
last_updated: "2025-10-04"
estimated_time: "10 minutes"
---

# Basic Strategy Structure

This example demonstrates the fundamental structure of a Planar strategy. Use this as a starting template for your own strategies.

## Overview

**What this example demonstrates:**
- Basic strategy module structure
- Essential strategy functions
- Configuration and parameters
- Simple trading logic template

**Complexity:** Beginner  
**Prerequisites:** Understanding of [Getting Started Guide](../../getting-started/index.md)

## Complete Example

```julia
# Example: Basic Strategy Template
# Description: Minimal working strategy structure
# Complexity: Beginner
# Prerequisites: Basic Planar knowledge

module BasicStrategy
    @strategyenv!
    
    # Strategy Configuration
    const DESCRIPTION = "Basic strategy template"
    const TIMEFRAME = tf"1h"
    
    # Strategy Parameters
    const BUY_THRESHOLD = Ref(0.02)   # 2% price increase threshold
    const SELL_THRESHOLD = Ref(-0.01) # 1% price decrease threshold
    const MIN_TRADE_SIZE = Ref(100.0) # Minimum trade size in quote currency
    
    # Define markets to trade
    function call!(::Type{S}, ::StrategyMarkets) where {S<:Strategy}
        return ["BTC/USDT", "ETH/USDT"]
    end
    
    # Define warmup period (how much historical data needed)
    function call!(s::S, ::WarmupPeriod) where {S<:Strategy}
        return 50  # Need 50 periods of data
    end
    
    # Main strategy logic - called on each time step
    function call!(s::S, current_time::DateTime, ctx) where {S<:Strategy}
        # Iterate through all assets in the strategy
        for ai in assets(s)
            # Skip if we don't have enough data
            if length(ohlcv(ai)) < 2
                continue
            end
            
            # Get current and previous prices
            current_price = lastprice(ai)
            previous_price = closeat(ohlcv(ai), -2)
            
            # Calculate price change
            price_change = (current_price - previous_price) / previous_price
            
            # Get current position
            current_balance = asset(ai)
            available_cash = freecash(s)
            
            # Trading logic
            if price_change > BUY_THRESHOLD[] && available_cash > MIN_TRADE_SIZE[]
                # Price increased significantly and we have cash - consider buying
                trade_amount = min(available_cash * 0.1, MIN_TRADE_SIZE[])  # Use 10% of cash or min size
                @info "Buy signal detected" asset=raw(ai) price_change=price_change trade_amount=trade_amount
                
                # Here you would place a buy order
                # place_buy_order(s, ai, trade_amount / current_price, current_price)
                
            elseif price_change < SELL_THRESHOLD[] && current_balance > 0
                # Price decreased and we have a position - consider selling
                @info "Sell signal detected" asset=raw(ai) price_change=price_change balance=current_balance
                
                # Here you would place a sell order
                # place_sell_order(s, ai, current_balance, current_price)
            end
        end
    end
    
    # Called when strategy starts
    function call!(s::S, ::StartStrategy) where {S<:Strategy}
        @info "BasicStrategy started" timeframe=s.timeframe assets=length(assets(s))
    end
    
    # Called when strategy stops
    function call!(s::S, ::StopStrategy) where {S<:Strategy}
        @info "BasicStrategy stopped"
    end
    
    # Helper function to calculate simple moving average
    function simple_moving_average(prices::Vector{Float64}, window::Int)
        if length(prices) < window
            return NaN
        end
        return mean(prices[end-window+1:end])
    end
    
    # Helper function to get price trend
    function get_price_trend(ai::AssetInstance, window::Int=5)
        if length(ohlcv(ai)) < window
            return :unknown
        end
        
        prices = closeat(ohlcv(ai), -window:-1)
        first_price = prices[1]
        last_price = prices[end]
        
        change = (last_price - first_price) / first_price
        
        if change > 0.01
            return :uptrend
        elseif change < -0.01
            return :downtrend
        else
            return :sideways
        end
    end
end
```

## Usage Example

```julia
using Planar
@environment!

# Load the strategy
s = strategy(:BasicStrategy)

# Check strategy configuration
println("Strategy: $(s.self)")
println("Timeframe: $(s.timeframe)")
println("Assets: $(length(assets(s)))")

# Load historical data
load_ohlcv(s)

# Run in simulation mode for testing
s_sim = strategy(:BasicStrategy, Sim())
load_ohlcv(s_sim)

# Run a simple backtest
results = backtest(s_sim, 
    from=DateTime("2024-01-01"),
    to=DateTime("2024-03-31")
)

println("Backtest results:")
println("  Total return: $(results.total_return)")
println("  Number of trades: $(results.num_trades)")
```

## Key Components Explained

### 1. Module Declaration
```julia
module BasicStrategy
    @strategyenv!
```
- Every strategy is a Julia module
- `@strategyenv!` imports necessary Planar functions and types

### 2. Configuration Constants
```julia
const DESCRIPTION = "Basic strategy template"
const TIMEFRAME = tf"1h"
```
- `DESCRIPTION`: Human-readable strategy description
- `TIMEFRAME`: The primary timeframe the strategy operates on

### 3. Parameters
```julia
const BUY_THRESHOLD = Ref(0.02)
const SELL_THRESHOLD = Ref(-0.01)
```
- Use `Ref()` for parameters that might be optimized
- Makes parameters mutable for optimization algorithms

### 4. Market Definition
```julia
function call!(::Type{S}, ::StrategyMarkets) where {S<:Strategy}
    return ["BTC/USDT", "ETH/USDT"]
end
```
- Defines which markets/symbols the strategy will trade
- Return a vector of symbol strings

### 5. Main Strategy Logic
```julia
function call!(s::S, current_time::DateTime, ctx) where {S<:Strategy}
    # Your trading logic here
end
```
- Called on each time step during execution
- Contains the core trading decision logic

## Customization Guide

### Adding New Parameters
```julia
# Add new parameter
const NEW_PARAMETER = Ref(default_value)

# Use in strategy logic
if some_condition > NEW_PARAMETER[]
    # Trading logic
end
```

### Adding More Assets
```julia
function call!(::Type{S}, ::StrategyMarkets) where {S<:Strategy}
    return [
        "BTC/USDT", "ETH/USDT", "ADA/USDT", 
        "DOT/USDT", "LINK/USDT"
    ]
end
```

### Adding Technical Indicators
```julia
# Add to strategy logic
sma_20 = simple_moving_average(closeat(ohlcv(ai), -20:-1), 20)
sma_50 = simple_moving_average(closeat(ohlcv(ai), -50:-1), 50)

if !isnan(sma_20) && !isnan(sma_50) && sma_20 > sma_50
    # Golden cross - bullish signal
    @info "Golden cross detected" asset=raw(ai)
end
```

## Testing Your Strategy

### 1. Simulation Testing
```julia
# Test with historical data
s = strategy(:BasicStrategy, Sim())
load_ohlcv(s)

# Run backtest
results = backtest(s, from=DateTime("2024-01-01"), to=DateTime("2024-12-31"))
```

### 2. Paper Trading
```julia
# Test with live data but no real money
s = strategy(:BasicStrategy, Paper())
load_ohlcv(s)
start_paper_trading(s)
```

### 3. Parameter Testing
```julia
# Test different parameter values
BasicStrategy.BUY_THRESHOLD[] = 0.03  # 3% threshold
BasicStrategy.SELL_THRESHOLD[] = -0.02  # 2% threshold

# Re-run tests with new parameters
```

## Common Patterns

### Error Handling
```julia
function call!(s::S, current_time::DateTime, ctx) where {S<:Strategy}
    try
        # Strategy logic here
        for ai in assets(s)
            # Safe operations
        end
    catch e
        @error "Strategy error" exception=e
        # Handle gracefully
    end
end
```

### Logging and Debugging
```julia
# Add informative logging
@info "Processing asset" asset=raw(ai) price=current_price
@debug "Detailed info" balance=current_balance cash=available_cash

# Use different log levels
@warn "Unusual condition detected" condition=some_value
@error "Critical error" error=error_info
```

### Data Validation
```julia
# Always check data availability
if isempty(ohlcv(ai)) || length(ohlcv(ai)) < required_periods
    @debug "Insufficient data for $(raw(ai))"
    continue
end

# Validate prices
current_price = lastprice(ai)
if current_price <= 0 || isnan(current_price)
    @warn "Invalid price for $(raw(ai))" price=current_price
    continue
end
```

## Next Steps

After mastering this basic structure:

1. **Add Indicators**: Learn [Simple Indicators](simple-indicators.md)
2. **Implement Orders**: See [Order Placement](order-placement.md)
3. **Add Risk Management**: Check [Risk Management](risk-management.md)
4. **Multi-Asset Trading**: Explore [Multi-Asset Strategies](multi-asset.md)

## See Also

- **[Strategy Development Guide](../../guides/strategy-development.md)** - Complete strategy development guide
- **[Getting Started](../../getting-started/first-strategy.md)** - Your first strategy tutorial
- **[Strategies API](../api/strategies.md)** - Strategy API reference
- **[Simple Indicators Example](simple-indicators.md)** - Adding technical indicators