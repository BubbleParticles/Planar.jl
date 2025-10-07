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


#### Usage Examples


#### Advanced Data Operations


### Strategy Execution

#### Execution Control


#### Example: Strategy Lifecycle


### Exchange Integration

#### Exchange Access


#### Example: Exchange Operations


## Data Structures and Types

### Core Types

The Engine module works with several key types:


### Data Handlers


## Integration Patterns

### Backtesting Pattern


### Paper Trading Pattern


### Live Trading Pattern


## Performance Optimization

### Efficient Data Access


### Batch Operations


## Error Handling

### Robust Data Loading


### Exchange Connection Handling


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
