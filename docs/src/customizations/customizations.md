# Comprehensive Customization Guide

Planar's architecture is built around Julia's powerful dispatch system, enabling deep customization without modifying core framework code. This guide provides detailed instructions for extending Planar's functionality through custom implementations.

## Understanding Planar's Dispatch System

Planar leverages Julia's multiple dispatch to provide customization points throughout the framework. The key insight is that behavior is determined by the combination of argument types, allowing you to specialize functionality for specific scenarios.

### Core Parametrized Types

The framework provides parametrized types for various elements:
- **Strategies**: `Strategy{Mode}` where `Mode` can be `Sim`, `Paper`, or `Live`
- **Assets**: `Asset`, `Derivative` and other `AbstractAsset` subtypes
- **Instances**: `AssetInstance{Asset, Exchange}` combining assets with [exchanges](../exchanges.md)
- **Orders and Trades**: `Order{OrderType}` and `Trade{OrderType}`
- **Exchanges**: `Exchange` subtypes with `ExchangeID` parameters

### Dispatch Patterns

Planar uses several dispatch patterns for customization:


## Custom Order Types Implementation

### Basic Order Type Definition

To implement a custom order type, create an abstract type inheriting from `OrderType`:


This creates `TrailingStopOrder`, `TrailingStopBuy`, and `TrailingStopSell` types.

### Order State Management

Custom orders often require additional state. Define a state structure:


### Order Constructor

Implement a constructor for your custom order:


### Order Execution Logic

Implement the execution logic for different modes:


## Custom Exchange Implementation

### Exchange Interface Requirements

To implement a custom [exchange](../exchanges.md), you need to satisfy the interface defined by the `check` function in the `Exchanges` module. Here's a comprehensive example:


### Exchange-Specific Customizations

You can customize behavior for specific exchanges using dispatch:


## Advanced Customization Patterns

### Strategy-Specific Functions

Create "snowflake" functions for specific [strategies](../guides/strategy-development.md):


### Custom Indicators and Signals

Extend the framework with custom [technical indicators](../guides/strategy-development.md#technical-indicators):


### Custom Risk Management

Implement sophisticated risk management:


## Best Practices for Customization

### 1. Minimal Invasive Changes

Only override the specific functions that need customization. Leverage existing functionality wherever possible:


### 2. Type Stability

Ensure your customizations maintain type stability:


### 3. Error Handling

Implement robust error handling in custom functions:


### 4. Documentation and Testing

Document your customizations thoroughly:

```julia
# Activate Planar project
import Pkg
Pkg.activate("Planar")

try
    using Planar
    
    """
        custom_momentum_strategy(s::Strategy, ai::AssetInstance, date::DateTime)

    Custom momentum strategy implementation that uses a combination of RSI and MACD
    indicators to generate trading signals.

    # Arguments
    - `s::Strategy`: The strategy instance
    - `ai::AssetInstance`: The asset instance to trade
    - `date::DateTime`: Current timestamp
    
    # Returns
    - Signal indicating buy/sell/hold decision
    """
    function custom_momentum_strategy(s, ai, date)
        # Example implementation
        println("Custom momentum strategy called for $date")
        return :hold  # Example return value
    end
    
    println("Custom momentum strategy function defined")
    
catch e
    @warn "Planar not available: $e"
end

# Returns
- `Float64`: Signal strength between -1.0 (strong sell) and 1.0 (strong buy)

# Example
"""
function custom_momentum_strategy(s::Strategy, ai::AssetInstance, date::DateTime)
    # Implementation here
end
```

### 5. Performance Considerations

Be mindful of performance in hot paths:



## See Also

- **[Exchanges](../exchanges.md)** - Exchange integration and configuration
- **[Config](../config.md)** - Exchange integration and configuration
- **[Overview](../troubleshooting/index.md)** - Troubleshooting: Troubleshooting and problem resolution
- **[Optimization](../optimization.md)** - Performance optimization techniques
- **[Performance Issues](../troubleshooting/performance-issues.md)** - Troubleshooting: Performance optimization techniques
- **[Data Management](../guides/data-management.md)** - Guide: Data handling and management

## Troubleshooting Customizations

### Common Issues

1. **Method Ambiguity**: When [multiple dispatch](../guides/strategy-development.md#dispatch-system) signatures could match

2. **Type Piracy**: Extending methods you don't own on types you don't own

3. **Performance Issues**: Customizations that hurt performance

### Debugging Tips

1. Use `@code_warntype` to check for type instabilities
2. Use `@benchmark` to measure performance impact
3. Use `methodswith` to find all methods for a type
4. Use `@which` to determine which method will be called

Remember to [leverage](../guides/strategy-development.md#margin-modes) this flexibility to enhance functionality without overcomplicating the system, thus avoiding "complexity bankruptcy."
