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


**Action-Based Dispatch**:

#### Exchange-Specific Dispatch

You can customize behavior for specific [exchanges](../exchanges.md):


### Margin Trading Concepts

Planar provides comprehensive [margin trading](../guides/strategy-development.md#margin-trading-concepts) support with proper position management and risk controls.

#### Margin Modes

**NoMargin**: Spot trading only

**Isolated Margin**: Each position has independent margin

**Cross Margin**: Shared margin across all positions

#### Position Management


#### Risk Management Patterns


## Creating a New Strategy

### Interactive Strategy Generator

The simplest way to create a strategy is using the interactive generator, which prompts for all required [configuration](../config.md) options:

```julia
# Activate Planar project
import Pkg
Pkg.activate("Planar")

try
    using Planar
    
    # Example of strategy generation (interactive in real usage)
    println("Strategy generation example:")
    println("Strategy name: MyNewStrategy")
    println("Available timeframes: 1m, 5m, 15m, 1h")
    
    # Note: Planar.generate_strategy() is interactive and requires user input
    # This example shows the expected output format
catch e
    @warn "Planar module not fully available: $e"
end
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

## Loading a Strategy

### Basic Strategy Loading

Strategies are instantiated by loading a Julia module at runtime:


The strategy name corresponds to the module name, which is imported from:
- `user/strategies/Example.jl` (single file strategy)
- `user/strategies/Example/src/Example.jl` (project-based strategy)

After module import, the strategy is instantiated by calling `call!(::Type{S}, ::LoadStrategy, cfg)`.

### Strategy Type Structure


### Example Strategy Module


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


#### Optional Methods


### Advanced Dispatch Patterns

#### Conditional Dispatch by Mode


#### Parameter-Based Dispatch


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


### Portfolio Rebalancing Strategy


### Advanced Optimization Strategy


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


### Margin Trading Strategy


## Best Practices

### Code Organization

1. **Module Constants**: Define strategy metadata at the top

2. **Environment Macros**: Use appropriate environment macros

3. **Parameter Management**: Use strategy attributes for parameters

### Error Handling


### Performance Optimization

1. **Minimize Allocations**: Reuse data structures when possible
2. **Batch Operations**: Group similar operations together
3. **Conditional Logic**: Use early returns to avoid unnecessary computations


### Testing and Validation


## Resizeable Universe

The universe (`s.universe`) is backed by a `DataFrame` (`s.universe.data`). It is possible to add and remove assets from the universe during runtime, although this feature is not extensively tested.

### Dynamic Asset Management


## Troubleshooting and Debugging

### Common Strategy Issues

#### 1. Strategy Loading Problems

**Issue**: Strategy fails to load with module not found error

**Solutions**:
- Verify the strategy file exists in `user/strategies/`
- Check that the module name matches the file name
- Ensure the strategy module is properly defined:


**Issue**: Strategy loads but crashes during initialization

**Solutions**:
- Add the `@strategyenv!` macro to import required types
- Verify all required constants are defined:


#### 2. Data Access Issues

**Issue**: [OHLCV data](../guides/data-management.md#ohlcv-data) is empty or missing

**Solutions**:
- Check data availability for your timeframe and date range
- Verify exchange supports the requested markets
- Ensure sufficient warmup period:


**Issue**: Inconsistent data between timeframes

**Solutions**:
- Use `available()` function to get valid timestamps
- Handle missing data gracefully:


#### 3. Order Execution Problems

**Issue**: Orders are rejected with insufficient funds

**Solutions**:
- Check available cash before placing orders:


**Issue**: Orders fail due to minimum size requirements

**Solutions**:
- Check exchange limits before placing orders:


#### 4. Margin Trading Issues

**Issue**: Leverage updates fail

**Solutions**:
- Check exchange-specific leverage limits
- Update leverage before placing orders:


### Debugging Techniques

#### 1. Logging and Monitoring


#### 2. Strategy State Inspection


#### 3. Performance Profiling


#### 4. Unit Testing Strategies


### Error Recovery Patterns

#### 1. Graceful Degradation


#### 2. Circuit Breaker Pattern


### Performance Optimization Tips

1. **Minimize Data Access**: Cache frequently used values
2. **Batch Operations**: Group similar operations together
3. **Use Type Stability**: Ensure functions return consistent types
4. **Profile Regularly**: Use Julia's profiling tools to identify bottlenecks
5. **Memory Management**: Avoid unnecessary allocations in hot paths

der Management and Risk Control

### Order Types and Execution

Planar supports various order types for different trading scenarios. Understanding when and how to use each type is crucial for effective strategy implementation.

#### Market Orders

Market orders execute immediately at the current market price:


#### Limit Orders

Limit orders execute only at a specified price or better:


#### Stop Orders

Stop orders become market orders when a trigger price is reached:


#### Order Management Patterns


### Position Management for Margin Trading

#### Position Types and States


#### Leverage Management


#### Position Sizing Strategies


### Risk Management Patterns

#### Stop Loss Strategies


#### Take Profit Strategies


#### Portfolio Risk Management


#### Risk Metrics and Monitoring


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