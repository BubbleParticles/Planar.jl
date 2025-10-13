<!--
category: "strategy-development"
difficulty: "advanced"
topics: [execution-modes, margin-trading, exchanges, data-management, optimization, strategy-development, troubleshooting, visualization, configuration]
last_updated: "2025-10-04"
-->

# Data Management

<!--
Keywords: OHLCV data, Zarr storage, LMDB, data fetching, scrapers, watchers, historical data, real-time data, market data
Description: Comprehensive data management system for OHLCV and time-series market data using Zarr storage, LMDB backend, and multiple data collection methods.
-->

The Data module provides comprehensive storage and management of [OHLCV](guides/data-management.md#ohlcv-data) (Open, High, Low, Close, Volume) data and other time-series [market data](guides/data-management.md).

## Quick Navigation

- **[Storage Architecture](#storage-architecture)** - Understanding Zarr and LMDB backends
- **[Historical Data](#historical-data-with-scrapers)** - Using Scrapers for bulk data collection
- **[Real-Time Data](#real-time-data-with-fetch)** - Fetching live data from exchanges
- **[Live Streaming](#live-data-streaming-with-watchers)** - Continuous data monitoring

## Prerequisites

- Basic understanding of [OHLCV data concepts](getting-started/index.md)
- Familiarity with [Exchange setup](exchanges.md)

## Related Topics

- **[Strategy Development](guides/strategy-development.md)** - Using data in trading strategies
- **[Watchers](watchers/watchers.md)** - Real-time data monitoring
- **[Processing](API/processing.md)** - Data transformation and analysis

## Storage Architecture

### Zarr Backend

Planar uses **Zarr** as its primary storage backend, which offers several advantages:

- **Columnar Storage**: Optimized for array-based data, similar to Feather or Parquet
- **Flexible Encoding**: Supports different compression and encoding schemes
- **Storage Agnostic**: Can be backed by various storage layers, including network-based systems
- **Chunked Access**: Efficient for time-series queries despite chunk-based reading

The framework wraps a Zarr subtype of `AbstractStore` in a [`Planar.Data.ZarrInstance`](@ref). The global `ZarrInstance` is accessible at `Data.zi[]`, with LMDB as the default underlying store.

### Data Organization

[OHLCV data](guides/data-management.md#ohlcv-data) is organized hierarchically using [`Planar.Data.key_path`](@ref):

## Data Architecture Overview

The Data module provides a comprehensive [data management](guides/data-management.md) system with the following key components:

- **Storage Backend**: Zarr arrays with LMDB as the default store
- **Data Organization**: Hierarchical structure by exchange/source, pair, and timeframe
- **Data Types**: [OHLCV data](guides/data-management.md#ohlcv-data), generic time-series data, and cached metadata
- **Access Patterns**: Progressive loading for large datasets, contiguous time-series validation
- **Performance**: Chunked storage, compression, and optimized indexing

### Storage Hierarchy

Data is organized in a hierarchical structure:
```
ZarrInstance/
├── exchange_name/
│   ├── pair_name/
│   │   ├── [timeframe](guides/data-management.md#timeframes)/
│   │   │   ├── timestamp
│   │   │   ├── open
│   │   │   ├── high
│   │   │   ├── low
│   │   │   ├── close
│   │   │   └── volume
│   │   └── ...
│   └── ...
└── ...
```

## Data Collection Methods

Planar provides multiple methods for collecting market data, each optimized for different use cases:

## Historical Data with Scrapers

The Scrapers module provides access to historical data archives from major exchanges, offering the most efficient method for obtaining large amounts of historical data.

**Supported Exchanges**: Binance and Bybit archives

### Basic Scraper Usage


### Advanced Scraper Examples

Download multiple symbols and filter by quote currency using `bn.binancesyms()` and `scr.selectsyms()`.

### Market Types and Frequencies

Use different market types (`:spot`, `:um`, `:cm`), frequencies (`:daily`, `:monthly`), and data kinds (`:klines`, `:trades`, `:aggTrades`).

### Error Handling and Data Validation


!!! warning "Download Caching"
    Downloads are cached - requesting the same pair path again will only download newer archives.
    If data becomes corrupted, pass `reset=true` to force a complete redownload.

!!! tip "Performance Optimization"
    - **Monthly Archives**: Use for historical [backtesting](guides/execution-modes.md#simulation)-mode) (faster download, larger chunks)
    - **Daily Archives**: Use for recent data or frequent updates
    - **Parallel Downloads**: Consider for multiple symbols, but respect [exchange](exchanges.md) rate limits 

## Real-Time Data with Fetch

The Fetch module downloads data directly from exchanges using [CCXT](exchanges.md#ccxt-integration), making it ideal for:

- Getting the most recent market data
- Filling gaps in historical data
- Real-time data updates for [live trading](guides/execution-modes.md#live-mode)

### Basic Fetch Usage


### Advanced Fetch Examples


### Multi-Exchange Data Collection


### Rate Limit Management

Use delays between requests and validate data quality. Implement error handling for failed requests.

!!! warning "Rate Limit Considerations"
    Direct exchange fetching is heavily rate-limited, especially for smaller [timeframes](guides/data-management.md#timeframes).
    Use archives for bulk historical data collection.

!!! tip "Fetch Best Practices"
    - **Recent Updates**: Use fetch for recent data updates and gap filling
    - **Rate Limiting**: Implement delays between requests to respect exchange limits
    - **Data Validation**: Always validate fetched data before using in [strategies](guides/strategy-development.md)
    - **Raw Data**: Use `fetch_candles` for unchecked data when you need raw exchange responses

## Live Data Streaming with Watchers

The Watchers module enables real-time data tracking from exchanges and other sources, storing data locally for:

- Live trading operations
- Real-time data analysis
- Continuous market monitoring

### OHLCV Ticker Watcher

The ticker watcher monitors multiple pairs simultaneously using exchange ticker endpoints:



As a convention, the `view` property of a watcher shows the processed data. In this case, the candles processed
by the `ohlcv_ticker_watcher` will be stored in a dict.


### Single-Pair OHLCV Watcher

There is another OHLCV watcher based on trades, that tracks only one pair at a time with higher precision:


### Watcher Configuration

Configure watchers with custom intervals using `timeout_interval`, `fetch_interval`, and `flush_interval` parameters. Use `wc.start!()` and `wc.stop!()` for lifecycle management.

### Orderbook Watcher


### Custom Data Processing


### Error Handling and Resilience


### Data Persistence and Storage


Other implemented watchers are the orderbook watcher, and watchers that parse data feeds from 3rd party APIs.

!!! tip "Watcher Best Practices"
    - Monitor watcher health regularly with `wc.isrunning()`
    - Implement proper error handling and reconnection logic
    - Save data periodically to prevent loss during interruptions
    - Use appropriate fetch intervals to balance data freshness with rate limits
    - Consider using multiple watchers for redundancy in critical applications

## Custom Data Sources

Assuming you have your own pipeline to fetch candles, you can use the functions [`Planar.Data.save_ohlcv`](@ref) and [`Planar.Data.load_ohlcv`](@ref) to manage the data.

### Basic Custom Data Integration

To save the data, it is easier if you pass a standard OHLCV dataframe, otherwise you need to provide a `saved_col` argument that indicates the correct column index to use as the `timestamp` column (or use lower-level functions).


To load the data back:


### Advanced Custom Data Examples


### Custom Data Validation


### Working with Large Custom Datasets


### Generic Data Storage

If you want to save other kinds of data, there are the [`Planar.Data.save_data`](@ref) and [`Planar.Data.load_data`](@ref) functions. Unlike the ohlcv functions, these functions don't check for contiguity, so it is possible to store sparse data. The data, however, still requires a timestamp column, because data when saved can either be prepend or appended, therefore an index must still be available to maintain order.


### Serialized Data Storage

While OHLCV data requires a concrete type for storage (default `Float64`) generic data can either be saved with a shared type, or instead serialized. To serialize the data while saving pass the `serialize=true` argument to `save_data`, while to load serialized data pass `serialized=true` to `load_data`.


### Progressive Data Loading

When loading data from storage, you can directly use the `ZArray` by passing `raw=true` to `load_ohlcv` or `as_z=true` or `with_z=true` to `load_data`. By managing the array directly you can avoid materializing the entire dataset, which is required when dealing with large amounts of data.


Data is returned as a `DataFrame` with `open,high,low,close,volume,timestamp` columns.
Since these save/load functions require a timestamp column, they check that the provided index is contiguous, it should not have missing timestamps, according to the subject timeframe. It is possible to disable those checks by passing `check=:none`.

!!! warning "Data Contiguity"
    OHLCV save/load functions validate timestamp contiguity by default. Use `check=:none` to disable validation for irregular data.

!!! tip "Performance Optimization"
    - Use progressive loading (`raw=true`) for datasets larger than available memory
    - Process data in chunks when dealing with very large time series
    - Consider serialization for complex data structures that don't fit standard numeric types

## Data Indexing and Access Patterns

The Data module implements dataframe indexing by dates such that you can conveniently access rows by:


### Advanced Indexing Examples


### Timeframe Management

With ohlcv data, we can access the timeframe of the series directly from the dataframe by calling `timeframe!(df)`. This will either return the previously set timeframe or infer it from the `timestamp` column. You can set the timeframe by calling e.g. `timeframe!(df, tf"1m")` or `timeframe!!` to overwrite it.


### Efficient Data Slicing


### Data Aggregation and Resampling


## Caching and Performance Optimization

`Data.Cache.save_cache` and `Data.Cache.load_cache` can be used to store generic metadata like JSON payloads. The data is saved in the Planar data directory which is either under the `XDG_CACHE_DIR` if set or under `$HOME/.cache` by default.

### Basic Caching Usage


### Advanced Caching Examples


### Performance Optimization Strategies


### Cache Management


### Storage Configuration Optimization


## Data Processing and Transformation

The Data module provides comprehensive tools for processing and transforming financial data. This section covers data cleaning, validation, and transformation techniques.

### Data Cleaning and Validation


### Gap Detection and Filling


### Data Transformation and Feature Engineering


## Storage Configuration and Optimization

This section covers advanced storage configuration, optimization techniques, and troubleshooting for the Zarr/LMDB backend.

### Zarr Storage Configuration


### LMDB Configuration and Tuning


### Storage Optimization Strategies


### Data Validation and Integrity


### Troubleshooting Storage Issues


### Progressive Data Loading

When loading data from storage, you can directly use the `ZArray` by passing `raw=true` to `load_ohlcv` or `as_z=true` or `with_z=true` to `load_data`. By managing the array directly you can avoid materializing the entire dataset, which is required when dealing with large amounts of data.


!!! tip "Performance Best Practices"
    - Use progressive loading (`raw=true`) for datasets larger than available memory
    - Implement caching for expensive computations with appropriate TTL
    - Monitor cache size and clean up old entries regularly
    - Use chunked processing for very large datasets
    - Consider serialization for complex data structures that don't fit standard numeric types

## Real-Time Data Pipelines and Monitoring

This section covers advanced real-time data collection, processing, and monitoring using the Watchers system.

### Real-Time Data Pipeline Architecture


### Advanced Watcher Management


### Real-Time Data Processing


### Monitoring and Alerting


### Data Quality Monitoring


### Complete Pipeline Example


!!! warning "Storage Considerations"
    - Always backup data before performing repair operations
    - Monitor disk space regularly, especially when using compression
    - Validate data integrity periodically to catch corruption early
    - Use appropriate LMDB map sizes to avoid out-of-space errors

!!! tip "Real-Time Data Best Practices"
    - Implement comprehensive monitoring and alerting for production systems
    - Use multiple watchers per exchange for redundancy
    - Monitor data quality continuously to catch issues early
    - Implement automatic restart mechanisms for failed watchers
    - Cache processed data for quick access by trading [strategies](guides/strategy-development.md)
    - Set up proper logging and error handling for debugging issues
