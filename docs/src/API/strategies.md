---
title: "Strategies API"
description: "Strategy base classes, interfaces, and core functionality"
category: "api-reference"
difficulty: "advanced"
prerequisites: ["getting-started", "strategy-development"]
topics: ["api-reference", "strategies", "trading"]
last_updated: "2025-10-04"
estimated_time: "Reference material"
---

# Strategies API

The Strategies module provides the core framework for building and managing trading strategies in Planar. It includes the base `Strategy` type, execution interfaces, and essential functions for strategy development.

## Overview

The `Strategy` type is the central component of the Planar framework. It encapsulates:
- Strategy configuration and parameters
- Asset universe and market data
- Order management and execution state
- Cash and position tracking
- Exchange connectivity

## Core Types

### Strategy Types

```julia
# Base strategy type
Strategy{X<:ExecMode,N,E<:ExchangeID,M<:MarginMode,C}

# Execution mode variants
SimStrategy     # Simulation/backtesting
PaperStrategy   # Paper trading with real data
LiveStrategy    # Live trading with real money

# Margin mode variants
IsolatedStrategy  # Isolated margin trading
CrossStrategy     # Cross margin trading
NoMarginStrategy  # Spot trading only
```

### Usage Examples

#### Creating a Strategy

```julia
using Planar
@strategyenv!

# Define strategy module
module MyStrategy
    @strategyenv!
    
    # Strategy configuration
    const DESCRIPTION = "Example moving average strategy"
    const TIMEFRAME = tf"1h"
    
    # Strategy logic
    function call!(s::S, current_time::DateTime, ctx) where {S<:Strategy}
        # Your strategy logic here
        for ai in assets(s)
            price = lastprice(ai)
            # Make trading decisions...
        end
    end
end

# Load the strategy
s = strategy(:MyStrategy)
```

#### Accessing Strategy Information

```julia
# Get strategy assets
asset_list = assets(s)
println("Trading $(length(asset_list)) assets")

# Check available cash
available_cash = freecash(s)
total_cash = cash(s)
committed_cash = committed(s)

# Get exchange information
exc = exchange(s)
exchange_id = exchangeid(s)

# Check execution mode
if issim(s)
    println("Running in simulation mode")
elseif ispaper(s)
    println("Running in paper trading mode")
elseif islive(s)
    println("Running in live trading mode")
end
```

#### Working with Assets

```julia
# Access individual assets
btc_asset = asset_bysym(s, :BTC)
eth_instance = instances(s)[1]  # First asset instance

# Check if asset is in universe
if inuniverse(:BTC, s)
    println("BTC is in strategy universe")
end

# Get market data
ohlcv_data = ohlcv(btc_asset)
last_price = lastprice(btc_asset)
```

## Strategy Interface Functions

### Core Interface

The strategy interface defines the main entry points that your strategy must implement:

```julia
# Main strategy execution function
call!(s::Strategy, current_time::DateTime, ctx)

# Strategy lifecycle functions
call!(::Type{<:Strategy}, cfg, ::LoadStrategy)  # Strategy construction
call!(s::Strategy, ::StartStrategy)             # Before strategy starts
call!(s::Strategy, ::StopStrategy)              # After strategy stops
call!(s::Strategy, ::ResetStrategy)             # After strategy reset

# Configuration functions
call!(::Type{<:Strategy}, ::StrategyMarkets)    # Define market symbols
call!(s::Strategy, ::WarmupPeriod)              # Define lookback period
```

#### Implementation Example

```julia
module ExampleStrategy
    @strategyenv!
    
    # Define markets to trade
    function call!(::Type{S}, ::StrategyMarkets) where {S<:Strategy}
        return ["BTC/USDT", "ETH/USDT"]
    end
    
    # Define warmup period
    function call!(s::S, ::WarmupPeriod) where {S<:Strategy}
        return 100  # Need 100 periods of historical data
    end
    
    # Main strategy logic
    function call!(s::S, current_time::DateTime, ctx) where {S<:Strategy}
        for ai in assets(s)
            # Get current price
            price = lastprice(ai)
            
            # Simple moving average example
            if length(ohlcv(ai)) >= 20
                sma_20 = mean(closeat(ohlcv(ai), -20:-1))
                
                if price > sma_20 * 1.02  # Price 2% above SMA
                    # Consider buying
                    available = freecash(s)
                    if available > 100.0  # Minimum order size
                        # Place buy order logic here
                    end
                end
            end
        end
    end
end
```

## Cash and Position Management

### Cash Functions

```julia
# Get total strategy cash
total = cash(s)

# Get available (uncommitted) cash
available = freecash(s)

# Get cash committed to pending orders
busy = committed(s)

# Check if strategy cash matches universe
is_valid = iscashable(s)
```

### Position Information

```julia
# Get strategy holdings (assets with non-zero balance)
current_holdings = s.holdings

# Check margin mode
margin_mode = marginmode(s)

# For margin strategies
if isa(s, MarginStrategy)
    # Access margin-specific functionality
    leverage_info = leverage(s)
end
```

## Order Management

### Order Access

```julia
# Get active buy orders for an asset
buy_orders = s.buyorders[asset_instance]

# Get active sell orders for an asset  
sell_orders = s.sellorders[asset_instance]

# Iterate through all orders
for (asset, orders) in s.buyorders
    for (price_time, order) in orders
        println("Buy order: $(order.amount) at $(price_time.price)")
    end
end
```

## Utility Functions

### Strategy Identification

```julia
# Get strategy module
strategy_module = s.self

# Get strategy name
strategy_name = nameof(typeof(s))

# Get strategy configuration
config = s.config
```

### Thread Safety

```julia
# The strategy includes a lock for thread-safe operations
lock(s.lock) do
    # Thread-safe operations here
    # Modify strategy state safely
end
```

## Common Patterns

### Data Loading Pattern

```julia
# Load historical data for strategy
load_ohlcv(s)

# Fetch latest data
fetch_ohlcv!(s)

# Update specific timeframe data
update_ohlcv!(s; limit=100)
```

### Error Handling Pattern

```julia
function call!(s::S, current_time::DateTime, ctx) where {S<:Strategy}
    try
        # Strategy logic here
        for ai in assets(s)
            # Safe operations
        end
    catch e
        @error "Strategy execution error" exception=e
        # Handle error appropriately
    end
end
```

### Performance Pattern

```julia
function call!(s::S, current_time::DateTime, ctx) where {S<:Strategy}
    # Batch operations when possible
    @sync for ai in assets(s)
        @async begin
            # Parallel processing of assets
            process_asset(ai, current_time)
        end
    end
end
```

## Complete API Reference

```@autodocs
Modules = [Strategies]
```

## See Also

- **[Strategy Development Guide](../guides/strategy-development.md)** - Complete guide to building strategies
- **[Engine API](engine.md)** - Core execution engine functions
- **[Executors API](executors.md)** - Order execution and management
- **[Instances API](instances.md)** - Asset instance management
- **[Getting Started](../getting-started/first-strategy.md)** - Your first strategy tutorial
