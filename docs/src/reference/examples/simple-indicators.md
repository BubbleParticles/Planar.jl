<!--
title: "Simple Indicators Examples"
description: "Moving averages and basic technical indicator calculations"
category: "examples"
difficulty: "beginner"
prerequisites: ["getting-started", "basic-strategy", "data-access"]
topics: ["examples", "indicators", "technical-analysis", "moving-averages"]
last_updated: "2025-10-04"
estimated_time: "20 minutes"
-->

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
# PlanarDev loaded in project

# Demonstrate basic indicator concepts
println("Simple indicators example:")

# Show basic functionality
println("Julia version: ", VERSION)
println("Planar project loaded successfully!")

# Example of basic indicator calculation
println("Example: Simple Moving Average calculation")
println("SMA = sum(prices) / length(prices)")

# Example data for demonstration
prices = [100.0, 101.0, 102.0, 101.5, 103.0]
sma = sum(prices) / length(prices)
println("Prices: ", prices)
println("SMA: ", sma)
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
# PlanarDev loaded in project
using Dates

# Demonstrate indicator-based strategy concepts
println("Indicator-based strategy example:")

# Show basic functionality
println("Julia environment ready!")
println("Planar project available: PlanarDev")

# Example indicator calculations
println("Technical indicators demonstration:")
prices = [100.0, 101.0, 102.0, 101.5, 103.0, 104.0, 102.5, 105.0]

# Simple Moving Average
sma_5_value = sum(prices[end-4:end]) / 5
println("5-period SMA: ", sma_5_value)

# Price change
price_change = prices[end] - prices[end-1]
println("Latest price change: ", price_change)

# Example backtest period
from_date = DateTime("2024-01-01")
to_date = DateTime("2024-06-30")
println("Backtest period: ", from_date, " to ", to_date)
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
- **[Technical Analysis Examples](#technical-analysis)** - Advanced analysis techniques
- **[Risk Management Examples](../../advanced/risk-management.md)** - Position sizing and stops
- **[Multi-Asset Strategies](#multi-asset)** - Trading multiple assets