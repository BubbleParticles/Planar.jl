---
title: "Engine API"
description: "Core execution engine for backtesting, paper trading, and live trading"
category: "api-reference"
difficulty: "advanced"
prerequisites: ["getting-started", "strategy-development"]
topics: ["api-reference", "engine", "execution", "backtesting"]
last_updated: "2025-10-04"
estimated_time: "Reference material"
---

# Engine API

The Engine module provides the core execution framework for Planar strategies. It handles data management, order execution, and coordinates between different execution modes (simulation, paper trading, and live trading).

## Overview

The Engine serves as the central coordinator that:
- Manages strategy execution across different modes
- Handles data loading and OHLCV management
- Coordinates with exchanges and executors
- Provides unified interfaces for backtesting and live trading

## Core Functions

### Data Management

#### OHLCV Data Functions

```julia
# Load historical OHLCV data for a strategy
load_ohlcv(s::Strategy; tf=s.config.min_timeframe, pairs=...)

# Fetch fresh OHLCV data from exchange
fetch_ohlcv(s::Strategy; sandbox=false, tf=s.config.min_timeframe, pairs=...)

# Fetch and store OHLCV data for all strategy assets
fetch_ohlcv!(s::Strategy)

# Update existing OHLCV data with latest candles
update_ohlcv!(s::Strategy; kwargs...)
```

#### Usage Examples

```julia
using Planar
@environment!

# Load a strategy
s = strategy(:MyStrategy)

# Load historical data for all strategy assets
load_ohlcv(s)
println("Loaded data for $(length(assets(s))) assets")

# Fetch latest data from exchange
fetch_ohlcv(s; limit=100)  # Get last 100 candles

# Update data for live trading
update_ohlcv!(s; limit=10)  # Get last 10 candles to update
```

#### Advanced Data Operations

```julia
# Load data for specific timeframe and pairs
btc_data = load_ohlcv(s; tf=tf"1h", pairs=["BTC/USDT"])

# Fetch data with custom parameters
historical_data = fetch_ohlcv(s; 
    tf=tf"4h", 
    pairs=["ETH/USDT", "BTC/USDT"],
    limit=500,
    since=DateTime("2024-01-01")
)

# Parallel data fetching for multiple assets
@sync for ai in assets(s)
    @async begin
        symbol = raw(ai)
        data = fetch_ohlcv(exchange(s), string(s.timeframe), symbol)
        # Process data...
    end
end
```

### Strategy Execution

#### Execution Control

```julia
# Fill strategy with current market data
fill!(s::Strategy)

# Reset strategy state
reset!(s::Strategy)

# Set strategy to default configuration
default!(s::Strategy)
```

#### Example: Strategy Lifecycle

```julia
# Initialize strategy
s = strategy(:MyStrategy)

# Load initial data
load_ohlcv(s)

# Reset to clean state
reset!(s)

# Fill with current data
fill!(s)

# Strategy is now ready for execution
```

### Exchange Integration

#### Exchange Access

```julia
# Get exchange instance for strategy
exc = exchange(s::Strategy)

# Get exchange ID
exc_id = exchangeid(s::Strategy)

# Check if exchange is in sandbox mode
is_sandbox = issandbox(s::Strategy)

# Get account information
account_info = account(s::Strategy)
```

#### Example: Exchange Operations

```julia
s = strategy(:MyStrategy)

# Get exchange and check status
exc = exchange(s)
println("Connected to: $(exc.id)")
println("Sandbox mode: $(issandbox(s))")

# Get account information
acc = account(s)
println("Trading account: $acc")

# Access exchange-specific functions
markets = marketsid(s)
println("Available markets: $markets")
```

## Data Structures and Types

### Core Types

The Engine module works with several key types:

```julia
# Strategy execution modes
abstract type ExecMode end
struct Sim <: ExecMode end      # Simulation/backtesting
struct Paper <: ExecMode end    # Paper trading
struct Live <: ExecMode end     # Live trading

# Margin modes
abstract type MarginMode end
struct NoMargin <: MarginMode end    # Spot trading
struct Isolated <: MarginMode end    # Isolated margin
struct Cross <: MarginMode end       # Cross margin
```

### Data Handlers

```julia
# OHLCV data handling
struct OHLCVData
    open::Vector{Float64}
    high::Vector{Float64}
    low::Vector{Float64}
    close::Vector{Float64}
    volume::Vector{Float64}
    timestamp::Vector{DateTime}
end

# Access OHLCV data
ohlcv_data = ohlcv(asset_instance)
latest_close = closelast(ohlcv_data)
latest_volume = volumeat(ohlcv_data, -1)  # Last volume
```

## Integration Patterns

### Backtesting Pattern

```julia
using Planar
@environment!

# Load strategy for simulation
s = strategy(:MyStrategy, Sim())

# Load historical data
load_ohlcv(s)

# Run backtest
results = backtest(s, 
    from=DateTime("2024-01-01"),
    to=DateTime("2024-12-31")
)

# Analyze results
println("Total return: $(results.total_return)")
println("Sharpe ratio: $(results.sharpe_ratio)")
```

### Paper Trading Pattern

```julia
# Load strategy for paper trading
s = strategy(:MyStrategy, Paper())

# Load initial data
load_ohlcv(s)

# Start paper trading (runs continuously)
start_paper_trading(s)

# Monitor in real-time
while is_running(s)
    update_ohlcv!(s)  # Get latest data
    # Strategy automatically executes
    sleep(60)  # Wait 1 minute
end
```

### Live Trading Pattern

```julia
# Load strategy for live trading
s = strategy(:MyStrategy, Live())

# Verify connection and funds
exc = exchange(s)
@assert !issandbox(exc) "Should not be in sandbox for live trading"

balance = freecash(s)
@assert balance > 1000.0 "Insufficient funds for live trading"

# Load data and start
load_ohlcv(s)
start_live_trading(s)
```

## Performance Optimization

### Efficient Data Access

```julia
# Pre-allocate data structures
function optimize_strategy_data(s::Strategy)
    # Cache frequently accessed data
    for ai in assets(s)
        # Pre-load OHLCV data
        ohlcv_data = ohlcv(ai)
        
        # Cache common calculations
        if length(ohlcv_data) >= 20
            sma_20 = mean(closeat(ohlcv_data, -20:-1))
            setattr!(ai, :sma_20, sma_20)
        end
    end
end
```

### Batch Operations

```julia
# Batch data updates
function batch_update_data(s::Strategy)
    symbols = [raw(ai) for ai in assets(s)]
    
    # Single API call for all symbols
    all_data = fetch_ohlcv(exchange(s), string(s.timeframe), symbols)
    
    # Update all assets
    for ai in assets(s)
        symbol = raw(ai)
        if haskey(all_data, symbol)
            ai.data[s.timeframe] = all_data[symbol].data
        end
    end
end
```

## Error Handling

### Robust Data Loading

```julia
function safe_load_ohlcv(s::Strategy; retries=3)
    for attempt in 1:retries
        try
            load_ohlcv(s)
            return true
        catch e
            @warn "Data loading failed (attempt $attempt/$retries)" exception=e
            if attempt == retries
                @error "Failed to load data after $retries attempts"
                return false
            end
            sleep(2^attempt)  # Exponential backoff
        end
    end
end
```

### Exchange Connection Handling

```julia
function ensure_exchange_connection(s::Strategy)
    try
        exc = exchange(s)
        # Test connection
        markets = marketsid(s)
        return true
    catch e
        @error "Exchange connection failed" exception=e
        return false
    end
end
```

## Complete API Reference

```@autodocs
Modules = [Planar.Engine]
```

## See Also

- **[Strategies API](strategies.md)** - Strategy base classes and interfaces
- **[Data API](data.md)** - Data structures and management
- **[Executors API](executors.md)** - Order execution and management
- **[Execution Modes Guide](../guides/execution-modes.md)** - Understanding sim, paper, and live modes
- **[Data Management Guide](../guides/data-management.md)** - Working with market data
