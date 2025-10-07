---
title: "API Reference"
description: "Complete API reference for Planar.jl modules and functions"
category: "reference"
difficulty: "advanced"
prerequisites: ["getting-started", "strategy-development"]
topics: ["api-reference", "functions", "modules"]
last_updated: "2025-10-04"
estimated_time: "Reference material"
---

# API Reference

This section provides comprehensive documentation for all Planar.jl modules and functions. Each module page includes function signatures, detailed descriptions, working code examples, and usage patterns.

## Quick Navigation

### Core Trading Components
- **[Strategies](strategies.md)** - Strategy base classes, interfaces, and core functionality
- **[Engine](engine.md)** - Core execution engine for backtesting, paper trading, and live trading
- **[Executors](executors.md)** - Order execution and trade management
- **[Instances](instances.md)** - Strategy instance management and asset handling

### Data Management
- **[Data](data.md)** - Data structures, persistence, and OHLCV data handling
- **[Fetch](fetch.md)** - Data fetching and retrieval utilities
- **[Processing](processing.md)** - Data processing and transformation functions
- **[Collections](collections.md)** - Specialized collection types and utilities

### Exchange Integration
- **[Exchanges](exchanges.md)** - Exchange interfaces and connectivity
- **[CCXT Integration](ccxt.md)** - CCXT library integration and utilities
- **[Instruments](instruments.md)** - Financial instrument definitions and management

### Analysis & Optimization
- **[Metrics](metrics.md)** - Performance metrics and analysis
- **[Optimization](optimization.md)** - Parameter optimization and hyperparameter tuning
- **[Strategy Tools](strategytools.md)** - Utilities for strategy development
- **[Strategy Statistics](strategystats.md)** - Statistical analysis of strategy performance

### Visualization & Utilities
- **[Plotting](plotting.md)** - Charting and visualization functions
- **[DataFrame Utils](dfutils.md)** - DataFrame manipulation utilities
- **[Python Integration](python.md)** - Python interoperability functions
- **[Miscellaneous](misc.md)** - Additional utility functions and helpers

## Getting Started with the API

### Basic Usage Pattern

Most Planar functions follow these common patterns:

```julia
using Planar
@environment!

# Load a strategy
s = strategy(:MyStrategy)

# Access strategy data
assets_list = assets(s)
exchange_info = exchange(s)
current_cash = freecash(s)

# Work with data
ohlcv_data = load_ohlcv(s)
fetch_ohlcv!(s)
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

For more information on contributing, see the [Contributing Guide](../../resources/contributing.md).