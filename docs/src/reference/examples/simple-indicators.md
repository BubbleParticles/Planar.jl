---
title: "Simple Indicators Examples"
description: "Moving averages and basic technical indicator calculations"
category: "examples"
difficulty: "beginner"
prerequisites: ["getting-started", "basic-strategy", "data-access"]
topics: ["examples", "indicators", "technical-analysis", "moving-averages"]
last_updated: "2025-10-04"
estimated_time: "20 minutes"
---

# Simple Indicators Examples

This example demonstrates how to calculate and use common technical indicators in Planar strategies. Learn to implement moving averages, RSI, MACD, and other essential indicators.

## Overview

**What this example demonstrates:**
- Simple and exponential moving averages
- RSI (Relative Strength Index) calculation
- MACD (Moving Average Convergence Divergence)
- Bollinger Bands
- Volume indicators
- Indicator-based trading signals

**Complexity:** Beginner  
**Prerequisites:** [Data Access Examples](data-access.md)

## Complete Indicators Example


## Advanced Indicators Example


## Indicator-Based Strategy Example


## Usage Examples

### Basic Indicators
```julia
using Planar
@environment!

# Test simple indicators
s = strategy(:SimpleIndicatorsExample)
load_ohlcv(s)

# Run analysis
call!(s, now(), nothing)
```

### Advanced Indicators
```julia
# Test advanced indicators
s_adv = strategy(:AdvancedIndicatorsExample)
load_ohlcv(s_adv)
call!(s_adv, now(), nothing)
```

### Complete Strategy
```julia
# Test indicator-based strategy
s_strategy = strategy(:IndicatorStrategy)
load_ohlcv(s_strategy)

# Run backtest
results = backtest(s_strategy, 
    from=DateTime("2024-01-01"),
    to=DateTime("2024-06-30")
)
```

## Performance Tips

1. **Cache Calculations**: Store indicator values to avoid recalculation
2. **Vectorize Operations**: Use array operations when possible
3. **Limit Lookback**: Only calculate indicators for required periods
4. **Validate Inputs**: Always check for sufficient data before calculation
5. **Handle Edge Cases**: Account for division by zero and invalid data

## Common Indicator Patterns

### Trend Following

### Mean Reversion

### Volume Confirmation

## See Also

- **[Data Access Examples](data-access.md)** - Working with market data
- **[Technical Analysis Examples](technical-analysis.md)** - Advanced analysis techniques
- **[Risk Management Examples](risk-management.md)** - Position sizing and stops
- **[Multi-Asset Strategies](multi-asset.md)** - Trading multiple assets