# Instances API

The Instances module manages asset instances within strategies, handling position tracking, margin management, and asset-specific data. It provides the bridge between abstract assets and their concrete usage in trading strategies.

## Overview

The Instances module handles:
- Asset instance creation and management
- Position tracking for spot and margin trading
- OHLCV data association with assets
- Fee calculation and management
- Balance and cash tracking
- Margin and leverage management

## Core Types

### Asset Instance


### Position Types


## Asset Instance Management

### Basic Asset Instance Operations


### Asset Instance Information


### Data Access and Management


## Position Management

### Spot Trading Positions


### Margin Trading Positions


## Fee Management

### Fee Calculation


## Cash and Balance Management

### Cash Operations


### Portfolio Value Calculation


## Performance Optimization

### Efficient Instance Operations


## Integration Examples

### Strategy Integration


## Complete API Reference

```@autodocs
Modules = [Planar.Engine.Instances]
```

## See Also

- **[Instruments API](instruments.md)** - Financial instrument definitions
- **[Strategies API](strategies.md)** - Strategy base classes and interfaces
- **[Data API](../data.md)** - Data structures and management
- **[Executors API](executors.md)** - Order execution and management
- **[Strategy Development Guide](../guides/strategy-development.md)** - Building trading strategies
- **[Advanced Trading Guide](../advanced/risk-management.md)** - Margin and derivative trading
