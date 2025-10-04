---
category: "strategy-development"
difficulty: "advanced"
topics: [execution-modes, margin-trading, exchanges, data-management, optimization, strategy-development, troubleshooting, visualization]
last_updated: "2025-10-04"---
---

# API Reference

This section provides comprehensive documentation for all Planar.jl modules and functions.

## Core Modules

### [Data Management](data.md)
Data structures, persistence, and [OHLCV data](../guides/data-management.md#ohlcv-data) handling.

### [Engine](engine.md)
Core execution engine for [backtesting](../guides/execution-modes.md#[simulation](../guides/execution-modes.md#simulation-mode)-mode), [paper trading](../guides/execution-modes.md#paper-mode), and [live trading](../guides/execution-modes.md#live-mode).

### [Exchanges]([exchanges](../exchanges.md).md)
Exchange interfaces and connectivity.

### [Instruments](instruments.md)
Financial instrument definitions and management.

### [Strategies]([strategies](../guides/strategy-development.md).md)
Strategy base classes and interfaces.

## Data Processing

### [Fetch](fetch.md)
Data fetching and retrieval utilities.

### [Processing](processing.md)
Data processing and transformation functions.

### [Prices](prices.md)
Price data structures and utilities.

### [Collections](collections.md)
Specialized collection types and utilities.

## Execution & Trading

### [Executors](executors.md)
Order execution and trade management.

### [Instances](instances.md)
Strategy instance management.

### [CCXT Integration](ccxt.md)
[CCXT](../[exchanges](../exchanges.md).md#ccxt-integration) library integration and utilities.

## Analysis & Optimization

### [Metrics](metrics.md)
Performance metrics and analysis.

### [Optimization]([optimization](../optimization.md).md)
Parameter [optimization](../optimization.md) and hyperparameter tuning.

### [Strategy Tools](strategytools.md)
Utilities for [strategy](../guides/strategy-development.md) development.

### [Strategy Statistics](strategystats.md)
Statistical analysis of [strategy](../guides/strategy-development.md) performance.

## Visualization & UI

### [Plotting](plotting.md)
Charting and visualization functions.

### [Progress Bars](pbar.md)
Progress tracking and display utilities.

## Utilities

### [DataFrame Utils](dfutils.md)
DataFrame manipulation utilities.

### [Python Integration](python.md)
Python interoperability functions.

### [Miscellaneous](misc.md)
Additional utility functions and helpers.

## Quick Navigation

- **Getting Started**: See the [Getting Started Guide](../getting-started/index.md)
- **Type System**: Learn about [Planar's Type System](../types.md)
- **Strategy Development**: Read the [Strategy Guide](../[strategy](../guides/strategy-development.md).md)
- **Troubleshooting**: Check the [Troubleshooting Guide](../[troubleshooting](../troubleshooting/).md)


## See Also

- **[Exchanges](../exchanges.md)** - Exchange integration and configuration
- **[Config](../config.md)** - Exchange integration and configuration
- **[Optimization](../optimization.md)** - Performance optimization techniques
- **[Performance Issues](../troubleshooting/performance-issues.md)** - Troubleshooting: Performance optimization techniques
- **[Data Management](../guides/data-management.md)** - Guide: Data handling and management
- **[Exchanges](../exchanges.md)** - Data handling and management

## Function Index

Each module page contains:
- Module overview and purpose
- Function signatures and descriptions
- Usage examples
- Related functions and cross-references

For specific function documentation, navigate to the appropriate module page above.