# Instruments API

The Instruments module provides definitions and management for financial instruments in Planar. It handles different asset types, currency management, and derivative instruments for advanced trading strategies.

## Overview

The Instruments module includes:
- Base asset types and currency definitions
- Cash and currency management
- Derivative instruments (futures, options, etc.)
- Asset validation and conversion utilities
- Compact number formatting for financial data

## Core Asset Types

### Base Asset Types


### Asset Creation and Management


### Currency Operations


#### Advanced Cash Operations


## Derivative Instruments

### Derivative Types


### Working with Derivatives


### Derivative Portfolio Management


## Number Formatting

### Compact Number Display


## Asset Validation and Utilities

### Asset Validation


### Asset Comparison and Sorting


## Integration with Strategy Framework

### Asset Instance Integration


## Performance Considerations

### Efficient Asset Operations


## Complete API Reference

```@autodocs
Modules = [Instruments, Instruments.Derivatives]
Order = [:type]
```

```@autodocs
Modules = [Instruments, Instruments.Derivatives]
Order = [:function]
```

```@autodocs
Modules = [Instruments, Instruments.Derivatives]
Order = [:macro, :constant]
```

## See Also

- **[Instances API](instances.md)** - Asset instance management
- **[Strategies API](strategies.md)** - Strategy base classes and interfaces
- **[Data API](../data.md)** - Data structures and management
- **[Strategy Development Guide](../guides/strategy-development.md)** - Building trading strategies
- **[Advanced Trading Guide](../advanced/risk-management.md)** - Margin and derivative trading
