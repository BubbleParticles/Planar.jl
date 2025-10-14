# Data Access Examples

This example demonstrates how to load, access, and work with market data in Planar strategies. Learn the essential patterns for handling OHLCV data effectively.

## Overview

**What this example demonstrates:**
- Loading historical OHLCV data
- Accessing price and volume data
- Working with multiple timeframes
- Data validation and error handling
- Efficient data access patterns

**Complexity:** Beginner  
**Prerequisites:** [Basic Strategy Structure](../../getting-started/first-strategy.md)

## Complete Data Access Example


## Multi-Timeframe Data Access


## Efficient Data Loading Patterns


## Usage Examples

### Basic Usage
```julia
# PlanarDev loaded in project

# Demonstrate basic data access patterns
println("Planar data access examples:")

# Show basic Julia functionality
println("Julia version: ", VERSION)
println("Planar project loaded successfully!")

# Show data organization structure
println("Data is organized as: exchange/pair/timeframe/arrays")

# Example of accessing data (when available)
# This would work with actual data:
# data_path = PlanarDev.Planar.Data.key_path("binance", "BTC/USDT", "1m")
# println("Data path: ", data_path)
```

### Multi-Timeframe Usage

### Efficient Data Usage
```julia
# PlanarDev loaded in project
using Dates

# Demonstrate efficient data access patterns
println("Efficient data access examples:")

# Example 1: Check basic functionality
println("Julia environment ready!")
println("Current time: ", now())

# Example 2: Show time-based data access pattern
current_time = now()
println("Current time: ", current_time)

# Example 3: Demonstrate data iteration pattern
for i in 1:3
    @info "Run $i at time: $(current_time + Minute(i))"
    # In real usage, you would access data here:
    # data = get_data_at_time(zi, current_time + Minute(i))
end
```

## Common Data Access Patterns

### Safe Data Access

### Batch Data Processing

## Performance Tips

1. **Cache Calculations**: Store expensive calculations in dictionaries
2. **Batch Operations**: Process multiple assets in parallel with `@async`
3. **Validate Data**: Always check for empty or invalid data
4. **Use Appropriate Ranges**: Access only the data you need
5. **Handle Errors**: Wrap data access in try-catch blocks

## See Also

- **[Simple Indicators Example](simple-indicators.md)** - Building technical indicators
- **[Multi-Asset Strategies](#multi-asset)** - Working with multiple assets
- **[Data API Reference](../../data.md)** - Complete data API documentation
- **[Data Management Guide](../../guides/data-management.md)** - Comprehensive data guide