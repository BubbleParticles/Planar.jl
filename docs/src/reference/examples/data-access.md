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
**Prerequisites:** [Basic Strategy Structure](basic-strategy.md)

## Complete Data Access Example

```julia
# Example: Comprehensive Data Access
# Description: Loading and accessing market data
# Complexity: Beginner
# Prerequisites: Basic strategy knowledge

module DataAccessExample
    @strategyenv!
    
    const DESCRIPTION = "Data access demonstration"
    const TIMEFRAME = tf"1h"
    
    # Define markets
    function call!(::Type{S}, ::StrategyMarkets) where {S<:Strategy}
        return ["BTC/USDT", "ETH/USDT", "ADA/USDT"]
    end
    
    function call!(s::S, ::WarmupPeriod) where {S<:Strategy}
        return 100  # Need 100 periods for analysis
    end
    
    function call!(s::S, current_time::DateTime, ctx) where {S<:Strategy}
        @info "Data Access Example - $(current_time)"
        
        # Demonstrate various data access patterns
        for ai in assets(s)
            demonstrate_basic_access(ai)
            demonstrate_historical_access(ai)
            demonstrate_data_validation(ai)
            demonstrate_calculations(ai)
            println()  # Separator
        end
    end
    
    # Basic data access patterns
    function demonstrate_basic_access(ai::AssetInstance)
        println("=== Basic Data Access for $(raw(ai)) ===")
        
        # Get OHLCV data
        data = ohlcv(ai)
        
        if isempty(data)
            println("No data available")
            return
        end
        
        # Current (latest) values
        current_open = openat(data, -1)
        current_high = highat(data, -1)
        current_low = lowat(data, -1)
        current_close = closelast(data)  # Shorthand for closeat(data, -1)
        current_volume = volumeat(data, -1)
        
        println("Current candle:")
        println("  Open: $current_open")
        println("  High: $current_high")
        println("  Low: $current_low")
        println("  Close: $current_close")
        println("  Volume: $current_volume")
        
        # Previous values
        prev_close = closeat(data, -2)
        prev_volume = volumeat(data, -2)
        
        println("Previous close: $prev_close")
        println("Previous volume: $prev_volume")
        
        # Price change
        if !isnan(prev_close) && prev_close > 0
            price_change = (current_close - prev_close) / prev_close
            println("Price change: $(round(price_change * 100, digits=2))%")
        end
    end
    
    # Historical data access
    function demonstrate_historical_access(ai::AssetInstance)
        println("=== Historical Data Access ===")
        
        data = ohlcv(ai)
        data_length = length(data.close)
        
        println("Total data points: $data_length")
        
        if data_length < 10
            println("Insufficient data for historical analysis")
            return
        end
        
        # Get ranges of data
        last_10_closes = closeat(data, -10:-1)
        last_20_highs = highat(data, -20:-1)
        last_5_volumes = volumeat(data, -5:-1)
        
        println("Last 10 closes: $(round.(last_10_closes, digits=2))")
        println("Highest in last 20: $(maximum(last_20_highs))")
        println("Average volume (last 5): $(round(mean(last_5_volumes), digits=2))")
        
        # Get specific historical points
        if data_length >= 50
            close_50_ago = closeat(data, -50)
            high_30_ago = highat(data, -30)
            
            println("Close 50 periods ago: $close_50_ago")
            println("High 30 periods ago: $high_30_ago")
        end
        
        # Calculate returns over different periods
        current_price = closelast(data)
        
        for periods in [1, 5, 10, 20]
            if data_length > periods
                past_price = closeat(data, -(periods + 1))
                return_pct = (current_price - past_price) / past_price * 100
                println("$(periods)-period return: $(round(return_pct, digits=2))%")
            end
        end
    end
    
    # Data validation patterns
    function demonstrate_data_validation(ai::AssetInstance)
        println("=== Data Validation ===")
        
        data = ohlcv(ai)
        
        # Check if data exists
        if isempty(data)
            println("❌ No data available")
            return
        end
        
        println("✅ Data available: $(length(data.close)) candles")
        
        # Validate recent data
        current_close = closelast(data)
        current_volume = volumeat(data, -1)
        
        # Price validation
        if current_close <= 0 || isnan(current_close)
            println("❌ Invalid current price: $current_close")
        else
            println("✅ Valid current price: $current_close")
        end
        
        # Volume validation
        if current_volume < 0 || isnan(current_volume)
            println("❌ Invalid current volume: $current_volume")
        else
            println("✅ Valid current volume: $current_volume")
        end
        
        # Check for data gaps (simplified)
        if length(data.close) >= 2
            timestamps = data.timestamp
            if length(timestamps) >= 2
                last_gap = timestamps[end] - timestamps[end-1]
                expected_gap = TIMEFRAME.period
                
                if last_gap == expected_gap
                    println("✅ No data gap detected")
                else
                    println("⚠️  Data gap detected: expected $(expected_gap), got $(last_gap)")
                end
            end
        end
        
        # OHLCV consistency check
        if length(data.close) >= 1
            o, h, l, c = openat(data, -1), highat(data, -1), lowat(data, -1), closelast(data)
            
            if l <= o <= h && l <= c <= h
                println("✅ OHLCV data is consistent")
            else
                println("❌ OHLCV data inconsistency detected")
                println("   O:$o H:$h L:$l C:$c")
            end
        end
    end
    
    # Common calculations with data
    function demonstrate_calculations(ai::AssetInstance)
        println("=== Common Calculations ===")
        
        data = ohlcv(ai)
        
        if length(data.close) < 20
            println("Need at least 20 data points for calculations")
            return
        end
        
        # Simple Moving Averages
        sma_5 = mean(closeat(data, -5:-1))
        sma_10 = mean(closeat(data, -10:-1))
        sma_20 = mean(closeat(data, -20:-1))
        
        println("Moving Averages:")
        println("  SMA(5): $(round(sma_5, digits=2))")
        println("  SMA(10): $(round(sma_10, digits=2))")
        println("  SMA(20): $(round(sma_20, digits=2))")
        
        # Price statistics
        recent_closes = closeat(data, -20:-1)
        price_std = std(recent_closes)
        price_min = minimum(recent_closes)
        price_max = maximum(recent_closes)
        
        println("Price Statistics (20 periods):")
        println("  Standard Deviation: $(round(price_std, digits=2))")
        println("  Min: $(round(price_min, digits=2))")
        println("  Max: $(round(price_max, digits=2))")
        println("  Range: $(round(price_max - price_min, digits=2))")
        
        # Volume analysis
        recent_volumes = volumeat(data, -10:-1)
        avg_volume = mean(recent_volumes)
        current_volume = volumeat(data, -1)
        volume_ratio = current_volume / avg_volume
        
        println("Volume Analysis:")
        println("  Average Volume (10 periods): $(round(avg_volume, digits=2))")
        println("  Current Volume: $(round(current_volume, digits=2))")
        println("  Volume Ratio: $(round(volume_ratio, digits=2))x")
        
        # Volatility (simplified)
        returns = []
        for i in 2:length(recent_closes)
            ret = (recent_closes[i] - recent_closes[i-1]) / recent_closes[i-1]
            push!(returns, ret)
        end
        
        if !isempty(returns)
            volatility = std(returns)
            println("Volatility (std of returns): $(round(volatility * 100, digits=2))%")
        end
    end
end
```

## Multi-Timeframe Data Access

```julia
# Example: Working with Multiple Timeframes
module MultiTimeframeExample
    @strategyenv!
    
    const DESCRIPTION = "Multi-timeframe data access"
    const TIMEFRAME = tf"1h"  # Primary timeframe
    
    function call!(::Type{S}, ::StrategyMarkets) where {S<:Strategy}
        return ["BTC/USDT"]
    end
    
    function call!(s::S, current_time::DateTime, ctx) where {S<:Strategy}
        for ai in assets(s)
            analyze_multiple_timeframes(ai)
        end
    end
    
    function analyze_multiple_timeframes(ai::AssetInstance)
        println("=== Multi-Timeframe Analysis for $(raw(ai)) ===")
        
        # Access different timeframes
        timeframes = [tf"5m", tf"15m", tf"1h", tf"4h", tf"1d"]
        
        for tf in timeframes
            data = ohlcv(ai, tf)
            
            if !isempty(data)
                current_price = closelast(data)
                data_points = length(data.close)
                
                # Calculate trend over different periods
                if data_points >= 10
                    old_price = closeat(data, -10)
                    trend = (current_price - old_price) / old_price * 100
                    
                    println("$(tf): $(data_points) candles, trend: $(round(trend, digits=2))%")
                else
                    println("$(tf): $(data_points) candles (insufficient for trend)")
                end
            else
                println("$(tf): No data available")
            end
        end
        
        # Cross-timeframe analysis
        h1_data = ohlcv(ai, tf"1h")
        h4_data = ohlcv(ai, tf"4h")
        d1_data = ohlcv(ai, tf"1d")
        
        if !isempty(h1_data) && !isempty(h4_data) && !isempty(d1_data)
            h1_trend = calculate_trend(h1_data, 20)
            h4_trend = calculate_trend(h4_data, 10)
            d1_trend = calculate_trend(d1_data, 5)
            
            println("\nTrend Alignment:")
            println("  1H trend: $(trend_direction(h1_trend))")
            println("  4H trend: $(trend_direction(h4_trend))")
            println("  1D trend: $(trend_direction(d1_trend))")
            
            if h1_trend > 0 && h4_trend > 0 && d1_trend > 0
                println("  🟢 All timeframes bullish")
            elseif h1_trend < 0 && h4_trend < 0 && d1_trend < 0
                println("  🔴 All timeframes bearish")
            else
                println("  🟡 Mixed signals across timeframes")
            end
        end
    end
    
    function calculate_trend(data, periods)
        if length(data.close) < periods + 1
            return 0.0
        end
        
        current = closelast(data)
        past = closeat(data, -(periods + 1))
        
        return (current - past) / past
    end
    
    function trend_direction(trend_value)
        if trend_value > 0.02
            return "Strong Up"
        elseif trend_value > 0.005
            return "Up"
        elseif trend_value < -0.02
            return "Strong Down"
        elseif trend_value < -0.005
            return "Down"
        else
            return "Sideways"
        end
    end
end
```

## Efficient Data Loading Patterns

```julia
# Example: Efficient Data Loading and Caching
module EfficientDataExample
    @strategyenv!
    
    const DESCRIPTION = "Efficient data loading patterns"
    const TIMEFRAME = tf"1h"
    
    # Cache for calculated indicators
    const INDICATOR_CACHE = Dict{String, Dict{Symbol, Any}}()
    
    function call!(::Type{S}, ::StrategyMarkets) where {S<:Strategy}
        return ["BTC/USDT", "ETH/USDT", "ADA/USDT"]
    end
    
    function call!(s::S, current_time::DateTime, ctx) where {S<:Strategy}
        # Batch load all data first
        batch_load_data(s)
        
        # Process each asset efficiently
        for ai in assets(s)
            process_asset_efficiently(ai, current_time)
        end
    end
    
    function batch_load_data(s::Strategy)
        @info "Batch loading data for $(length(assets(s))) assets"
        
        # Load data for all assets in parallel
        @sync for ai in assets(s)
            @async begin
                symbol = raw(ai)
                
                # Ensure we have recent data
                if isempty(ohlcv(ai))
                    @debug "Loading initial data for $symbol"
                    # This would trigger data loading
                end
                
                # Update cache timestamp
                INDICATOR_CACHE[symbol] = get(INDICATOR_CACHE, symbol, Dict{Symbol, Any}())
                INDICATOR_CACHE[symbol][:last_update] = now()
            end
        end
    end
    
    function process_asset_efficiently(ai::AssetInstance, current_time::DateTime)
        symbol = raw(ai)
        data = ohlcv(ai)
        
        if isempty(data)
            return
        end
        
        # Check if we need to recalculate indicators
        cache = get(INDICATOR_CACHE, symbol, Dict{Symbol, Any}())
        last_update = get(cache, :last_update, DateTime(0))
        
        # Recalculate if data is newer than cache
        if current_time > last_update
            calculate_and_cache_indicators(ai, cache)
            cache[:last_update] = current_time
        end
        
        # Use cached indicators
        sma_20 = get(cache, :sma_20, NaN)
        rsi = get(cache, :rsi, NaN)
        
        if !isnan(sma_20) && !isnan(rsi)
            current_price = closelast(data)
            
            @info "Efficient analysis" symbol=symbol price=current_price sma_20=sma_20 rsi=rsi
            
            # Trading logic using cached indicators
            if current_price > sma_20 && rsi < 30
                @info "Potential buy signal" symbol=symbol
            elseif current_price < sma_20 && rsi > 70
                @info "Potential sell signal" symbol=symbol
            end
        end
    end
    
    function calculate_and_cache_indicators(ai::AssetInstance, cache::Dict{Symbol, Any})
        data = ohlcv(ai)
        symbol = raw(ai)
        
        @debug "Calculating indicators for $symbol"
        
        # Calculate SMA 20
        if length(data.close) >= 20
            sma_20 = mean(closeat(data, -20:-1))
            cache[:sma_20] = sma_20
        end
        
        # Calculate simple RSI
        if length(data.close) >= 15
            rsi = calculate_simple_rsi(data, 14)
            cache[:rsi] = rsi
        end
        
        # Calculate volatility
        if length(data.close) >= 10
            returns = calculate_returns(data, 10)
            volatility = std(returns)
            cache[:volatility] = volatility
        end
    end
    
    function calculate_simple_rsi(data, period=14)
        if length(data.close) < period + 1
            return NaN
        end
        
        closes = closeat(data, -(period+1):-1)
        gains = Float64[]
        losses = Float64[]
        
        for i in 2:length(closes)
            change = closes[i] - closes[i-1]
            if change > 0
                push!(gains, change)
                push!(losses, 0.0)
            else
                push!(gains, 0.0)
                push!(losses, -change)
            end
        end
        
        avg_gain = mean(gains)
        avg_loss = mean(losses)
        
        if avg_loss == 0
            return 100.0
        end
        
        rs = avg_gain / avg_loss
        rsi = 100 - (100 / (1 + rs))
        
        return rsi
    end
    
    function calculate_returns(data, periods)
        if length(data.close) < periods + 1
            return Float64[]
        end
        
        closes = closeat(data, -(periods+1):-1)
        returns = Float64[]
        
        for i in 2:length(closes)
            ret = (closes[i] - closes[i-1]) / closes[i-1]
            push!(returns, ret)
        end
        
        return returns
    end
end
```

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
```julia
# Load multi-timeframe example
s_multi = strategy(:MultiTimeframeExample)

# Load data for multiple timeframes
for tf in [tf"5m", tf"1h", tf"4h", tf"1d"]
    load_ohlcv(s_multi; tf=tf)
end

# Analyze
call!(s_multi, now(), nothing)
```

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
```julia
function safe_data_access(ai::AssetInstance)
    data = ohlcv(ai)
    
    # Always check if data exists
    if isempty(data)
        @debug "No data for $(raw(ai))"
        return nothing
    end
    
    # Check minimum data requirements
    if length(data.close) < 10
        @debug "Insufficient data for $(raw(ai)): $(length(data.close)) candles"
        return nothing
    end
    
    # Safe price access
    current_price = closelast(data)
    if current_price <= 0 || isnan(current_price)
        @warn "Invalid price for $(raw(ai)): $current_price"
        return nothing
    end
    
    return current_price
end
```

### Batch Data Processing
```julia
function process_all_assets_batch(s::Strategy, processor_func)
    results = Dict{String, Any}()
    
    @sync for ai in assets(s)
        @async begin
            symbol = raw(ai)
            try
                result = processor_func(ai)
                results[symbol] = result
            catch e
                @error "Processing failed for $symbol" exception=e
                results[symbol] = nothing
            end
        end
    end
    
    return results
end
```

## Performance Tips

1. **Cache Calculations**: Store expensive calculations in dictionaries
2. **Batch Operations**: Process multiple assets in parallel with `@async`
3. **Validate Data**: Always check for empty or invalid data
4. **Use Appropriate Ranges**: Access only the data you need
5. **Handle Errors**: Wrap data access in try-catch blocks

## See Also

- **[Simple Indicators Example](simple-indicators.md)** - Building technical indicators
- **[Multi-Asset Strategies](multi-asset.md)** - Working with multiple assets
- **[Data API Reference](../api/data.md)** - Complete data API documentation
- **[Data Management Guide](../../guides/data-management.md)** - Comprehensive data guide