---
title: "Data API"
description: "Data structures, persistence, and OHLCV data handling"
category: "api-reference"
difficulty: "advanced"
prerequisites: ["getting-started", "data-management"]
topics: ["api-reference", "data", "ohlcv", "storage"]
last_updated: "2025-10-04"
estimated_time: "Reference material"
---

# Data API

The Data module provides comprehensive functionality for managing market data in Planar. It handles OHLCV (Open, High, Low, Close, Volume) data storage, retrieval, and manipulation using efficient storage formats like Zarr and LMDB.

## Overview

The Data module is responsible for:
- OHLCV data storage and retrieval
- Data persistence using Zarr format for large datasets
- LMDB key-value storage for fast access
- Data validation and integrity checking
- Efficient data structures for time series analysis

## Core Data Structures

### OHLCV Data Access

```julia
# Access OHLCV data from asset instance
ohlcv_data = ohlcv(asset_instance)

# Get specific OHLCV values
open_price = openat(ohlcv_data, index)
high_price = highat(ohlcv_data, index)
low_price = lowat(ohlcv_data, index)
close_price = closeat(ohlcv_data, index)
volume = volumeat(ohlcv_data, index)

# Get latest values
latest_close = closelast(ohlcv_data)
latest_candle = candleat(ohlcv_data, -1)  # Last candle
```

#### Usage Examples

```julia
using Planar
@environment!

s = strategy(:MyStrategy)
load_ohlcv(s)

# Work with OHLCV data
for ai in assets(s)
    data = ohlcv(ai)
    
    # Get recent prices
    current_price = closelast(data)
    prev_price = closeat(data, -2)
    
    # Calculate price change
    price_change = (current_price - prev_price) / prev_price
    println("$(raw(ai)): $(price_change * 100)% change")
    
    # Access volume data
    current_volume = volumeat(data, -1)
    avg_volume = mean(volumeat(data, -20:-1))  # 20-period average
    
    if current_volume > avg_volume * 1.5
        println("$(raw(ai)): High volume detected!")
    end
end
```

### Data Loading and Storage

#### Primary Data Functions

```julia
# Load OHLCV data for exchange and symbols
load_ohlcv(exchange, symbols::Vector{String}, timeframe::String)

# Load data for a strategy
load_ohlcv(s::Strategy; tf=s.config.min_timeframe, pairs=...)

# Propagate OHLCV data across timeframes
propagate_ohlcv!(data_dict, symbol, exchange)

# Create data stub for missing data
stub!(data_dict, symbol, timeframe, exchange)
```

#### Advanced Data Operations

```julia
# Load data with specific parameters
btc_data = load_ohlcv(exchange(s), ["BTC/USDT"], "1h")

# Load multiple timeframes
symbols = ["BTC/USDT", "ETH/USDT"]
for tf in ["1m", "5m", "1h", "1d"]
    data = load_ohlcv(exchange(s), symbols, tf)
    println("Loaded $tf data: $(length(data)) symbols")
end

# Propagate data across timeframes
for ai in assets(s)
    symbol = raw(ai)
    propagate_ohlcv!(ai.data, symbol, exchange(s))
end
```

### Data Persistence

#### Zarr Storage

Planar uses Zarr format for efficient storage of large time series datasets:

```julia
# Get Zarr instance
zi = Data.zi[]  # Global Zarr instance

# Store data in Zarr format
zarr_group = zi[exchange_name][symbol][timeframe]

# Access stored data
stored_data = zarr_group["close"][:]  # All close prices
recent_data = zarr_group["close"][-100:]  # Last 100 values
```

#### LMDB Key-Value Storage

For fast metadata and configuration storage:

```julia
using .Data.Cache

# Save data to cache
save_cache("strategy_config", config_data)

# Load data from cache
config = load_cache("strategy_config")

# Cache with expiration
save_cache("market_data", data, ttl=3600)  # 1 hour TTL
```

## Data Validation and Integrity

### Data Quality Checks

```julia
# Check for data gaps
function check_data_integrity(ohlcv_data, timeframe)
    timestamps = ohlcv_data.timestamp
    expected_interval = timeframe.period
    
    for i in 2:length(timestamps)
        actual_interval = timestamps[i] - timestamps[i-1]
        if actual_interval != expected_interval
            @warn "Data gap detected" expected=expected_interval actual=actual_interval
        end
    end
end

# Validate OHLCV consistency
function validate_ohlcv(ohlcv_data)
    for i in 1:length(ohlcv_data.open)
        o, h, l, c = ohlcv_data.open[i], ohlcv_data.high[i], 
                     ohlcv_data.low[i], ohlcv_data.close[i]
        
        if !(l <= o <= h && l <= c <= h)
            @error "Invalid OHLCV data at index $i" open=o high=h low=l close=c
        end
    end
end
```

### Data Cleaning

```julia
# Remove invalid data points
function clean_ohlcv_data!(ohlcv_data)
    valid_indices = Int[]
    
    for i in 1:length(ohlcv_data.open)
        o, h, l, c, v = ohlcv_data.open[i], ohlcv_data.high[i], 
                        ohlcv_data.low[i], ohlcv_data.close[i], ohlcv_data.volume[i]
        
        # Check for valid OHLCV relationships and positive volume
        if l <= o <= h && l <= c <= h && v >= 0
            push!(valid_indices, i)
        end
    end
    
    # Keep only valid data
    for field in [:open, :high, :low, :close, :volume, :timestamp]
        data_array = getfield(ohlcv_data, field)
        setfield!(ohlcv_data, field, data_array[valid_indices])
    end
end
```

## DataFrame Integration

### Working with DataFrames

```julia
using .Data.DataFrames
using .Data.DFUtils

# Convert OHLCV to DataFrame
function ohlcv_to_dataframe(ohlcv_data)
    DataFrame(
        timestamp = ohlcv_data.timestamp,
        open = ohlcv_data.open,
        high = ohlcv_data.high,
        low = ohlcv_data.low,
        close = ohlcv_data.close,
        volume = ohlcv_data.volume
    )
end

# DataFrame operations
df = ohlcv_to_dataframe(ohlcv(asset_instance))

# Add technical indicators
df.sma_20 = rolling_mean(df.close, 20)
df.returns = [NaN; diff(log.(df.close))]

# Filter data
recent_df = df[end-100:end, :]  # Last 100 rows
high_volume_df = df[df.volume .> quantile(df.volume, 0.9), :]
```

## Performance Optimization

### Efficient Data Access Patterns

```julia
# Pre-allocate arrays for calculations
function calculate_indicators_efficient(ohlcv_data, window=20)
    n = length(ohlcv_data.close)
    sma = Vector{Float64}(undef, n)
    
    # Calculate SMA efficiently
    for i in window:n
        sma[i] = mean(ohlcv_data.close[i-window+1:i])
    end
    
    return sma
end

# Batch data processing
function process_multiple_assets(assets, calculation_func)
    results = Dict{String, Any}()
    
    @sync for ai in assets
        @async begin
            symbol = raw(ai)
            data = ohlcv(ai)
            results[symbol] = calculation_func(data)
        end
    end
    
    return results
end
```

### Memory Management

```julia
# Limit data size for memory efficiency
function load_recent_data_only(s::Strategy, max_periods=1000)
    for ai in assets(s)
        data = ohlcv(ai)
        if length(data.close) > max_periods
            # Keep only recent data
            start_idx = length(data.close) - max_periods + 1
            for field in [:open, :high, :low, :close, :volume, :timestamp]
                array = getfield(data, field)
                setfield!(data, field, array[start_idx:end])
            end
        end
    end
end
```

## Data Streaming and Updates

### Real-time Data Updates

```julia
# Update data with new candles
function update_ohlcv_realtime!(ai::AssetInstance, new_candle)
    data = ohlcv(ai)
    
    # Append new candle
    push!(data.timestamp, new_candle.timestamp)
    push!(data.open, new_candle.open)
    push!(data.high, new_candle.high)
    push!(data.low, new_candle.low)
    push!(data.close, new_candle.close)
    push!(data.volume, new_candle.volume)
    
    # Maintain maximum size
    max_size = 10000
    if length(data.close) > max_size
        # Remove oldest data
        for field in [:open, :high, :low, :close, :volume, :timestamp]
            array = getfield(data, field)
            setfield!(data, field, array[2:end])
        end
    end
end
```

## Common Data Patterns

### Moving Averages

```julia
# Simple Moving Average
function sma(prices::Vector{Float64}, window::Int)
    n = length(prices)
    result = Vector{Float64}(undef, n)
    
    for i in window:n
        result[i] = mean(prices[i-window+1:i])
    end
    
    return result
end

# Exponential Moving Average
function ema(prices::Vector{Float64}, alpha::Float64)
    result = copy(prices)
    result[1] = prices[1]
    
    for i in 2:length(prices)
        result[i] = alpha * prices[i] + (1 - alpha) * result[i-1]
    end
    
    return result
end
```

### Price Analysis

```julia
# Calculate returns
function calculate_returns(ohlcv_data)
    closes = ohlcv_data.close
    returns = Vector{Float64}(undef, length(closes))
    returns[1] = NaN
    
    for i in 2:length(closes)
        returns[i] = (closes[i] - closes[i-1]) / closes[i-1]
    end
    
    return returns
end

# Volatility calculation
function calculate_volatility(returns::Vector{Float64}, window::Int=20)
    n = length(returns)
    volatility = Vector{Float64}(undef, n)
    
    for i in window:n
        window_returns = returns[i-window+1:i]
        volatility[i] = std(skipmissing(window_returns))
    end
    
    return volatility
end
```

## Complete API Reference

```@autodocs
Modules = [Planar.Data]
```

## See Also

- **[Data Management Guide](../guides/data-management.md)** - Complete guide to working with market data
- **[Processing API](processing.md)** - Data processing and transformation functions
- **[DFUtils API](dfutils.md)** - DataFrame manipulation utilities
- **[Engine API](engine.md)** - Core execution engine functions
- **[Fetch API](fetch.md)** - Data fetching and retrieval utilities
