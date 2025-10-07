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


## Usage Example


## Key Components Explained

### 1. Module Declaration
- Every strategy is a Julia module
- `@strategyenv!` imports necessary Planar functions and types

### 2. Configuration Constants
- `DESCRIPTION`: Human-readable strategy description
- `TIMEFRAME`: The primary timeframe the strategy operates on

### 3. Parameters
- Use `Ref()` for parameters that might be optimized
- Makes parameters mutable for optimization algorithms

### 4. Market Definition
- Defines which markets/symbols the strategy will trade
- Return a vector of symbol strings

### 5. Main Strategy Logic
- Called on each time step during execution
- Contains the core trading decision logic

## Customization Guide

### Adding New Parameters

### Adding More Assets

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

## Common Patterns

### Error Handling

### Logging and Debugging

### Data Validation

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