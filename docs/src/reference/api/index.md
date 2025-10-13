<!--
title: "API Reference"
description: "Complete API reference for Planar.jl modules and functions"
category: "reference"
difficulty: "advanced"
prerequisites: ["getting-started", "strategy-development"]
topics: ["api-reference", "functions", "modules"]
last_updated: "2025-10-04"
estimated_time: "Reference material"
-->

# API Reference

This section provides comprehensive documentation for all Planar.jl modules and functions. Each module page includes function signatures, detailed descriptions, working code examples, and usage patterns.

## Quick Navigation

### Core Trading Components
- **[Strategies](../../API/strategies.md)** - Strategy base classes, interfaces, and core functionality
- **[Engine](../../API/engine.md)** - Core execution engine for backtesting, paper trading, and live trading
- **[Executors](../../API/executors.md)** - Order execution and trade management
- **[Instances](../../API/instances.md)** - Strategy instance management and asset handling

### Data Management
- **[Data](../../data.md)** - Data structures, persistence, and OHLCV data handling
- **[Fetch](../../API/fetch.md)** - Data fetching and retrieval utilities
- **[Processing](../../API/processing.md)** - Data processing and transformation functions
- **[Collections](../../API/collections.md)** - Specialized collection types and utilities

### Exchange Integration
- **[Exchanges](../../exchanges.md)** - Exchange interfaces and connectivity
- **[CCXT Integration](../../API/ccxt.md)** - CCXT library integration and utilities
- **[Instruments](../../API/instruments.md)** - Financial instrument definitions and management

### Analysis & Optimization
- **[Metrics](../../metrics.md)** - Performance metrics and analysis
- **[Optimization](../../optimization.md)** - Parameter optimization and hyperparameter tuning
- **[Strategy Tools](../../API/strategytools.md)** - Utilities for strategy development
- **[Strategy Statistics](../../API/strategystats.md)** - Statistical analysis of strategy performance

### Visualization & Utilities
- **[Plotting](../../plotting.md)** - Charting and visualization functions
- **[DataFrame Utils](../../API/dfutils.md)** - DataFrame manipulation utilities
- **[Python Integration](../../API/python.md)** - Python interoperability functions
- **[Miscellaneous](../../API/misc.md)** - Additional utility functions and helpers

## Getting Started with the API

### Basic Usage Pattern

Most Planar functions follow these common patterns:

```julia
# Activate PlanarInteractive project
import Pkg
Pkg.activate("PlanarInteractive")

try
    using PlanarInteractive
    @environment!

    # Example API usage patterns
    println("Common Planar API patterns:")
    
    # Load a strategy (example)
    println("s = strategy(:MyStrategy)  # Load strategy")
    
    # Access strategy data (examples)
    println("assets_list = assets(s)    # Get assets")
    println("exchange_info = exchange(s) # Get exchange")
    println("current_cash = freecash(s)  # Get cash")
    
    # Work with data (examples)
    println("ohlcv_data = load_ohlcv(s)  # Load OHLCV data")
    println("fetch_ohlcv!(s)            # Fetch new data")
    
    # Note: Real usage requires proper strategy configuration
    
catch e
    @warn "PlanarInteractive not available: $e"
end
```

### Common Function Categories

1. **Strategy Functions**: Functions that operate on `Strategy` objects
2. **Data Functions**: Functions for loading, processing, and managing market data
3. **Order Functions**: Functions for creating and managing orders
4. **Analysis Functions**: Functions for calculating metrics and statistics
5. **Utility Functions**: Helper functions for common operations

## Function Naming Conventions

- Functions ending with `!` modify their arguments in-place
- Functions starting with `is` return boolean values
- Functions starting with `get` retrieve information
- Functions starting with `set` modify configuration or state

## Error Handling

Most API functions use Julia's standard error handling:


## Performance Considerations

- Use in-place functions (ending with `!`) when possible to avoid allocations
- Batch operations when working with multiple assets
- Consider using `@async` for independent operations
- Cache frequently accessed data

## See Also

- **[Getting Started Guide](../../getting-started/index.md)** - Introduction to Planar
- **[Strategy Development Guide](../../guides/strategy-development.md)** - Building trading strategies
- **[Data Management Guide](../../guides/data-management.md)** - Working with market data
- **[Troubleshooting](../../troubleshooting/index.md)** - Common issues and solutions

## Contributing to API Documentation

If you find missing or incorrect information in the API documentation, please:

1. Check the source code for the most up-to-date function signatures
2. Test any code examples before submitting changes
3. Follow the established documentation format and style
4. Include working examples for new functions

For more information on contributing, see the Contributing Guide.