<!--
title: "Data API"
description: "Data structures, persistence, and OHLCV data handling"
category: "api-reference"
difficulty: "advanced"
prerequisites: ["getting-started", "data-management"]
topics: ["api-reference", "data", "ohlcv", "storage"]
last_updated: "2025-10-04"
estimated_time: "Reference material"
-->

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

### OHLCV Data Access


#### Usage Examples


### Data Loading and Storage

#### Primary Data Functions


#### Advanced Data Operations


### Data Persistence

#### Zarr Storage

Planar uses Zarr format for efficient storage of large time series datasets:


#### LMDB Key-Value Storage

For fast metadata and configuration storage:


## Data Validation and Integrity

### Data Quality Checks


### Data Cleaning


## DataFrame Integration

### Working with DataFrames


## Performance Optimization

### Efficient Data Access Patterns


### Memory Management


## Data Streaming and Updates

### Real-time Data Updates


## Common Data Patterns

### Moving Averages


### Price Analysis


## Complete API Reference

```@autodocs
Modules = [Planar.Data]
```

## See Also

- **[Data Management Guide](../guides/data-management.md)** - Complete guide to working with market data
- **[Processing API](processing.md)** - Data processing and transformation functions
- **[DFUtils API](dfutils.md)** - DataFrame manipulation utilities
- **[Engine API](engine.md)** - Core execution engine functions
- **[Fetch API](fetch.md)** - Data fetching and retrieval utilities
