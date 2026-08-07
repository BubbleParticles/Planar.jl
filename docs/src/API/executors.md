# Executors API

The Executors module handles order execution and trade management in Planar. It provides the interface between strategy logic and actual order placement, managing the execution lifecycle across different trading modes.

## Overview

The Executors module is responsible for:
- Order creation and validation
- Trade execution across different modes (sim, paper, live)
- Order lifecycle management
- Position tracking and updates
- Risk management and validation

## Complete API Reference

```@autodocs
Modules = [PlanarCore.Executors]
```

## See Also

- **[Strategies API](strategies.md)** - Strategy base classes and interfaces
- **[OrderTypes API](../customizations/orders.md)** - Order types and structures
- **[Engine API](engine.md)** - Core execution engine functions
- **[Instances API](instances.md)** - Asset instance management
- **[Strategy Development Guide](../guides/strategy-development.md)** - Building trading strategies
- **[Execution Modes Guide](../guides/execution-modes.md)** - Understanding different execution modes
