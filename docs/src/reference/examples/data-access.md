---
title: "Data Access Examples"
description: "Loading and accessing market data in Planar strategies"
category: "examples"
difficulty: "beginner"
prerequisites: ["getting-started", "basic-strategy"]
topics: ["examples", "data", "ohlcv", "market-data"]
last_updated: "2025-10-04"
estimated_time: "15 minutes"
---

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
using Planar
@environment!

# Load and test the data access example
s = strategy(:DataAccessExample)
load_ohlcv(s)

# Run once to see data access patterns
call!(s, now(), nothing)
```

### Multi-Timeframe Usage

### Efficient Data Usage
```julia
# Test efficient data patterns
s_efficient = strategy(:EfficientDataExample)
load_ohlcv(s_efficient)

# Run multiple times to see caching in action
for i in 1:3
    @info "Run $i"
    call!(s_efficient, now() + Minute(i), nothing)
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