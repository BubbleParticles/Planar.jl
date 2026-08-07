# Data API

The Data module provides comprehensive functionality for managing market data in Planar. It handles OHLCV (Open, High, Low, Close, Volume) data storage, retrieval, and manipulation using efficient storage formats like Zarr and LMDB.

## Overview

The Data module is responsible for:
- OHLCV data storage and retrieval
- Data persistence using Zarr format for large datasets
- LMDB key-value storage for fast access
- Data validation and integrity checking
- Efficient data structures for time series analysis

## Core Data Structures

### Data Persistence

#### Zarr Storage

Planar uses Zarr format for efficient storage of large time series datasets.


#### LMDB Key-Value Storage

For fast metadata and configuration storage.


## Complete API Reference

```@autodocs
Modules = [PlanarCore.Data]
```

## See Also

- **[Data Management Guide](../guides/data-management.md)** - Complete guide to working with market data
- **[Processing API](processing.md)** - Data processing and transformation functions
- **[DFUtils API](dfutils.md)** - DataFrame manipulation utilities
- **[Engine API](engine.md)** - Core execution engine functions
- **[Fetch API](fetch.md)** - Data fetching and retrieval utilities
