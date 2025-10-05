---
category: "strategy-development"
difficulty: "advanced"
topics: [execution-modes, margin-trading, exchanges, data-management, optimization, strategy-development, troubleshooting, visualization, configuration]
last_updated: "2025-10-04"---
---

# Strategy Development Guide

<!--
Keywords: [strategy](../guides/strategy-development.md) development, call! function, [dispatch system](../guides/[strategy](../guides/strategy-development.md)-development.md#dispatch-system), [margin trading](../guides/[strategy](../guides/strategy-development.md)-development.md#margin-trading-concepts), [backtesting](../guides/execution-modes.md#simulation)-mode), [optimization](../optimization.md), [Julia](https://julialang.org/) modules, trading logic
Description: Comprehensive guide to developing trading [strategies](../guides/strategy-development.md) in Planar using [Julia](https://julialang.org/)'s [dispatch system](../guides/strategy-development.md#dispatch-system), covering everything from basic concepts to advanced patterns.
-->

This comprehensive guide covers everything you need to know about developing trading [strategies](../guides/strategy-development.md) in Planar. From basic concepts to advanced patterns, you'll learn how to build robust, profitable trading systems.

## Quick Navigation

- **[Strategy Fundamentals](#strategy-fundamentals)** - Core concepts and architecture
- **[Creating Strategies](#creating-a-new-strategy)** - Interactive and manual setup
- **[Loading Strategies](#loading-a-strategy)** - Runtime instantiation
- **[Advanced Examples](#advanced-strategy-examples)** - Multi-timeframe, portfolio, and optimization strategies
- **[Best Practices](#best-practices)** - Code organization and performance tips
- **[Troubleshooting](#troubleshooting-and-debugging)** - Common issues and solutions

## Prerequisites

Before diving into strategy development, ensure you have:

- Completed the [Getting Started Guide](getting-started/index.md)
- Basic understanding of [Data Management](data.md)
- Familiarity with [Execution Modes](engine/mode-comparison.md)

## Related Topics

- **[Optimization](../optimization.md)** - Parameter tuning and backtesting
- **[Plotting](plotting.md)** - Visualizing strategy performance
- **[Customization](customizations/customizations.md)** - Extending strategy functionality

## Strategy Fundamentals

### Architecture Overview

Planar strategies are built around [Julia](https://julialang.org/)'s powerful [dispatch system](../guides/strategy-development.md#dispatch-system), enabling clean separation of concerns and easy customization. Each strategy is a Julia module that implements specific interface methods through the `call!` function dispatch pattern.

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
# Called during strategy loading (before construction)
function call!(::Type{<:SC}, config, ::LoadStrategy)
    # Strategy initialization logic
end

# Called during strategy execution (after construction)
function call!(s::SC, ts::DateTime, ctx)
    # Trading logic executed on each timestep
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
# Default behavior for all [exchanges](../exchanges.md)
function call!(::Type{<:SC}, ::StrategyMarkets)
    ["BTC/USDT", "ETH/USDT", "SOL/USDT"]
end

# Specific behavior for Bybit
function call!(::Type{<:SC{ExchangeID{:bybit}}}, ::StrategyMarkets)
    ["BTC/USDT", "ETH/USDT", "ATOM/USDT"]  # Different asset selection
end
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

# Position-specific [leverage](../guides/strategy-development.md#margin-modes) updates
function update_leverage!(s, ai, pos::Long, [leverage](../guides/strategy-development.md#margin-modes))
    call!(s, ai, [leverage](../guides/strategy-development.md#margin-modes), UpdateLeverage(); pos=Long())
end
```

**Cross Margin**: Shared margin across all positions
```julia
const MARGIN = Cross
```

#### Position Management

```julia
# Check position direction
if inst.islong(position)
    # Handle long position logic
elseif inst.isshort(position)
    # Handle short position logic
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
    min(amount, max_position / closeat(ai, available(s.[timeframe](../guides/data-management.md#timeframes), now())))
end
```

## Creating a New Strategy

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

Select exchange by:
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
### Non-Interactive Strategy Creation

You can also create strategies programmatically without user interaction:

```julia
# Skip interaction by passing ask=false
Planar.generate_strat("MyNewStrategy", ask=false, [exchange](../exchanges.md)=:myexc)

# Or use a configuration object
cfg = Planar.Config(exchange=:myexc)
Planar.generate_strat("MyNewStrategy", cfg)
```
## Loading a Strategy

### Basic Strategy Loading

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

After module import, the strategy is instantiated by calling `call!(::Type{S}, ::LoadStrategy, cfg)`.

### Strategy Type Structure

```julia
julia> typeof(s)
Engine.Strategies.Strategy37{:Example, ExchangeTypes.ExchangeID{:kucoin}(), :USDT}
```

### Example Strategy Module

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

### Dispatch Convention

**Rule of Thumb**: Methods called before strategy construction dispatch on the strategy **type** (`Type{<:S}`), while methods called during runtime dispatch on the strategy **instance** (`S`).

**Type Definitions**:
- `S`: Complete strategy type with all parameters (`const S = Strategy{name, exc, ...}`)
- `SC`: Generic strategy type where exchange parameter is unspecified

## Manual setup
If you want to create a strategy manually you can either:
- Copy the `user/strategies/Template.jl` to a new file in the same directory and customize it.
- Generate a new project in `user/strategies` and customize `Template.jl` to be your project entry file. The strategy `Project.toml` is used to store strategy config options. See other strategies examples for what the keys that are required.

For more advanced setups you can also use `Planar` as a library, and construct the strategy object directly from your own module:

``` julia
using Planar
using MyDownStreamModule
s = Planar.Engine.Strategies.strategy(MyDownStreamModule)
```


## Strategy Interface Details

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

# Define tradeable markets
function call!(::Type{<:SC}, ::StrategyMarkets)
    ["BTC/USDT", "ETH/USDT", "SOL/USDT"]
end
```

#### Optional Methods

```julia
# Custom strategy loading
function call!(::Type{<:SC}, config, ::LoadStrategy)
    s = default_load(@__MODULE__, SC, config)
    # Custom initialization logic
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

# Warmup period for data requirements
function call!(s::SC, ::WarmupPeriod)
    Day(30)  # Require 30 days of historical data
end
```

### Advanced Dispatch Patterns

#### Conditional Dispatch by Mode

```julia
# Different behavior for different execution modes
function call!(s::Strategy{Sim}, ts::DateTime, ctx)
    # Backtesting-specific logic (faster, simplified)
    simple_trading_logic(s, ts)
end

function call!(s::Strategy{<:Union{Paper,Live}}, ts::DateTime, ctx)
    # Live trading logic (more robust, with error handling)
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

## List of strategy call! functions

```@docs
Engine.Strategies.call!
```

## Removing a strategy
The function `remove_strategy` allows to discard a strategy by its name. It will delete the julia file or the project directory and optionally the config entry.

``` julia
julia> Planar.remove_strategy("MyNewStrategy")
Really delete strategy located at /run/media/fra/stateful-1/dev/Planar.jl/user/strategies/MyNewStrategy? [n]/y: y
[ Info: Strategy removed
Remove user config entry MyNewStrategy? [n]/y: y
```

## Advanced Strategy Examples

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
    # Configure multiple [timeframes](../guides/data-management.md#timeframes)
    s.attrs[:timeframes] = [tf"5m", tf"1h", tf"4h"]
    s.attrs[:trend_threshold] = 0.02
    s.attrs[:position_size] = 0.1
end

function call!(s::SC, ts::DateTime, ctx)
    ats = available(s.timeframe, ts)
    
    foreach(s.universe) do ai
        # Get signals from multiple [timeframes](../guides/data-management.md#timeframes)
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
    # Weight longer [timeframes](../guides/data-management.md#timeframes) more heavily
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
        # Calculate [RSI](../guides/strategy-development.md#technical-indicators)
        rsi = calculate_rsi(ai, ats, s.attrs[:rsi_period])
        
        # Entry conditions
        if rsi < s.attrs[:rsi_oversold] && !has_position(ai)
            enter_position(s, ai, ats, ts)
        end
        
        # Exit conditions
        if has_position(ai)
            if rsi > s.attrs[:rsi_overbought]
                exit_position(s, ai, ats, ts, "[RSI](../guides/strategy-development.md#technical-indicators) overbought")
            else
                check_stop_loss_take_profit(s, ai, ats, ts)
            end
        end
    end
end

function enter_position(s, ai, ats, ts)
    price = closeat(ai.ohlcv, ats)
    amount = freecash(s) * 0.1 / price  # 10% position size
    
    if amount > ai.limits.amount.min
        trade = call!(s, ai, MarketOrder(); amount, date=ts)
        
        # Set stop loss and take profit levels
        if !isnothing(trade)
            stop_price = price * (1 - s.attrs[:stop_loss])
            profit_price = price * (1 + s.attrs[:take_profit])
            
            # Store entry information for position management
            s.attrs[:entry_info] = Dict(
                :entry_price => price,
                :stop_price => stop_price,
                :profit_price => profit_price,
                :entry_time => ts
            )
        end
    end
end

function check_stop_loss_take_profit(s, ai, ats, ts)
    if !haskey(s.attrs, :entry_info)
        return
    end
    
    current_price = closeat(ai.ohlcv, ats)
    entry_info = s.attrs[:entry_info]
    
    if current_price <= entry_info[:stop_price]
        exit_position(s, ai, ats, ts, "Stop loss triggered")
    elseif current_price >= entry_info[:profit_price]
        exit_position(s, ai, ats, ts, "Take profit triggered")
    end
end

function exit_position(s, ai, ats, ts, reason)
    amount = freecash(ai)
    if amount > 0
        call!(s, ai, MarketOrder(); amount, date=ts, side=Sell)
        @info "Position closed: \$reason" asset=ai.asset.symbol
        delete!(s.attrs, :entry_info)
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

## Strategy Setup and Loading (Preserved)

Strategy examples can be found in the `user/strategies` folder. Some strategies are single files like `Example.jl` while strategies like `BollingerBands` or `ExampleMargin` are project-based.

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

## Strategy Examples

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

2. **Environment Macros**: Use appropriate environment macros
```julia
@strategyenv!      # Basic strategy environment
@contractsenv!     # For margin/futures trading
@optenv!          # For optimization support
```

3. **Parameter Management**: Use strategy attributes for parameters
```julia
function call!(s::SC, ::ResetStrategy)
    s.attrs[:param1] = default_value
    s.attrs[:param2] = another_value
end
```

### Error Handling

```julia
function call!(s::SC, ts::DateTime, ctx)
    try
        # Your trading logic
        execute_strategy_logic(s, ts)
    catch e
        @error "Strategy execution error" exception=e
        # Implement recovery logic or fail gracefully
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

## Resizeable Universe

The universe (`s.universe`) is backed by a `DataFrame` (`s.universe.data`). It is possible to add and remove assets from the universe during runtime, although this feature is not extensively tested.

### Dynamic Asset Management

```julia
# Add new asset to universe
function add_asset_to_universe(s::Strategy, symbol::String)
    # This is experimental - use with caution
    new_asset = Asset(symbol, exchange(s))
    # Implementation would require careful handling of data synchronization
end

# Remove asset from universe
function remove_asset_from_universe(s::Strategy, symbol::String)
    # Close any open positions first
    ai = s[symbol]
    if !isnothing(ai) && freecash(ai) != 0
        close_position(s, ai)
    end
    # Remove from universe (experimental)
end
```

## Troubleshooting and Debugging

### Common Strategy Issues

#### 1. Strategy Loading Problems

**Issue**: Strategy fails to load with module not found error
```julia
ERROR: ArgumentError: Module MyStrategy not found
```

**Solutions**:
- Verify the strategy file exists in `user/strategies/`
- Check that the module name matches the file name
- Ensure the strategy module is properly defined:

```julia
module MyStrategy  # Must match filename
using Planar

# Strategy implementation
end
```

**Issue**: Strategy loads but crashes during initialization
```julia
ERROR: UndefVarError: SC not defined
```

**Solutions**:
- Add the `@strategyenv!` macro to import required types
- Verify all required constants are defined:

```julia
const DESCRIPTION = "Strategy description"
const EXC = :exchange_name
const MARGIN = NoMargin
const TF = tf"1h"

@strategyenv!  # This defines SC and other types
```

#### 2. Data Access Issues

**Issue**: [OHLCV data](../guides/data-management.md#ohlcv-data) is empty or missing
```julia
ERROR: BoundsError: attempt to access 0-element Vector
```

**Solutions**:
- Check data availability for your timeframe and date range
- Verify exchange supports the requested markets
- Ensure sufficient warmup period:

```julia
function call!(s::SC, ::WarmupPeriod)
    Day(30)  # Increase if you need more historical data
end
```

**Issue**: Inconsistent data between timeframes
```julia
WARNING: Data gap detected in [OHLCV](../guides/data-management.md#ohlcv-data) series
```

**Solutions**:
- Use `available()` function to get valid timestamps
- Handle missing data gracefully:

```julia
function call!(s::SC, ts::DateTime, ctx)
    ats = available(s.timeframe, ts)
    
    foreach(s.universe) do ai
        # Check if data is available
        if isempty(ai.ohlcv) || ats < first(ai.ohlcv.timestamp)
            @warn "Insufficient data for \$(ai.asset.symbol)"
            return
        end
        
        # Your trading logic here
    end
end
```

#### 3. Order Execution Problems

**Issue**: Orders are rejected with insufficient funds
```julia
ERROR: OrderError: Insufficient balance
```

**Solutions**:
- Check available cash before placing orders:

```julia
function safe_buy(s, ai, amount, price)
    required_cash = amount * price
    available_cash = freecash(s)
    
    if required_cash > available_cash
        @warn "Insufficient cash" required=required_cash available=available_cash
        return nothing
    end
    
    call!(s, ai, MarketOrder(); amount, date=now())
end
```

**Issue**: Orders fail due to minimum size requirements
```julia
ERROR: OrderError: Order size below minimum
```

**Solutions**:
- Check exchange limits before placing orders:

```julia
function validate_order_size(ai, amount)
    min_amount = ai.limits.amount.min
    min_cost = ai.limits.cost.min
    
    if amount < min_amount
        @warn "Amount below minimum" amount min_amount
        return false
    end
    
    cost = amount * closeat(ai.ohlcv, available(tf"1m", now()))
    if cost < min_cost
        @warn "Cost below minimum" cost min_cost
        return false
    end
    
    return true
end
```

#### 4. Margin Trading Issues

**Issue**: Leverage updates fail
```julia
ERROR: Exchange error: Invalid leverage value
```

**Solutions**:
- Check exchange-specific leverage limits
- Update leverage before placing orders:

```julia
function safe_leverage_update(s, ai, leverage, pos)
    max_lev = ai.limits.leverage.max
    min_lev = ai.limits.leverage.min
    
    leverage = clamp(leverage, min_lev, max_lev)
    
    try
        call!(s, ai, leverage, UpdateLeverage(); pos)
    catch e
        @error "Leverage update failed" exception=e
    end
end
```

### Debugging Techniques

#### 1. Logging and Monitoring

```julia
using Logging

function call!(s::SC, ts::DateTime, ctx)
    @debug "Strategy execution" timestamp=ts cash=freecash(s)
    
    ats = available(s.timeframe, ts)
    
    foreach(s.universe) do ai
        price = closeat(ai.ohlcv, ats)
        position = freecash(ai)
        
        @debug "Asset state" symbol=ai.asset.symbol price position
        
        # Your trading logic with logging
        if should_buy(s, ai, ats)
            @info "Buy signal detected" symbol=ai.asset.symbol price
            buy_result = buy!(s, ai, ats, ts)
            @info "Buy order result" result=buy_result
        end
    end
end
```

#### 2. Strategy State Inspection

```julia
# Add debugging methods to your strategy
function debug_state(s::SC)
    println("=== Strategy State ===")
    println("Cash: \$(freecash(s))")
    println("Committed: \$(s.cash_committed)")
    println("Attributes: \$(s.attrs)")
    
    println("\n=== Universe State ===")
    foreach(s.universe) do ai
        println("\$(ai.asset.symbol): \$(freecash(ai))")
    end
    
    println("\n=== Open Orders ===")
    for (side, orders) in [(:buy, s.buyorders), (:sell, s.sellorders)]
        for (symbol, order_list) in orders
            if !isempty(order_list)
                println("\$side orders for \$symbol: \$(length(order_list))")
            end
        end
    end
end

# Call during strategy execution
function call!(s::SC, ts::DateTime, ctx)
    if ts.hour == 0 && ts.minute == 0  # Daily debug output
        debug_state(s)
    end
    
    # Your strategy logic
end
```

#### 3. Performance Profiling

```julia
using Profile

function profile_strategy(s::SC, ts::DateTime, ctx)
    @profile begin
        # Your strategy logic here
        call!(s, ts, ctx)
    end
end

# After running, analyze the profile
Profile.print()
```

#### 4. Unit Testing Strategies

```julia
# test/test_mystrategy.jl
using Test
using Planar

@testset "MyStrategy Tests" begin
    # Test strategy loading
    @testset "Strategy Loading" begin
        cfg = Config(exchange=:binance, mode=Sim())
        s = strategy(:MyStrategy, cfg)
        @test s isa Strategy
        @test nameof(s) == :MyStrategy
    end
    
    # Test signal calculation
    @testset "Signal Calculation" begin
        # Create mock data
        s = create_test_strategy()
        ai = first(s.universe)
        
        # Test your signal functions
        signal = calculate_signal(s, ai, now())
        @test -1.0 <= signal <= 1.0
    end
    
    # Test order validation
    @testset "Order Validation" begin
        s = create_test_strategy()
        ai = first(s.universe)
        
        # Test minimum order size validation
        @test validate_order_size(ai, 0.001) == false
        @test validate_order_size(ai, 1.0) == true
    end
end

function create_test_strategy()
    cfg = Config(
        exchange=:binance,
        mode=Sim(),
        initial_cash=10000.0
    )
    s = strategy(:MyStrategy, cfg)
    reset!(s)
    return s
end
```

### Error Recovery Patterns

#### 1. Graceful Degradation

```julia
function call!(s::SC, ts::DateTime, ctx)
    try
        # Main strategy logic
        execute_main_logic(s, ts, ctx)
    catch e
        @error "Main logic failed, switching to safe mode" exception=e
        execute_safe_mode(s, ts, ctx)
    end
end

function execute_safe_mode(s, ts, ctx)
    # Close all positions if something goes wrong
    foreach(s.universe) do ai
        if freecash(ai) > 0
            try
                call!(s, ai, MarketOrder(); 
                      amount=freecash(ai), 
                      date=ts, 
                      side=Sell)
            catch e
                @error "Failed to close position" asset=ai.asset.symbol exception=e
            end
        end
    end
end
```

#### 2. Circuit Breaker Pattern

```julia
function call!(s::SC, ts::DateTime, ctx)
    # Check for circuit breaker conditions
    if should_halt_trading(s)
        @warn "Circuit breaker activated, halting trading"
        return
    end
    
    # Normal trading logic
    execute_strategy(s, ts, ctx)
end

function should_halt_trading(s)
    # Halt if losses exceed threshold
    total_pnl = calculate_total_pnl(s)
    max_loss = s.config.initial_cash * 0.1  # 10% max loss
    
    if total_pnl < -max_loss
        return true
    end
    
    # Halt if too many failed orders
    failed_orders = get(s.attrs, :failed_orders, 0)
    if failed_orders > 10
        return true
    end
    
    return false
end
```

### Performance Optimization Tips

1. **Minimize Data Access**: Cache frequently used values
2. **Batch Operations**: Group similar operations together
3. **Use Type Stability**: Ensure functions return consistent types
4. **Profile Regularly**: Use Julia's profiling tools to identify bottlenecks
5. **Memory Management**: Avoid unnecessary allocations in hot paths

```julia
# Good: Cache expensive calculations
function call!(s::SC, ts::DateTime, ctx)
    ats = available(s.timeframe, ts)
    
    # Cache prices for all assets at once
    prices = Dict{String, Float64}()
    foreach(s.universe) do ai
        prices[ai.asset.symbol] = closeat(ai.ohlcv, ats)
    end
    
    # Use cached prices in trading logic
    foreach(s.universe) do ai
        price = prices[ai.asset.symbol]
        # Trading logic using cached price
    end
end
```## Or
der Management and Risk Control

### Order Types and Execution

Planar supports various order types for different trading scenarios. Understanding when and how to use each type is crucial for effective strategy implementation.

#### Market Orders

Market orders execute immediately at the current market price:

```julia
# Basic market buy order
function place_market_buy(s, ai, amount, ts)
    call!(s, ai, MarketOrder(); amount, date=ts)
end

# Market sell order
function place_market_sell(s, ai, amount, ts)
    call!(s, ai, MarketOrder(); amount, date=ts, side=Sell)
end

# Market order with position specification (for [margin trading](../guides/strategy-development.md#margin-trading-concepts))
function place_market_order_with_position(s, ai, amount, ts, position_side)
    call!(s, ai, MarketOrder(); amount, date=ts, pos=position_side)
end
```

#### Limit Orders

Limit orders execute only at a specified price or better:

```julia
# Limit buy order (buy at or below specified price)
function place_limit_buy(s, ai, amount, price, ts)
    call!(s, ai, LimitOrder(); amount, price, date=ts)
end

# Limit sell order (sell at or above specified price)
function place_limit_sell(s, ai, amount, price, ts)
    call!(s, ai, LimitOrder(); amount, price, date=ts, side=Sell)
end

# Advanced limit order with time-in-force
function place_limit_order_advanced(s, ai, amount, price, ts; tif=:GTC)
    call!(s, ai, LimitOrder(); 
          amount, price, date=ts, 
          time_in_force=tif)  # GTC, IOC, FOK
end
```

#### Stop Orders

Stop orders become market orders when a trigger price is reached:

```julia
# Stop loss order (sell when price falls below trigger)
function place_stop_loss(s, ai, amount, stop_price, ts)
    call!(s, ai, StopOrder(); 
          amount, stop_price, date=ts, side=Sell)
end

# Stop limit order (becomes limit order when triggered)
function place_stop_limit(s, ai, amount, stop_price, limit_price, ts)
    call!(s, ai, StopLimitOrder(); 
          amount, stop_price, limit_price, date=ts, side=Sell)
end
```

#### Order Management Patterns

```julia
# Cancel all orders for an asset
function cancel_all_orders(s, ai)
    call!(s, ai, CancelOrders())
end

# Cancel specific order type
function cancel_buy_orders(s, ai)
    call!(s, ai, CancelOrders(); t=Buy)
end

function cancel_sell_orders(s, ai)
    call!(s, ai, CancelOrders(); t=Sell)
end

# Replace existing orders with new ones
function replace_orders(s, ai, new_amount, new_price, ts)
    # Cancel existing orders
    cancel_all_orders(s, ai)
    
    # Place new order
    call!(s, ai, LimitOrder(); amount=new_amount, price=new_price, date=ts)
end
```

### Position Management for Margin Trading

#### Position Types and States

```julia
# Check position state
function analyze_position(ai)
    pos = inst.position(ai)
    
    if isnothing(pos)
        return :no_position
    elseif inst.islong(pos)
        return :long_position
    elseif inst.isshort(pos)
        return :short_position
    else
        return :unknown_position
    end
end

# Get position-specific information
function get_position_info(ai, position_side)
    pos = inst.position(ai, position_side)
    
    if !isnothing(pos)
        return (
            size = abs(inst.freecash(ai, position_side)),
            entry_price = pos.entry_price,
            unrealized_pnl = pos.unrealized_pnl,
            margin_used = pos.margin_used
        )
    end
    
    return nothing
end
```

#### Leverage Management

```julia
# Dynamic leverage based on volatility
function calculate_dynamic_leverage(s, ai, ats; base_leverage=2.0, max_leverage=10.0)
    # Calculate recent volatility
    lookback = 20
    prices = [closeat(ai.ohlcv, ats - i * s.timeframe.period) for i in 0:lookback-1]
    returns = [log(prices[i] / prices[i+1]) for i in 1:length(prices)-1]
    volatility = std(returns)
    
    # Inverse relationship: higher volatility = lower leverage
    volatility_factor = 0.02  # Adjust based on your risk tolerance
    leverage = base_leverage / (1 + volatility / volatility_factor)
    
    return clamp(leverage, 1.0, max_leverage)
end

# Set leverage for specific position
function set_position_leverage(s, ai, leverage, position_side)
    try
        call!(s, ai, leverage, UpdateLeverage(); pos=position_side)
        @info "Leverage updated" asset=ai.asset.symbol leverage position=position_side
    catch e
        @error "Failed to update leverage" asset=ai.asset.symbol exception=e
    end
end

# Set leverage for both long and short positions
function set_dual_leverage(s, ai, long_lev, short_lev)
    set_position_leverage(s, ai, long_lev, Long())
    set_position_leverage(s, ai, short_lev, Short())
end
```

#### Position Sizing Strategies

```julia
# Fixed fractional position sizing
function fixed_fractional_size(s, price, fraction=0.1)
    available_cash = freecash(s)
    position_value = available_cash * fraction
    return position_value / price
end

# Volatility-adjusted position sizing
function volatility_adjusted_size(s, ai, ats, target_risk=0.02)
    price = closeat(ai.ohlcv, ats)
    
    # Calculate volatility (standard deviation of returns)
    lookback = 20
    returns = []
    for i in 1:lookback-1
        p1 = closeat(ai.ohlcv, ats - i * s.timeframe.period)
        p2 = closeat(ai.ohlcv, ats - (i+1) * s.timeframe.period)
        push!(returns, log(p1 / p2))
    end
    
    volatility = std(returns)
    
    # Position size = (Target Risk * Portfolio Value) / (Price * Volatility)
    portfolio_value = freecash(s)
    position_size = (target_risk * portfolio_value) / (price * volatility)
    
    return position_size
end

# Kelly criterion position sizing
function kelly_position_size(s, ai, win_rate, avg_win, avg_loss)
    if avg_loss <= 0
        return 0.0
    end
    
    # Kelly fraction = (win_rate * avg_win - (1 - win_rate) * avg_loss) / avg_win
    kelly_fraction = (win_rate * avg_win - (1 - win_rate) * avg_loss) / avg_win
    
    # Use fractional Kelly to reduce risk
    fractional_kelly = kelly_fraction * 0.25  # Use 25% of full Kelly
    
    # Convert to position size
    portfolio_value = freecash(s)
    price = closeat(ai.ohlcv, available(s.timeframe, now()))
    
    return max(0.0, fractional_kelly * portfolio_value / price)
end
```

### Risk Management Patterns

#### Stop Loss Strategies

```julia
# Fixed percentage stop loss
function implement_fixed_stop_loss(s, ai, entry_price, stop_pct=0.03)
    if inst.islong(inst.position(ai))
        stop_price = entry_price * (1 - stop_pct)
        place_stop_loss(s, ai, abs(inst.freecash(ai)), stop_price, now())
    elseif inst.isshort(inst.position(ai))
        stop_price = entry_price * (1 + stop_pct)
        # For short positions, stop loss is a buy order
        call!(s, ai, StopOrder(); 
              amount=abs(inst.freecash(ai)), 
              stop_price=stop_price, 
              date=now(), 
              side=Buy, 
              pos=Short())
    end
end

# Trailing stop loss
function implement_trailing_stop(s, ai, trail_pct=0.02)
    pos = inst.position(ai)
    if isnothing(pos)
        return
    end
    
    current_price = closeat(ai.ohlcv, available(s.timeframe, now()))
    
    if inst.islong(pos)
        # For long positions, trail stop up as price increases
        highest_price = get(s.attrs, Symbol("highest_\$(ai.asset.symbol)"), pos.entry_price)
        highest_price = max(highest_price, current_price)
        s.attrs[Symbol("highest_\$(ai.asset.symbol)")] = highest_price
        
        stop_price = highest_price * (1 - trail_pct)
        
        # Update stop loss if new stop is higher than current
        current_stop = get(s.attrs, Symbol("stop_\$(ai.asset.symbol)"), 0.0)
        if stop_price > current_stop
            cancel_sell_orders(s, ai)  # Cancel existing stop
            place_stop_loss(s, ai, abs(inst.freecash(ai)), stop_price, now())
            s.attrs[Symbol("stop_\$(ai.asset.symbol)")] = stop_price
        end
    end
end

# ATR-based stop loss
function implement_atr_stop_loss(s, ai, ats, atr_multiplier=2.0)
    # Calculate Average True Range
    atr = calculate_atr(ai, ats, 14)  # 14-period ATR
    current_price = closeat(ai.ohlcv, ats)
    
    pos = inst.position(ai)
    if !isnothing(pos)
        if inst.islong(pos)
            stop_price = current_price - (atr * atr_multiplier)
        else
            stop_price = current_price + (atr * atr_multiplier)
        end
        
        # Implement the stop loss
        implement_fixed_stop_loss(s, ai, current_price, abs(stop_price - current_price) / current_price)
    end
end
```

#### Take Profit Strategies

```julia
# Fixed take profit
function implement_take_profit(s, ai, entry_price, profit_pct=0.05)
    pos = inst.position(ai)
    if isnothing(pos)
        return
    end
    
    if inst.islong(pos)
        profit_price = entry_price * (1 + profit_pct)
        call!(s, ai, LimitOrder(); 
              amount=abs(inst.freecash(ai)), 
              price=profit_price, 
              date=now(), 
              side=Sell)
    elseif inst.isshort(pos)
        profit_price = entry_price * (1 - profit_pct)
        call!(s, ai, LimitOrder(); 
              amount=abs(inst.freecash(ai)), 
              price=profit_price, 
              date=now(), 
              side=Buy, 
              pos=Short())
    end
end

# Scaled take profit (partial profit taking)
function implement_scaled_take_profit(s, ai, entry_price)
    pos = inst.position(ai)
    if isnothing(pos)
        return
    end
    
    position_size = abs(inst.freecash(ai))
    
    # Take profit at multiple levels
    profit_levels = [
        (0.02, 0.25),  # 2% profit, sell 25% of position
        (0.04, 0.35),  # 4% profit, sell 35% of position
        (0.08, 0.40),  # 8% profit, sell remaining 40%
    ]
    
    for (profit_pct, size_pct) in profit_levels
        if inst.islong(pos)
            profit_price = entry_price * (1 + profit_pct)
        else
            profit_price = entry_price * (1 - profit_pct)
        end
        
        amount = position_size * size_pct
        
        call!(s, ai, LimitOrder(); 
              amount, 
              price=profit_price, 
              date=now(), 
              side=inst.islong(pos) ? Sell : Buy,
              pos=inst.islong(pos) ? Long() : Short())
    end
end
```

#### Portfolio Risk Management

```julia
# Maximum drawdown protection
function check_drawdown_limit(s, max_drawdown=0.15)
    current_value = calculate_portfolio_value(s)
    peak_value = get(s.attrs, :peak_portfolio_value, current_value)
    
    # Update peak value
    if current_value > peak_value
        s.attrs[:peak_portfolio_value] = current_value
        peak_value = current_value
    end
    
    # Calculate current drawdown
    drawdown = (peak_value - current_value) / peak_value
    
    if drawdown > max_drawdown
        @warn "Maximum drawdown exceeded" current_dd=drawdown max_dd=max_drawdown
        emergency_close_all_positions(s)
        return true
    end
    
    return false
end

# Position correlation limits
function check_correlation_limits(s, max_correlation=0.7)
    positions = []
    
    foreach(s.universe) do ai
        if abs(inst.freecash(ai)) > 0
            push!(positions, ai.asset.symbol)
        end
    end
    
    # Calculate correlation between positions (simplified)
    if length(positions) > 1
        # In practice, you would calculate actual price correlations
        # This is a simplified example
        correlation = calculate_position_correlation(s, positions)
        
        if correlation > max_correlation
            @warn "High correlation detected" correlation positions
            # Reduce position sizes or close some positions
            reduce_correlated_positions(s, positions)
        end
    end
end

# Emergency position closure
function emergency_close_all_positions(s)
    @warn "Emergency closure activated - closing all positions"
    
    foreach(s.universe) do ai
        position_size = abs(inst.freecash(ai))
        if position_size > 0
            try
                # Cancel all pending orders first
                cancel_all_orders(s, ai)
                
                # Close position with market order
                pos = inst.position(ai)
                if !isnothing(pos)
                    side = inst.islong(pos) ? Sell : Buy
                    pos_type = inst.islong(pos) ? Long() : Short()
                    
                    call!(s, ai, MarketOrder(); 
                          amount=position_size, 
                          date=now(), 
                          side=side, 
                          pos=pos_type)
                end
            catch e
                @error "Failed to close position" asset=ai.asset.symbol exception=e
            end
        end
    end
end
```

#### Risk Metrics and Monitoring

```julia
# Real-time risk monitoring
function monitor_risk_metrics(s)
    metrics = Dict{Symbol, Float64}()
    
    # Portfolio level metrics
    metrics[:total_exposure] = calculate_total_exposure(s)
    metrics[:leverage_ratio] = calculate_leverage_ratio(s)
    metrics[:var_1d] = calculate_var(s, 0.05, 1)  # 1-day 5% VaR
    metrics[:portfolio_beta] = calculate_portfolio_beta(s)
    
    # Position level metrics
    foreach(s.universe) do ai
        symbol = ai.asset.symbol
        pos = inst.position(ai)
        
        if !isnothing(pos)
            metrics[Symbol("exposure_\$(symbol)")] = abs(inst.freecash(ai)) * closeat(ai.ohlcv, available(s.timeframe, now()))
            metrics[Symbol("pnl_\$(symbol)")] = pos.unrealized_pnl
        end
    end
    
    # Store metrics for monitoring
    s.attrs[:risk_metrics] = metrics
    
    # Check risk limits
    check_risk_limits(s, metrics)
    
    return metrics
end

function check_risk_limits(s, metrics)
    limits = Dict(
        :total_exposure => freecash(s) * 2.0,  # Max 2x exposure
        :leverage_ratio => 5.0,                # Max 5x leverage
        :var_1d => freecash(s) * 0.05         # Max 5% daily VaR
    )
    
    for (metric, limit) in limits
        if haskey(metrics, metric) && metrics[metric] > limit
            @warn "Risk limit exceeded" metric value=metrics[metric] limit
            # Implement risk reduction measures
            reduce_risk_exposure(s, metric)
        end
    end
end
```

This comprehensive order management and risk documentation provides practical patterns for implementing robust trading strategies with proper risk controls.
## Se
e Also

### Core Documentation
- **[Data Management](data.md)** - Working with OHLCV data and storage
- **[Execution Modes](engine/mode-comparison.md)** - Understanding Sim, Paper, and Live modes
- **[Optimization](optimization.md)** - Parameter optimization and backtesting
- **[Plotting](plotting.md)** - Visualizing strategy performance and results

### Advanced Topics
- **[Customization Guide](customizations/customizations.md)** - Extending Planar's functionality
- **[Custom Orders](customizations/orders.md)** - Implementing custom order types
- **[Exchange Extensions](customizations/exchanges.md)** - Adding new exchange support

### API Reference
- **[Strategy API](API/strategies.md)** - Complete strategy function reference
- **[Engine API](API/engine.md)** - Core engine functions
- **[Strategy Tools](API/strategytools.md)** - Utility functions for strategies
- **[Strategy Stats](API/strategystats.md)** - Performance analysis functions

### Support
- **[Troubleshooting](../troubleshooting/index.md)** - Common strategy development issues
- **[Community](contacts.md)** - Getting help and sharing strategies

## Next Steps

After mastering strategy development:

1. **[Optimize Your Strategies](../optimization.md)** - Learn parameter optimization techniques
2. **[Visualize Performance](plotting.md)** - Create compelling performance charts
3. **[Deploy Live](engine/live.md)** - Move from backtesting to live trading
4. **[Extend Functionality](customizations/customizations.md)** - Customize Planar for your needs