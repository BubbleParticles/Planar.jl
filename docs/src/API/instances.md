---
title: "Instances API"
description: "Asset instance management and position tracking"
category: "api-reference"
difficulty: "advanced"
prerequisites: ["getting-started", "strategy-development"]
topics: ["api-reference", "instances", "positions", "assets"]
last_updated: "2025-10-04"
estimated_time: "Reference material"
---

# Instances API

The Instances module manages asset instances within strategies, handling position tracking, margin management, and asset-specific data. It provides the bridge between abstract assets and their concrete usage in trading strategies.

## Overview

The Instances module handles:
- Asset instance creation and management
- Position tracking for spot and margin trading
- OHLCV data association with assets
- Fee calculation and management
- Balance and cash tracking
- Margin and leverage management

## Core Types

### Asset Instance

```julia
# Asset instance - represents an asset within a strategy context
struct AssetInstance{T<:AbstractAsset, E<:ExchangeID}
    asset::T                    # The underlying asset
    data::Dict{TimeFrame, Any}  # OHLCV data by timeframe
    balance::Float64            # Current balance
    # Additional fields for margin trading, fees, etc.
end
```

### Position Types

```julia
# Position sides for margin trading
abstract type PositionSide end
struct Long <: PositionSide end
struct Short <: PositionSide end

# Position information
struct Position
    side::PositionSide
    size::Float64
    entry_price::Float64
    current_price::Float64
    unrealized_pnl::Float64
    margin_used::Float64
end
```

## Asset Instance Management

### Basic Asset Instance Operations

```julia
using Planar
@environment!

# Load a strategy to work with instances
s = strategy(:MyStrategy)

# Access asset instances
instances_list = instances(s)
println("Strategy has $(length(instances_list)) asset instances")

# Get specific asset instance
btc_instance = asset_bysym(s, :BTC)
if !isnothing(btc_instance)
    println("Found BTC instance: $(raw(btc_instance))")
end

# Check if asset is in strategy universe
if inuniverse(:ETH, s)
    eth_instance = asset_bysym(s, :ETH)
    println("ETH is available for trading")
end
```

### Asset Instance Information

```julia
# Get asset information from instance
function analyze_asset_instance(ai::AssetInstance)
    println("Asset Analysis: $(raw(ai))")
    println("=" ^ 40)
    
    # Basic asset info
    println("Symbol: $(raw(ai))")
    println("Base Currency: $(bc(ai))")
    println("Quote Currency: $(qc(ai))")
    
    # Current balance
    current_balance = asset(ai)
    println("Current Balance: $current_balance")
    
    # Price information
    if !isempty(ohlcv(ai))
        current_price = lastprice(ai)
        println("Current Price: $current_price")
        
        # Calculate position value
        position_value = current_balance * current_price
        println("Position Value: $position_value $(qc(ai))")
    end
    
    # Fee information
    taker_fee = takerfees(ai)
    maker_fee = makerfees(ai)
    println("Taker Fee: $(taker_fee * 100)%")
    println("Maker Fee: $(maker_fee * 100)%")
end

# Example usage
for ai in instances(s)[1:3]  # Analyze first 3 assets
    analyze_asset_instance(ai)
    println()
end
```

### Data Access and Management

```julia
# Access OHLCV data for different timeframes
function get_multi_timeframe_data(ai::AssetInstance)
    data_summary = Dict{String, Int}()
    
    # Check available timeframes
    for (tf, data) in ohlcv_dict(ai)
        if !isnothing(data) && !isempty(data)
            data_summary[string(tf)] = length(data.close)
        end
    end
    
    return data_summary
end

# Example: Get data summary for all assets
for ai in instances(s)
    data_info = get_multi_timeframe_data(ai)
    if !isempty(data_info)
        println("$(raw(ai)) data:")
        for (tf, count) in data_info
            println("  $tf: $count candles")
        end
    end
end

# Access specific timeframe data
btc_1h_data = ohlcv(btc_instance, tf"1h")
btc_daily_data = ohlcv(btc_instance, tf"1d")

# Get latest price efficiently
latest_btc_price = lastprice(btc_instance)
```

## Position Management

### Spot Trading Positions

```julia
# Check current asset balance
function get_position_info(ai::AssetInstance)
    balance = asset(ai)
    
    if balance > 0
        println("Long position: $balance $(bc(ai))")
        
        # Calculate position value
        if !isempty(ohlcv(ai))
            price = lastprice(ai)
            value = balance * price
            println("Position value: $value $(qc(ai))")
        end
    else
        println("No position in $(raw(ai))")
    end
    
    return balance
end

# Check if position is dust (too small to trade)
function check_dust_positions(s::Strategy)
    dust_positions = []
    
    for ai in instances(s)
        balance = asset(ai)
        if balance > 0 && isdust(ai, balance)
            push!(dust_positions, (raw(ai), balance))
        end
    end
    
    if !isempty(dust_positions)
        println("Dust positions found:")
        for (symbol, balance) in dust_positions
            println("  $symbol: $balance")
        end
    end
    
    return dust_positions
end

# Get non-dust positions only
function get_tradeable_positions(s::Strategy)
    tradeable = []
    
    for ai in instances(s)
        balance = asset(ai)
        if balance > 0 && !isdust(ai, balance)
            push!(tradeable, ai)
        end
    end
    
    return tradeable
end
```

### Margin Trading Positions

```julia
# For margin strategies, work with positions
function analyze_margin_position(ai::AssetInstance)
    if ishedged(ai)  # Check if asset supports hedged positions
        println("Hedged margin trading available for $(raw(ai))")
    end
    
    # Get position information (if any)
    pos = position(ai)
    if !isnothing(pos)
        println("Position Details:")
        println("  Side: $(posside(pos))")
        println("  Size: $(pos.size)")
        println("  Entry Price: $(entryprice(pos))")
        println("  Current Price: $(price(pos))")
        println("  Unrealized PnL: $(pos.unrealized_pnl)")
        
        # Margin information
        margin_used = margin(pos)
        additional_margin = additional(pos)
        maintenance_margin = maintenance(pos)
        
        println("  Margin Used: $margin_used")
        println("  Additional Margin: $additional_margin")
        println("  Maintenance Margin: $maintenance_margin")
        
        # Liquidation price
        liq_price = liqprice(pos)
        println("  Liquidation Price: $liq_price")
        
        # Leverage
        current_leverage = leverage(pos)
        println("  Leverage: $(current_leverage)x")
    else
        println("No open position for $(raw(ai))")
    end
end

# Position risk management
function check_position_risk(ai::AssetInstance)
    pos = position(ai)
    if isnothing(pos)
        return :no_position
    end
    
    # Check maintenance margin ratio
    mmr = maintenance(pos)
    if mmr < 0.05  # 5% maintenance margin
        return :high_risk
    elseif mmr < 0.1  # 10% maintenance margin
        return :medium_risk
    else
        return :low_risk
    end
end
```

## Fee Management

### Fee Calculation

```julia
# Get fee information for an asset
function get_fee_structure(ai::AssetInstance)
    taker_fee = takerfees(ai)
    maker_fee = makerfees(ai)
    max_fee = maxfees(ai)
    min_fee = minfees(ai)
    
    return (
        taker = taker_fee,
        maker = maker_fee,
        max = max_fee,
        min = min_fee
    )
end

# Calculate trading fees
function calculate_trade_fee(ai::AssetInstance, amount::Float64, price::Float64, is_maker::Bool=false)
    fee_rate = is_maker ? makerfees(ai) : takerfees(ai)
    trade_value = amount * price
    fee_amount = trade_value * fee_rate
    
    # Apply min/max fee limits
    min_fee = minfees(ai)
    max_fee = maxfees(ai)
    
    fee_amount = max(fee_amount, min_fee)
    fee_amount = min(fee_amount, max_fee)
    
    return fee_amount
end

# Example: Calculate fees for all assets
function analyze_trading_costs(s::Strategy, trade_amount::Float64=1000.0)
    println("Trading Cost Analysis (Trade Amount: $trade_amount)")
    println("=" ^ 50)
    
    for ai in instances(s)
        if !isempty(ohlcv(ai))
            price = lastprice(ai)
            amount = trade_amount / price
            
            taker_fee = calculate_trade_fee(ai, amount, price, false)
            maker_fee = calculate_trade_fee(ai, amount, price, true)
            
            println("$(raw(ai)):")
            println("  Taker Fee: $(round(taker_fee, digits=4)) $(qc(ai))")
            println("  Maker Fee: $(round(maker_fee, digits=4)) $(qc(ai))")
            println("  Fee Savings: $(round(taker_fee - maker_fee, digits=4)) $(qc(ai))")
            println()
        end
    end
end
```

## Cash and Balance Management

### Cash Operations

```julia
# Get available cash for trading
available_cash = freecash(s)
total_cash = cash(s)
committed_cash = committed(s)

println("Cash Summary:")
println("  Total: $total_cash")
println("  Available: $available_cash")
println("  Committed: $committed_cash")

# Check if strategy cash is compatible with universe
if iscashable(s)
    println("Strategy cash is compatible with asset universe")
else
    println("Warning: Cash/asset mismatch detected")
end
```

### Portfolio Value Calculation

```julia
# Calculate total portfolio value
function calculate_portfolio_value(s::Strategy)
    total_value = 0.0
    cash_currency = qc(cash(s))  # Get cash currency
    
    # Add cash value
    total_value += freecash(s)
    
    # Add asset values
    for ai in instances(s)
        balance = asset(ai)
        if balance > 0 && !isempty(ohlcv(ai))
            price = lastprice(ai)
            asset_value = balance * price
            
            # Convert to cash currency if needed
            if qc(ai) != cash_currency
                # Apply conversion rate (simplified)
                conversion_rate = get_conversion_rate(qc(ai), cash_currency)
                asset_value *= conversion_rate
            end
            
            total_value += asset_value
        end
    end
    
    return total_value
end

# Portfolio allocation analysis
function analyze_portfolio_allocation(s::Strategy)
    total_value = calculate_portfolio_value(s)
    allocations = Dict{String, Float64}()
    
    # Cash allocation
    cash_allocation = freecash(s) / total_value
    allocations["CASH"] = cash_allocation
    
    # Asset allocations
    for ai in instances(s)
        balance = asset(ai)
        if balance > 0 && !isempty(ohlcv(ai))
            price = lastprice(ai)
            asset_value = balance * price
            allocation = asset_value / total_value
            allocations[raw(ai)] = allocation
        end
    end
    
    # Display results
    println("Portfolio Allocation:")
    for (asset, allocation) in sort(collect(allocations), by=x->x[2], rev=true)
        percentage = round(allocation * 100, digits=2)
        println("  $asset: $percentage%")
    end
    
    return allocations
end
```

## Performance Optimization

### Efficient Instance Operations

```julia
# Batch operations on instances
function batch_update_prices!(instances_list::Vector{AssetInstance})
    @sync for ai in instances_list
        @async begin
            if !isempty(ohlcv(ai))
                # Update cached price or perform calculations
                current_price = lastprice(ai)
                setattr!(ai, :cached_price, current_price)
            end
        end
    end
end

# Efficient filtering
function filter_instances_by_criteria(s::Strategy; 
                                    min_balance=0.0, 
                                    min_volume=0.0,
                                    asset_types=nothing)
    filtered = AssetInstance[]
    
    for ai in instances(s)
        # Balance filter
        if asset(ai) < min_balance
            continue
        end
        
        # Volume filter
        if min_volume > 0 && !isempty(ohlcv(ai))
            recent_volume = volumeat(ohlcv(ai), -1)
            if recent_volume < min_volume
                continue
            end
        end
        
        # Asset type filter
        if !isnothing(asset_types) && !(ai.asset.type in asset_types)
            continue
        end
        
        push!(filtered, ai)
    end
    
    return filtered
end

# Memory-efficient data access
function get_latest_prices_batch(instances_list::Vector{AssetInstance})
    prices = Dict{String, Float64}()
    
    for ai in instances_list
        if !isempty(ohlcv(ai))
            prices[raw(ai)] = lastprice(ai)
        end
    end
    
    return prices
end
```

## Integration Examples

### Strategy Integration

```julia
# Example: Asset instance usage in strategy
module InstanceExampleStrategy
    @strategyenv!
    
    function call!(s::S, current_time::DateTime, ctx) where {S<:Strategy}
        # Analyze all asset instances
        for ai in instances(s)
            # Skip if no data
            if isempty(ohlcv(ai))
                continue
            end
            
            # Get current position
            current_balance = asset(ai)
            current_price = lastprice(ai)
            
            # Check if we have a position
            if current_balance > 0 && !isdust(ai, current_balance)
                # We have a position - check for exit signals
                position_value = current_balance * current_price
                
                # Simple profit-taking example
                if position_value > 1000.0  # Take profit above $1000
                    # Create sell order (implementation depends on executor)
                    @info "Taking profit on $(raw(ai))" value=position_value
                end
            else
                # No position - check for entry signals
                available_cash = freecash(s)
                
                if available_cash > 100.0  # Minimum trade size
                    # Simple entry logic example
                    if length(ohlcv(ai).close) >= 20
                        sma_20 = mean(closeat(ohlcv(ai), -20:-1))
                        if current_price > sma_20 * 1.02  # Price 2% above SMA
                            @info "Entry signal for $(raw(ai))" price=current_price sma=sma_20
                        end
                    end
                end
            end
        end
    end
end
```

## Complete API Reference

```@autodocs
Modules = [Planar.Engine.Instances]
```

## See Also

- **[Instruments API](instruments.md)** - Financial instrument definitions
- **[Strategies API](strategies.md)** - Strategy base classes and interfaces
- **[Data API](data.md)** - Data structures and management
- **[Executors API](executors.md)** - Order execution and management
- **[Strategy Development Guide](../guides/strategy-development.md)** - Building trading strategies
- **[Advanced Trading Guide](../advanced/margin-trading.md)** - Margin and derivative trading
