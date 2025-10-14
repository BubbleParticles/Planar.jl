# Strategies API

The Strategies module provides the core framework for building and managing trading strategies in Planar. It includes the base `Strategy` type, execution interfaces, and essential functions for strategy development.

## Overview

The `Strategy` type is the central component of the Planar framework. It encapsulates:
- Strategy configuration and parameters
- Asset universe and market data
- Order management and execution state
- Cash and position tracking
- Exchange connectivity

## Core Types

### Strategy Types


### Usage Examples

#### Creating a Strategy


#### Accessing Strategy Information


#### Working with Assets


## Strategy Interface Functions

### Core Interface

The strategy interface defines the main entry points that your strategy must implement:


#### Implementation Example


## Cash and Position Management

### Cash Functions


### Position Information


## Order Management

### Order Access


## Utility Functions

### Strategy Identification


### Thread Safety


## Common Patterns

### Data Loading Pattern


### Error Handling Pattern


### Performance Pattern


## Complete API Reference

```@autodocs
Modules = [Strategies]
```

## See Also

- **[Strategy Development Guide](../guides/strategy-development.md)** - Complete guide to building strategies
- **[Engine API](engine.md)** - Core execution engine functions
- **[Executors API](executors.md)** - Order execution and management
- **[Instances API](instances.md)** - Asset instance management
- **[Getting Started](../getting-started/first-strategy.md)** - Your first strategy tutorial
