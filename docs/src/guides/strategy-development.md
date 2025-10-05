---
title: "Strategy Development Guide"
description: "Complete guide to developing trading strategies in Planar"
category: "guides"
difficulty: "intermediate"
topics: [strategy-development, technical-indicators, backtesting]
last_updated: "2025-10-04"
---

# Strategy Development Guide

<!--
Keywords: [strategy](../guides/strategy-development.md) development, call! function, [dispatch system](../guides/[strategy](../guides/strategy-development.md)-development.md#dispatch-system), [margin trading](../guides/[strategy](../guides/strategy-development.md)-development.md#margin-trading-concepts), [backtesting](../guides/execution-modes.md#simulation)-mode), [optimization](../optimization.md), [Julia](https://julialang.org/) modules, trading logic
Description: Comprehensive guide to developing trading [strategies](../guides/strategy-development.md) in Planar using [Julia](https://julialang.org/)'s [dispatch system](../guides/strategy-development.md#dispatch-system), covering everything from basic concepts to advanced patterns.
-->

This comprehensive guide covers everything you need to know about developing trading [strategies](../guides/strategy-development.md) in Planar. From basic concepts to advanced patterns, you'll learn how to build robust, profitable trading systems using [Julia](https://julialang.org/)'s powerful [dispatch system](../guides/strategy-development.md#dispatch-system).

## Quick Navigation

- **[Strategy Fundamentals](#strategy-fundamentals)** - Core concepts and architecture
- **[Creating Strategies](#creating-[strategies](../guides/strategy-development.md))** - Interactive and manual setup
- **[Strategy Interface](#strategy-interface)** - Understanding the call! dispatch system
- **[Advanced Examples](#advanced-examples)** - Multi-[timeframe](../guides/data-management.md#timeframes), portfolio, and [optimization](../optimization.md) strategies
- **[Best Practices](#best-practices)** - Code organization and performance tips
- **[Troubleshooting](#[troubleshooting](../troubleshooting/))** - Common issues and solutions

## Prerequisites

Before diving into strategy development, ensure you have:

- Completed the [Getting Started Guide](../getting-started/index.md)
- Basic understanding of [Data Management](data-management.md)
- Familiarity with [Execution Modes](execution-modes.md)

## Related Topics

- **[Optimization]([optimization](../optimization.md).md)** - Parameter tuning and [backtesting](../guides/execution-modes.md#simulation)-mode)
- **[Plotting](../plotting.md)** - Visualizing strategy performance
- **[Customization](../customizations/customizations.md)** - Extending strategy functionality

## Strategy Fundamentals

### Architecture Overview

Planar strategies are built around Julia's powerful dispatch system, enabling clean separation of concerns and easy customization. Each strategy is a Julia module that implements specific interface methods through the `call!` function dispatch pattern.

#### Core Components

- **Strategy Module**: Contains your trading logic and [configuration](../config.md)
- **Dispatch System**: Uses `call!` methods to handle different strategy events
- **Asset Universe**: Collection of tradeable assets managed by the strategy
- **Execution Modes**: Sim ([backtesting](../guides/execution-modes.md#simulation)-mode)), Paper (simulated live), and Live trading
- **Margin Support**: Full support for isolated and [cross margin](../guides/strategy-development.md#margin-modes) trading

#### Strategy Type Hierarchy

```julia
Strategy{Mode, Name, Exchange, Margin, QuoteCurrency}
```

Where:
- `Mode`: Execution mode (Sim, Paper, Live)
- `Name`: Strategy module name as Symbol
- `Exchange`: Exchange identifier
- `Margin`: Margin mode (NoMargin, Isolated, Cross)
- `QuoteCurrency`: Base currency symbol

### Dispatch System

The strategy interface uses Julia's [multiple dispatch](../guides/strategy-development.md#dispatch-system) through the `call!` function. This pattern allows you to define different behaviors for different contexts while maintaining clean, extensible code.

#### Key Dispatch Patterns

**Type vs Instance Dispatch**:
- Methods dispatching on `Type{<:Strategy}` are called before strategy construction
- Methods dispatching on strategy instances are called during runtime

```julia
# Example within a strategy module context
try
    module ExampleStrategy
    using Planar
    @strategyenv!
    
    # Called during strategy loading (before construction)
    function call!(::Type{<:SC}, config, ::LoadStrategy)
        # Strategy initialization logic
        @info "Loading strategy with config: $config"
    end
    
    # Called during strategy execution (after construction)
    function call!(s::SC, ts::DateTime, ctx)
        # Trading logic executed on each timestep
        @info "Executing strategy at $ts"
    end
    
    end  # module
    @info "Example strategy module defined successfully"
catch e
    @warn "Strategy module definition failed: $e"
    @info "This is normal in some testing environments"
end
```

**Action-Based Dispatch**:
```julia
# Strategy lifecycle events
call!(s::SC, ::ResetStrategy)     # Called when strategy is reset
call!(s::SC, ::StartStrategy)     # Called when strategy starts
call!(s::SC, ::StopStrategy)      # Called when strategy stops
call!(s::SC, ::WarmupPeriod)      # Returns required lookback period

# Market and optimization events
call!(::Type{<:SC}, ::StrategyMarkets)  # Returns tradeable markets
call!(s::SC, ::OptSetup)               # Optimization [configuration](../config.md)
call!(s::SC, params, ::OptRun)         # Optimization execution
```

#### Exchange-Specific Dispatch

You can customize behavior for specific [exchanges](../exchanges.md):

```julia
# Example within a strategy module context
module ExchangeSpecificStrategy
using Planar
@strategyenv!

# Default behavior for all exchanges
function call!(::Type{<:SC}, ::StrategyMarkets)
    ["BTC/USDT", "ETH/USDT", "SOL/USDT"]
end

# Specific behavior for Bybit
function call!(::Type{<:SC{ExchangeID{:bybit}}}, ::StrategyMarkets)
    ["BTC/USDT", "ETH/USDT", "ATOM/USDT"]  # Different asset selection
end

end  # module
```

### Margin Trading Concepts

Planar provides comprehensive [margin trading](../guides/strategy-development.md#margin-trading-concepts) support with proper position management and risk controls.

#### Margin Modes

**NoMargin**: Spot trading only
```julia
const MARGIN = NoMargin
```

**Isolated Margin**: Each position has independent margin
```julia
const MARGIN = Isolated

# Position-specific leverage updates
function update_leverage!(s, ai, pos::Long, leverage)
    call!(s, ai, leverage, UpdateLeverage(); pos=Long())
end
```

**Cross Margin**: Shared margin across all positions
```julia
const MARGIN = Cross
```

#### Position Management

```julia
# Example within a strategy module context
module PositionManagementStrategy
using Planar
@strategyenv!

# Check position direction
function handle_position(s, ai, position)
    if inst.islong(position)
        # Handle long position logic
        @info "Managing long position"
    elseif inst.isshort(position)
        # Handle short position logic
        @info "Managing short position"
    end
end

end  # module
end

# Access position information
pos = inst.position(ai)  # Get current position
long_pos = inst.position(ai, Long())   # Get long position
short_pos = inst.position(ai, Short()) # Get short position

# Position sizing with margin
amount = freecash(s) / leverage / price
```

#### Risk Management Patterns

```julia
# Dynamic leverage based on volatility
function calculate_leverage(s, ai, ats)
    volatility = highat(ai, ats) / lowat(ai, ats) - 1.0
    base_leverage = attr(s, :base_leverage, 2.0)
    max_leverage = attr(s, :max_leverage, 10.0)
    
    clamp(base_leverage / volatility, 1.0, max_leverage)
end

# Position size limits
function validate_position_size(s, ai, amount)
    max_position = freecash(s) * attr(s, :max_position_pct, 0.1)
    min(amount, max_position / closeat(ai, available(s.timeframe, now())))
end
```

## Creating Strategies

### Interactive Strategy Generator

The simplest way to create a strategy is using the interactive generator, which prompts for all required [configuration](../config.md) options:

```julia
julia> using Planar
julia> Planar.generate_strategy()
Strategy name: : MyNewStrategy

Timeframe:
   1m
 > 5m
   15m
   1h
   1d

Select [exchange]([exchanges](../exchanges.md).md) by:
 > volume
   markets
   nokyc

 > binance
   bitforex
   okx
   xt
   coinbase

Quote currency:
   USDT
   USDC
 > BTC
   ETH
   DOGE

Margin mode:
 > NoMargin
   Isolated

Activate strategy project at /path/to/Planar.jl/user/strategies/MyNewStrategy? [y]/n: y

Add project dependencies (comma separated): Indicators
   Resolving package versions...
   [...]
  Activating project at `/path/to/Planar.jl/user/strategies/MyNewStrategy`

┌ Info: New Strategy
│   name = "MyNewStrategy"
│   [exchange](../exchanges.md) = :binance
└   [timeframe](../guides/data-management.md#timeframes) = "5m"
[ Info: Config file updated

Load strategy? [y]/n: 

julia> s = ans
```

### Non-Interactive Strategy Creation

You can also create strategies programmatically without user interaction:

```julia
using Planar

# Skip interaction by passing ask=false
Planar.generate_strat("MyNewStrategy", ask=false, exchange=:myexc)

# Or use a configuration object
cfg = Planar.Config(exchange=:myexc)
Planar.generate_strat("MyNewStrategy", cfg)
```

### Manual Strategy Setup

If you want to create a strategy manually you can either:
- Copy the `user/strategies/Template.jl` to a new file in the same directory and customize it
- Generate a new project in `user/strategies` and customize `Template.jl` to be your project entry file

For more advanced setups you can also use `Planar` as a library, and construct the strategy object directly from your own module:

```julia
using Planar
using MyDownStreamModule
s = Planar.Engine.Strategies.strategy(MyDownStreamModule)
```

### Project-Based Strategies

For complex strategies, use the project structure:

```
user/strategies/MyStrategy/
├── Project.toml          # Package definition and dependencies
├── Manifest.toml         # Locked dependency versions
├── src/
│   ├── MyStrategy.jl     # Main strategy module
│   ├── indicators.jl     # Custom indicators
│   ├── utils.jl         # Utility functions
│   └── risk.jl          # Risk management
└── test/
    └── test_strategy.jl  # Strategy tests
```

## Strategy Interface

### Loading a Strategy

Strategies are instantiated by loading a Julia module at runtime:

```julia
using Planar

# Create configuration object
cfg = Config(exchange=:kucoin)

# Load the Example strategy
s = strategy(:Example, cfg)
```

The strategy name corresponds to the module name, which is imported from:
- `user/strategies/Example.jl` (single file strategy)
- `user/strategies/Example/src/Example.jl` (project-based strategy)

### Strategy Type Structure

```julia
julia> typeof(s)
Engine.Strategies.Strategy37{:Example, ExchangeTypes.ExchangeID{:kucoin}(), :USDT}
```

### Basic Strategy Module

```julia
module Example
using Planar

const DESCRIPTION = "Example strategy"
const EXC = :phemex
const MARGIN = NoMargin
const TF = tf"1m"

@strategyenv!

function call!(::Type{<:SC}, ::LoadStrategy, config)
    assets = marketsid(S)
    s = Strategy(Example, assets; config)
    return s
end

end
```

### Function Signature Convention

The `call!` function follows a consistent signature pattern:
- **Subject**: Either strategy type (`Type{<:Strategy}`) or instance (`Strategy`)
- **Arguments**: Function-specific parameters
- **Verb**: Action type that determines the dispatch (e.g., `::LoadStrategy`)
- **Keyword Arguments**: Optional parameters

```julia
call!(subject, args..., ::Verb; kwargs...)
```

### Strategy Lifecycle

Understanding the strategy lifecycle is crucial for proper implementation:

1. **Module Loading**: Strategy module is imported
2. **Type Construction**: Strategy type is created with parameters
3. **Instance Creation**: `call!(Type{<:SC}, config, ::LoadStrategy)` is called
4. **Reset/Initialization**: `call!(s::SC, ::ResetStrategy)` is called
5. **Execution Loop**: `call!(s::SC, timestamp, context)` is called repeatedly
6. **Cleanup**: `call!(s::SC, ::StopStrategy)` is called when stopping

### Essential Strategy Methods

#### Required Methods

```julia
# Example within a strategy module context
module MainExecutionStrategy
using Planar
@strategyenv!

# Helper functions for trading logic
function should_buy(s, ai, ats)
    # Placeholder logic - replace with your indicators
    return rand() > 0.7
end

function should_sell(s, ai, ats)
    # Placeholder logic - replace with your indicators
    return rand() > 0.8
end

# Main execution method - called on each timestep
function call!(s::SC, ts::DateTime, ctx)
    ats = available(s.timeframe, ts)
    foreach(s.universe) do ai
        # Your trading logic here
        if should_buy(s, ai, ats)
            buy!(s, ai, ats, ts)
        elseif should_sell(s, ai, ats)
            sell!(s, ai, ats, ts)
        end
    end
end

end  # module

# Define tradeable markets
function call!(::Type{<:SC}, ::StrategyMarkets)
    ["BTC/USDT", "ETH/USDT", "SOL/USDT"]
end
```

#### Optional Methods

```julia
# Example within a strategy module context
module OptionalMethodsStrategy
using Planar
@strategyenv!

# Helper function for setup
function setup_watchers(s)
    @info "Setting up watchers for $(typeof(s))"
end

# Custom strategy loading
function call!(::Type{<:SC}, config, ::LoadStrategy)
    s = default_load(@__MODULE__, SC, config)
    # Custom initialization logic
    @info "Custom loading for strategy"
    return s
end

# Strategy reset behavior
function call!(s::SC, ::ResetStrategy)
    # Initialize parameters
    s.attrs[:param1] = 1.0
    s.attrs[:param2] = 2.0
    
    # Setup watchers for live/paper mode
    if s isa Union{PaperStrategy, LiveStrategy}
        setup_watchers(s)
    end
end

end  # module
end

# Warmup period for data requirements
function call!(s::SC, ::WarmupPeriod)
    Day(30)  # Require 30 days of historical data
end
```

### Advanced Dispatch Patterns

#### Conditional Dispatch by Mode

```julia
# Example within a strategy module context
module ConditionalDispatchStrategy
using Planar
@strategyenv!

# Helper functions
function simple_trading_logic(s, ts)
    @info "Running simple backtesting logic at $ts"
end

function robust_trading_logic(s, ts)
    @info "Running robust live trading logic at $ts"
end

# Different behavior for different execution modes
function call!(s::Strategy{Sim}, ts::DateTime, ctx)
    # Backtesting-specific logic (faster, simplified)
    simple_trading_logic(s, ts)
end

function call!(s::Strategy{<:Union{Paper,Live}}, ts::DateTime, ctx)
    # Live trading logic (more robust, with error handling)
    robust_trading_logic(s, ts)
end

end  # module
    robust_trading_logic(s, ts)
end
```

#### Parameter-Based Dispatch

```julia
# Different strategies based on margin mode
function execute_trade(s::Strategy{<:Any, <:Any, <:Any, NoMargin}, ai, amount)
    # Spot trading logic
    place_spot_order(s, ai, amount)
end

function execute_trade(s::Strategy{<:Any, <:Any, <:Any, <:MarginMode}, ai, amount)
    # Margin trading logic with leverage
    leverage = calculate_leverage(s, ai)
    place_margin_order(s, ai, amount, leverage)
end
```

## Advanced Examples

### Multi-Timeframe Strategy

```julia
module MultiTimeframe
using Planar

const DESCRIPTION = "Multi-timeframe trend following"
const EXC = :binance
const MARGIN = NoMargin
const TF = tf"5m"  # Primary execution timeframe

@strategyenv!

function call!(s::SC, ::ResetStrategy)
    # Configure multiple timeframes
    s.attrs[:timeframes] = [tf"5m", tf"1h", tf"4h"]
    s.attrs[:trend_threshold] = 0.02
    s.attrs[:position_size] = 0.1
end

function call!(s::SC, ts::DateTime, ctx)
    ats = available(s.timeframe, ts)
    
    foreach(s.universe) do ai
        # Get signals from multiple timeframes
        signals = Dict{TimeFrame, Float64}()
        
        for tf in s.attrs[:timeframes]
            signals[tf] = calculate_trend_signal(ai, tf, ats)
        end
        
        # Combine signals with timeframe weighting
        combined_signal = combine_signals(signals)
        
        if combined_signal > s.attrs[:trend_threshold]
            enter_long_position(s, ai, ats, ts)
        elseif combined_signal < -s.attrs[:trend_threshold]
            exit_long_position(s, ai, ats, ts)
        end
    end
end

function calculate_trend_signal(ai, timeframe, ats)
    # Calculate trend strength for specific timeframe
    tf_ats = available(timeframe, ats)
    
    # Simple trend calculation using price momentum
    current_price = closeat(ai.ohlcv, tf_ats)
    past_price = closeat(ai.ohlcv, tf_ats - 20 * timeframe.period)
    
    return (current_price - past_price) / past_price
end

function combine_signals(signals)
    # Weight longer timeframes more heavily
    weights = Dict(tf"5m" => 0.2, tf"1h" => 0.3, tf"4h" => 0.5)
    
    weighted_sum = sum(signals[tf] * weights[tf] for tf in keys(signals))
    return weighted_sum
end

function call!(::Type{<:SC}, ::StrategyMarkets)
    ["BTC/USDT", "ETH/USDT", "SOL/USDT"]
end

end
```

### Portfolio Rebalancing Strategy

```julia
module PortfolioRebalancer
using Planar

const DESCRIPTION = "Dynamic portfolio rebalancing"
const EXC = :binance
const MARGIN = NoMargin
const TF = tf"1d"

@strategyenv!

function call!(s::SC, ::ResetStrategy)
    # Target allocations (must sum to 1.0)
    s.attrs[:target_allocations] = Dict(
        "BTC/USDT" => 0.4,
        "ETH/USDT" => 0.3,
        "SOL/USDT" => 0.2,
        "USDT" => 0.1  # Cash allocation
    )
    s.attrs[:rebalance_threshold] = 0.05  # 5% deviation triggers rebalance
    s.attrs[:last_rebalance] = DateTime(0)
    s.attrs[:rebalance_frequency] = Day(7)  # Weekly rebalancing
end

function call!(s::SC, ts::DateTime, ctx)
    # Check if it's time to rebalance
    if ts - s.attrs[:last_rebalance] < s.attrs[:rebalance_frequency]
        return
    end
    
    current_allocations = calculate_current_allocations(s)
    target_allocations = s.attrs[:target_allocations]
    
    # Check if rebalancing is needed
    if needs_rebalancing(current_allocations, target_allocations, s.attrs[:rebalance_threshold])
        execute_rebalancing(s, current_allocations, target_allocations, ts)
        s.attrs[:last_rebalance] = ts
    end
end

function calculate_current_allocations(s)
    total_value = calculate_total_portfolio_value(s)
    allocations = Dict{String, Float64}()
    
    # Cash allocation
    allocations["USDT"] = freecash(s) / total_value
    
    # Asset allocations
    foreach(s.universe) do ai
        symbol = string(ai.asset.bc, "/", ai.asset.qc)
        asset_value = freecash(ai) * closeat(ai.ohlcv, available(s.timeframe, now()))
        allocations[symbol] = asset_value / total_value
    end
    
    return allocations
end

function needs_rebalancing(current, target, threshold)
    for (asset, target_pct) in target
        current_pct = get(current, asset, 0.0)
        if abs(current_pct - target_pct) > threshold
            return true
        end
    end
    return false
end

function execute_rebalancing(s, current, target, ts)
    total_value = calculate_total_portfolio_value(s)
    
    for (symbol, target_pct) in target
        if symbol == "USDT"
            continue  # Handle cash separately
        end
        
        ai = s[symbol]
        current_pct = get(current, symbol, 0.0)
        
        target_value = total_value * target_pct
        current_value = total_value * current_pct
        
        difference = target_value - current_value
        
        if abs(difference) > s.config.min_size
            if difference > 0
                # Need to buy more
                amount = difference / closeat(ai.ohlcv, available(s.timeframe, ts))
                call!(s, ai, MarketOrder(); amount, date=ts)
            else
                # Need to sell
                amount = abs(difference) / closeat(ai.ohlcv, available(s.timeframe, ts))
                amount = min(amount, freecash(ai))  # Don't sell more than we have
                call!(s, ai, MarketOrder(); amount, date=ts, side=Sell)
            end
        end
    end
end

function call!(::Type{<:SC}, ::StrategyMarkets)
    ["BTC/USDT", "ETH/USDT", "SOL/USDT"]
end

end
```

### Advanced Optimization Strategy

```julia
module OptimizedStrategy
using Planar

const DESCRIPTION = "Strategy with comprehensive optimization"
const EXC = :binance
const MARGIN = NoMargin
const TF = tf"1h"

@strategyenv!
@optenv!

function call!(s::SC, ::ResetStrategy)
    _reset!(s)
    _initparams!(s)
    _overrides!(s)
end

function _initparams!(s)
    params_index = attr(s, :params_index)
    empty!(params_index)
    
    # Map parameter names to indices for optimization
    params_index[:rsi_period] = 1
    params_index[:rsi_oversold] = 2
    params_index[:rsi_overbought] = 3
    params_index[:stop_loss] = 4
    params_index[:take_profit] = 5
end

function call!(s::SC, ts::DateTime, ctx)
    ats = available(s.timeframe, ts)
    
    foreach(s.universe) do ai
        # Calculate RSI
        rsi = calculate_rsi(ai, ats, s.attrs[:rsi_period])
        
        # Entry conditions
        if rsi < s.attrs[:rsi_oversold] && !has_position(ai)
            enter_position(s, ai, ats, ts)
        end
        
        # Exit conditions
        if has_position(ai)
            if rsi > s.attrs[:rsi_overbought]
                exit_position(s, ai, ats, ts, "RSI overbought")
            else
                check_stop_loss_take_profit(s, ai, ats, ts)
            end
        end
    end
end

# Optimization configuration
function call!(s::SC, ::OptSetup)
    _initparams!(s)
    (;
        ctx=Context(Sim(), tf"1h", dt"2023-01-01", dt"2024-01-01"),
        params=(
            rsi_period=10:1:30,
            rsi_oversold=20:5:40,
            rsi_overbought=60:5:80,
            stop_loss=0.02:0.005:0.05,
            take_profit=0.03:0.005:0.08
        ),
        space=(kind=:MixedPrecisionRectSearchSpace, precision=[1, 1, 1, 3, 3]),
    )
end

function call!(s::SC, params, ::OptRun)
    s.attrs[:overrides] = (;
        rsi_period=Int(getparam(s, params, :rsi_period)),
        rsi_oversold=getparam(s, params, :rsi_oversold),
        rsi_overbought=getparam(s, params, :rsi_overbought),
        stop_loss=getparam(s, params, :stop_loss),
        take_profit=getparam(s, params, :take_profit),
    )
    _overrides!(s)
end

function call!(s::SC, ::OptScore)
    # Multi-objective optimization
    sharpe = mt.sharpe(s)
    sortino = mt.sortino(s)
    max_dd = mt.maxdrawdown(s)
    
    # Combine metrics with weights
    score = 0.4 * sharpe + 0.4 * sortino - 0.2 * max_dd
    [score]
end

function call!(::Type{<:SC}, ::StrategyMarkets)
    ["BTC/USDT", "ETH/USDT"]
end

end
```

### Simple Moving Average Strategy

```julia
module SimpleMA
using Planar

const DESCRIPTION = "Simple Moving Average Crossover"
const EXC = :binance
const MARGIN = NoMargin
const TF = tf"1h"

@strategyenv!

function call!(s::SC, ::ResetStrategy)
    s.attrs[:fast_period] = 10
    s.attrs[:slow_period] = 20
end

function call!(s::SC, ts::DateTime, ctx)
    ats = available(s.timeframe, ts)
    
    foreach(s.universe) do ai
        # Calculate moving averages
        fast_ma = mean(closeat(ai.ohlcv, ats-s.attrs[:fast_period]:assets
        slow_ma = mean(closeat(ai.ohlcv, ats-s.attrs[:slow_period]:assets
        
        current_price = closeat(ai.ohlcv, ats)
        
        # Trading logic
        if fast_ma > slow_ma && !has_position(ai)
            # Buy signal
            amount = freecash(s) * 0.1 / current_price  # 10% of cash
            call!(s, ai, MarketOrder(); amount, date=ts)
        elseif fast_ma < slow_ma && has_position(ai)
            # Sell signal
            amount = freecash(ai)
            call!(s, ai, MarketOrder(); amount, date=ts, side=Sell)
        end
    end
end

function call!(::Type{<:SC}, ::StrategyMarkets)
    ["BTC/USDT", "ETH/USDT"]
end

end
```

### Margin Trading Strategy

```julia
module MarginStrategy
using Planar

const DESCRIPTION = "Margin Trading with Risk Management"
const EXC = :bybit
const MARGIN = Isolated
const TF = tf"15m"

@strategyenv!
@contractsenv!

function call!(s::SC, ::ResetStrategy)
    # Risk parameters
    s.attrs[:max_leverage] = 5.0
    s.attrs[:risk_per_trade] = 0.02  # 2% risk per trade
    s.attrs[:stop_loss_pct] = 0.03   # 3% stop loss
    
    # Initialize leverage for all assets
    foreach(s.universe) do ai
        call!(s, ai, 2.0, UpdateLeverage(); pos=Long())
        call!(s, ai, 2.0, UpdateLeverage(); pos=Short())
    end
end

function call!(s::SC, ts::DateTime, ctx)
    ats = available(s.timeframe, ts)
    
    foreach(s.universe) do ai
        signal = calculate_signal(s, ai, ats)
        
        if signal > 0.7  # Strong buy signal
            open_long_position(s, ai, ats, ts)
        elseif signal < -0.7  # Strong sell signal
            open_short_position(s, ai, ats, ts)
        end
        
        # Manage existing positions
        manage_positions(s, ai, ats, ts)
    end
end

function open_long_position(s, ai, ats, ts)
    if !inst.islong(inst.position(ai))
        # Calculate position size based on risk
        price = closeat(ai.ohlcv, ats)
        risk_amount = freecash(s) * s.attrs[:risk_per_trade]
        stop_distance = price * s.attrs[:stop_loss_pct]
        
        # Position size = Risk Amount / Stop Distance
        amount = risk_amount / stop_distance
        
        # Apply leverage constraints
        max_amount = freecash(s) * s.attrs[:max_leverage] / price
        amount = min(amount, max_amount)
        
        if amount > ai.limits.amount.min
            call!(s, ai, MarketOrder(); amount, date=ts, pos=Long())
        end
    end
end

function manage_positions(s, ai, ats, ts)
    pos = inst.position(ai)
    if !isnothing(pos) && abs(inst.freecash(ai)) > 0
        entry_price = pos.entry_price
        current_price = closeat(ai.ohlcv, ats)
        
        # Stop loss check
        if inst.islong(pos)
            if current_price <= entry_price * (1 - s.attrs[:stop_loss_pct])
                # Close long position
                call!(s, ai, MarketOrder(); 
                      amount=abs(inst.freecash(ai)), 
                      date=ts, side=Sell, pos=Long())
            end
        elseif inst.isshort(pos)
            if current_price >= entry_price * (1 + s.attrs[:stop_loss_pct])
                # Close short position
                call!(s, ai, MarketOrder(); 
                      amount=abs(inst.freecash(ai)), 
                      date=ts, side=Buy, pos=Short())
            end
        end
    end
end

function calculate_signal(s, ai, ats)
    # Implement your signal calculation logic
    # Return value between -1 (strong sell) and 1 (strong buy)
    0.0  # Placeholder
end

function call!(::Type{<:SC}, ::StrategyMarkets)
    ["BTC/USDT:USDT", "ETH/USDT:USDT"]  # Perpetual contracts
end

end
```

## Best Practices

### Code Organization

1. **Module Constants**: Define strategy metadata at the top
```julia
const DESCRIPTION = "Clear strategy description"
const EXC = :exchange_name
const MARGIN = NoMargin  # or Isolated/Cross
const TF = tf"1h"        # Primary timeframe
```

2. **Environment Macros**: Use appropriate environment macros within your strategy module
```julia
module MyStrategy
using Planar

@strategyenv!      # Basic strategy environment
@contractsenv!     # For margin/futures trading (if needed)
@optenv!          # For optimization support (if needed)

# Your strategy code here...

end
```

3. **Parameter Management**: Use strategy attributes for parameters
```julia
# Within your strategy module
function call!(s::SC, ::ResetStrategy)
    # Example parameter initialization
    s.attrs[:param1] = 1.5  # Example default value
    s.attrs[:param2] = "example_value"  # Another example value
end
```

### Error Handling

```julia
# Within your strategy module - example error handling pattern
function call!(s::SC, ts::DateTime, ctx)
    try
        # Example trading logic (replace with your actual logic)
        # execute_strategy_logic(s, ts)
        @info "Strategy executed successfully at $ts"
    catch e
        @error "Strategy execution error" exception=e
        # Implement recovery logic or fail gracefully
        return nothing
    end
end
```

### Performance Optimization

1. **Minimize Allocations**: Reuse data structures when possible
2. **Batch Operations**: Group similar operations together
3. **Conditional Logic**: Use early returns to avoid unnecessary computations

```julia
function call!(s::SC, ts::DateTime, ctx)
    # Early exit if market is closed
    if !is_market_open(ts)
        return
    end
    
    ats = available(s.timeframe, ts)
    
    # Batch process all assets
    signals = calculate_signals_batch(s, ats)
    execute_trades_batch(s, signals, ats, ts)
end
```

### Testing and Validation

```julia
# Add validation in development
function call!(s::SC, ts::DateTime, ctx)
    @assert freecash(s) >= 0 "Negative cash detected"
    @assert all(ai -> ai.cash >= 0, s.universe) "Negative asset cash"
    
    # Your strategy logic
end
```

### Strategy Configuration

Strategies can be configured through `user/[planar.toml](../config.md#configuration-file)`:

```toml
[strategies.MyStrategy]
exchange = "binance"
margin = "NoMargin"
timeframe = "1h"
initial_cash = 10000.0
sandbox = true

[strategies.MyStrategy.attrs]
custom_param1 = 1.5
custom_param2 = "value"
```

## Quick Troubleshooting

For comprehensive strategy troubleshooting with detailed solutions, see [Strategy Problems](../troubleshooting/strategy-problems.md).

### Common Issues Quick Reference

**❌ Strategy loading fails** → [Strategy Problems: Loading Issues](../troubleshooting/strategy-problems.md#strategy-loading-and-compilation-issues)
- Module not found errors
- Compilation failures
- Missing dependencies

**❌ Runtime execution errors** → [Strategy Problems: Execution Issues](../troubleshooting/strategy-problems.md#strategy-execution-issues)
- Method dispatch errors
- Data access problems
- Signal generation failures

**❌ No trades executing** → [Strategy Problems: Order Execution](../troubleshooting/strategy-problems.md#order-execution-issues)
- Insufficient balance
- Order validation failures
- Position management errors

**❌ Slow performance** → [Performance Issues](../troubleshooting/performance-issues.md#strategy-execution-performance)
- Backtesting optimization
- Memory usage problems
- Algorithm efficiency

**❌ Data problems** → [Exchange Issues](../troubleshooting/exchange-issues.md) or [Performance Issues: Data](../troubleshooting/performance-issues.md#data-related-performance-issues)
- Missing market data
- Exchange connectivity
- Database performance

### Development Tips

**Enable Debug Logging**:
```julia
ENV["JULIA_DEBUG"] = "MyStrategy"
using Logging
global_logger(ConsoleLogger(stderr, Logging.Debug))
```

**Test Components Individually**:
```julia
# Test strategy loading
strategy = load_strategy(:MyStrategy)

# Test data access
data = get_market_data(strategy)

# Test signal generation
signals = generate_signals(strategy, data, now())
```

**Use Simulation Mode for Debugging**:
```julia
using Planar
@environment!

# Create strategy in simulation mode for debugging
s = strategy(:YourStrategy, mode=Sim())
s.config.start_date = DateTime("2023-01-01")
s.config.end_date = DateTime("2023-12-31")

# Run simulation
fill!(s)
start!(s)
```

For detailed troubleshooting steps and platform-specific solutions, visit [Strategy Problems](../troubleshooting/strategy-problems.md).es
- Check that `call!(s::SC, ::OptScore)` returns appropriate metrics
- Verify that parameter overrides are applied correctly in `call!(s::SC, params, ::OptRun)`

### Debugging Strategies

#### Enable Debug Logging

```julia
# Add to your strategy module
using Logging

function call!(s::SC, ts::DateTime, ctx)
    @debug "Strategy execution" timestamp=ts cash=freecash(s)
    
    # Your strategy logic with debug statements
    foreach(s.universe) do ai
        @debug "Processing asset" symbol=ai.asset.symbol position=freecash(ai)
        # Trading logic
    end
end
```

#### Strategy State Inspection

```julia
# Inspect strategy state during development
function inspect_strategy_state(s)
    println("Strategy: $(typeof(s))")
    println("Cash: $(freecash(s))")
    println("Universe size: $(length(s.universe))")
    
    foreach(s.universe) do ai
        println("  $(ai.asset.symbol): $(freecash(ai))")
    end
    
    println("Attributes:")
    for (key, value) in s.attrs
        println("  $key: $value")
    end
end
```

#### Performance Profiling

```julia
using Profile

# Profile your strategy execution
function profile_strategy(s, start_date, end_date)
    @profile begin
        # Run strategy for profiling
        simulate!(s, start_date, end_date)
    end
    
    Profile.print()
end
```

### Removing Strategies

The function `remove_strategy` allows you to discard a strategy by its name:

```julia
julia> Planar.remove_strategy("MyNewStrategy")
Really delete strategy located at /path/to/Planar.jl/user/strategies/MyNewStrategy? [n]/y: y
[ Info: Strategy removed
Remove user config entry MyNewStrategy? [n]/y: y
```

## Advanced Topics

### Dynamic Universe Management

The universe (`s.universe`) is backed by a `DataFrame` (`s.universe.data`). It is possible to add and remove assets from the universe during runtime, although this feature is not extensively tested.

```julia
# Add new asset to universe (experimental)
function add_asset_to_universe(s::Strategy, symbol::String)
    # This requires careful handling of data synchronization
    new_asset = Asset(symbol, exchange(s))
    # Implementation would require careful handling of data synchronization
end

# Remove asset from universe (experimental)
function remove_asset_from_universe(s::Strategy, symbol::String)
    # Close any open positions first
    ai = s[symbol]
    if !isnothing(ai) && freecash(ai) != 0
        close_position(s, ai)
    end
    # Remove from universe (experimental)
end
```

### Custom Indicators

```julia
# Example: Custom technical indicators
function calculate_rsi(prices, period=14)
    gains = max.(diff(prices), 0)
    losses = -min.(diff(prices), 0)
    
    avg_gain = mean(gains[1:period])
    avg_loss = mean(losses[1:period])
    
    rs = avg_gain / avg_loss
    rsi = 100 - (100 / (1 + rs))
    
    return rsi
end

function calculate_bollinger_bands(prices, period=20, std_dev=2)
    sma = mean(prices[end-period+1:end])
    std = std(prices[end-period+1:end])
    
    upper_band = sma + (std_dev * std)
    lower_band = sma - (std_dev * std)
    
    return (upper=upper_band, middle=sma, lower=lower_band)
end
```

### Integration with External Libraries

```julia
# Example: Using external Python libraries
using PythonCall

function call!(s::SC, ::ResetStrategy)
    # Import Python libraries
    s.attrs[:ta] = pyimport("talib")
    s.attrs[:np] = pyimport("numpy")
end

function call!(s::SC, ts::DateTime, ctx)
    ats = available(s.timeframe, ts)
    
    foreach(s.universe) do ai
        # Get price data
        prices = closeat(ai.ohlcv, ats-100:ats)
        
        # Use Python TA-Lib
        ta = s.attrs[:ta]
        np = s.attrs[:np]
        
        rsi = ta.RSI(np.array(prices))
        macd = ta.MACD(np.array(prices))
        
        # Use indicators in trading logic
        if rsi[end] < 30  # Oversold
            # Buy logic
        elseif rsi[end] > 70  # Overbought
            # Sell logic
        end
    end
end
```

This comprehensive guide provides everything you need to develop sophisticated trading strategies in Planar. Start with the basic examples and gradually work your way up to more advanced patterns as you become comfortable with the dispatch system and strategy architecture.