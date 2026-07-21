# Strategy Development Guide



This comprehensive guide covers everything you need to know about developing trading [strategies](../guides/strategy-development.md) in Planar. From basic concepts to advanced patterns, you'll learn how to build robust, profitable trading systems using [Julia](https://julialang.org/)'s powerful [dispatch system](../guides/strategy-development.md#Dispatch-System).

## Quick Navigation

- **[Strategy Fundamentals](#Strategy-Fundamentals)** - Core concepts and architecture
- **[strategies](../guides/strategy-development.md)** - Interactive and manual setup
- **[Strategy Interface](#Strategy-Interface)** - Understanding the call! dispatch system
- **[Advanced Examples](#Advanced-Examples)** - Multi-[timeframe](../guides/data-management.md#timeframes), portfolio, and [optimization](../optimization.md) strategies
- **[Best Practices](#Best-Practices)** - Code organization and performance tips
- **[troubleshooting](../troubleshooting/index.md)** - Common issues and solutions

## Prerequisites

Before diving into strategy development, ensure you have:

- Completed the [Getting Started Guide](../getting-started/index.md)
- Basic understanding of [Data Management](../guides/data-management.md)
- Familiarity with [Execution Modes](execution-modes.md)

## Related Topics

- **[optimization](../optimization.md)** - Parameter tuning and [backtesting](../guides/execution-modes.md#simulation)-mode)
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
- **Margin Support**: Full support for isolated and [cross margin](../guides/strategy-development.md#Margin-Modes) trading

#### Strategy Type Hierarchy


Where:
- `Mode`: Execution mode (Sim, Paper, Live)
- `Name`: Strategy module name as Symbol
- `Exchange`: Exchange identifier
- `Margin`: Margin mode (NoMargin, Isolated, Cross)
- `QuoteCurrency`: Base currency symbol

### Dispatch System

The strategy interface uses Julia's [multiple dispatch](../guides/strategy-development.md#Dispatch-System) through the `call!` function. This pattern allows you to define different behaviors for different contexts while maintaining clean, extensible code.

#### Key Dispatch Patterns

**Type vs Instance Dispatch**:
- Methods dispatching on `Type{<:Strategy}` are called before strategy construction
- Methods dispatching on strategy instances are called during runtime


**Action-Based Dispatch**:

#### Exchange-Specific Dispatch

You can customize behavior for specific [exchanges](../exchanges.md):


### Margin Trading Concepts

Planar provides comprehensive [margin trading](../guides/strategy-development.md#Margin-Trading-Concepts) support with proper position management and risk controls.

#### Margin Modes

**NoMargin**: Spot trading only

**Isolated Margin**: Each position has independent margin

**Cross Margin**: Shared margin across all positions

#### Position Management


#### Risk Management Patterns


## Creating Strategies

### Interactive Strategy Generator

The simplest way to create a strategy is using the interactive generator, which prompts for all required [configuration](../config.md) options:


### Non-Interactive Strategy Creation

You can also create strategies programmatically without user interaction:


### Manual Strategy Setup

If you want to create a strategy manually you can either:
- Copy the `user/strategies/Template.jl` to a new file in the same directory and customize it
- Generate a new project in `user/strategies` and customize `Template.jl` to be your project entry file

For more advanced setups you can also use `Planar` as a library, and construct the strategy object directly from your own module:


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


The strategy name corresponds to the module name, which is imported from:
- `user/strategies/Example.jl` (single file strategy)
- `user/strategies/Example/src/Example.jl` (project-based strategy)

### Strategy Type Structure


### Basic Strategy Module


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


## Advanced Examples

### Multi-Timeframe Strategy


### Portfolio Rebalancing Strategy


### Advanced Optimization Strategy


### Simple Moving Average Strategy


### Margin Trading Strategy


## Best Practices

### Code Organization

1. **Module Constants**: Define strategy metadata at the top

2. **Environment Macros**: Use appropriate environment macros within your strategy module

3. **Parameter Management**: Use strategy attributes for parameters

### Error Handling


### Performance Optimization

1. **Minimize Allocations**: Reuse data structures when possible
2. **Batch Operations**: Group similar operations together
3. **Conditional Logic**: Use early returns to avoid unnecessary computations


### Testing and Validation


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

**Test Components Individually**:

**Use Simulation Mode for Debugging**:

For detailed troubleshooting steps and platform-specific solutions, visit [Strategy Problems](../troubleshooting/strategy-problems.md).es
- Check that `call!(s::SC, ::OptScore)` returns appropriate metrics
- Verify that parameter overrides are applied correctly in `call!(s::SC, params, ::OptRun)`

### Debugging Strategies

#### Enable Debug Logging


#### Strategy State Inspection


#### Performance Profiling


### Removing Strategies

The function `remove_strategy` allows you to discard a strategy by its name:


## Advanced Topics

### Dynamic Universe Management

The universe (`s.universe`) is backed by a `DataFrame` (`s.universe.data`). It is possible to add and remove assets from the universe during runtime, although this feature is not extensively tested.

```julia
# Activate Planar project
import Pkg
Pkg.activate("Planar")

try
    using Planar
    @environment!

    # Add new asset to universe (experimental)
    function add_asset_to_universe_example(s, symbol::String)
        # This requires careful handling of data synchronization
        @info "Adding asset to universe: $symbol"
        # Real implementation would be:
        # new_asset = Asset(symbol, exchange(s))
        # Careful handling of data synchronization required
        println("Asset $symbol would be added to universe")
    end

    # Remove asset from universe (experimental)
    function remove_asset_from_universe_example(s, symbol::String)
        # Close any open positions first
        @info "Removing asset from universe: $symbol"
        # Real implementation would be:
        # ai = s[symbol]
        # if !isnothing(ai) && freecash(ai) != 0
        #     close_position(s, ai)
        # end
        println("Asset $symbol would be removed from universe")
    end
    
    println("Universe management functions defined (experimental)")
    
catch e
    @warn "Planar not available: $e"
end
```

### Custom Indicators


### Integration with External Libraries


This comprehensive guide provides everything you need to develop sophisticated trading strategies in Planar. Start with the basic examples and gradually work your way up to more advanced patterns as you become comfortable with the dispatch system and strategy architecture.
