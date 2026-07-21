# Data Management Guide



This comprehensive guide covers Planar's [data management](../guides/data-management.md) system for [OHLCV](../guides/data-management.md#ohlcv-data) (Open, High, Low, Close, Volume) data and other time-series [market data](../guides/data-management.md). Learn how to efficiently collect, store, and access market data using multiple collection methods and storage backends.

## Quick Navigation

- **[Storage Architecture](#Storage-Architecture)** - Understanding Zarr and LMDB backends
- **[Data Collection Methods](#Data-Collection-Methods)** - Overview of collection approaches
- **[Historical Data](#Historical-Data-Collection)** - Using Scrapers for bulk data collection
- **[Real-Time Data](#Real-Time-Data-Fetching)** - Fetching live data from [exchanges](../exchanges.md)
- **[Live Streaming](#Live-Data-Streaming)** - Continuous data monitoring with Watchers
- **[Custom Data Sources](#Custom-Data-Sources)** - Integrating your own data
- **[Data Access Patterns](#Data-Access-Patterns)** - Efficient data querying and indexing
- **[optimization](../optimization.md)** - Caching and [optimization](../optimization.md) [strategies](../guides/strategy-development.md)
- **[troubleshooting](../troubleshooting/index.md)** - Common issues and solutions

## Prerequisites

- Basic understanding of [OHLCV data concepts](../getting-started/index.md)
- Familiarity with [exchanges](../exchanges.md)

## Related Topics

- **[Strategy Development](strategy-development.md))** - Using data in trading [strategies](../guides/strategy-development.md)
- **[Watchers](../watchers/watchers.md)** - Real-time data monitoring
- **[Processing](../API/processing.md)** - Data transformation and analysis

## Storage Architecture

### Zarr Backend

Planar uses **Zarr** as its primary storage backend, which offers several advantages for time-series data:

- **Columnar Storage**: Optimized for array-based data, similar to Feather or Parquet
- **Flexible Encoding**: Supports different compression and encoding schemes
- **Storage Agnostic**: Can be backed by various storage layers, including network-based systems
- **Chunked Access**: Efficient for time-series queries despite chunk-based reading
- **Scalability**: Handles large datasets with progressive loading capabilities

The framework wraps a Zarr subtype of `AbstractStore` in a [`Planar.Data.ZarrInstance`](@ref). The global `ZarrInstance` is accessible at `Data.zi[]`, with LMDB as the default underlying store.

### Data Organization

[OHLCV data](../guides/data-management.md#ohlcv-data) is organized hierarchically using [`Planar.Data.key_path`](@ref):

```
ZarrInstance/
├── exchange_name/
│   ├── pair_name/
│   │   ├── [timeframe](../guides/data-management.md#timeframes)/
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

### Storage Hierarchy Benefits

This hierarchical organization provides:

- **Logical Grouping**: Data organized by source, instrument, and [timeframe](../guides/data-management.md#timeframes)
- **Efficient Queries**: Fast access to specific data subsets
- **Scalability**: Easy addition of new [exchanges](../exchanges.md), pairs, and [timeframes](../guides/data-management.md#timeframes)
- **Data Integrity**: Consistent structure across all data sources
- **Performance**: Optimized for common access patterns

## Data Collection Methods

Planar provides multiple methods for collecting market data, each optimized for different use cases:

| Method | Use Case | Speed | Data Range | Rate Limits |
|--------|----------|-------|------------|-------------|
| **Scrapers** | Historical bulk data | Fast | Months/Years | None |
| **Fetch** | Recent data, gap filling | Medium | Days/Weeks | High |
| **Watchers** | Real-time streaming | Real-time | Live only | Low |

### Choosing the Right Method

- **Use Scrapers** for initial historical data collection and [backtesting](../guides/execution-modes.md#simulationmode) datasets
- **Use Fetch** for recent data updates and filling gaps in historical data
- **Use Watchers** for [live trading](../guides/execution-modes.md#live-mode) and real-time analysis

**⚠️ Data collection issues?** See [Performance Issues: Data-Related](../troubleshooting/performance-issues.md#data-related-performance-issues) for slow loading and database problems, or [Exchange Issues](../troubleshooting/exchange-issues.md) for connectivity problems.
##
 Historical Data Collection

The Scrapers module provides access to historical data archives from major exchanges, offering the most efficient method for obtaining large amounts of historical data.

**Supported Exchanges**: Binance and Bybit archives

### Basic Scraper Usage


### Market Types and Frequencies


### Advanced Scraper Examples


### Error Handling and Data Validation


### Bybit Scrapers


!!! warning "Download Caching"
    Downloads are cached - requesting the same pair path again will only download newer archives.
    If data becomes corrupted, pass `reset=true` to force a complete redownload.

!!! tip "Performance Optimization"
    - **Monthly Archives**: Use for historical [backtesting](../guides/execution-modes.md#simulationmode) (faster download, larger chunks)
    - **Daily Archives**: Use for recent data or frequent updates
    - **Parallel Downloads**: Consider for multiple symbols, but respect [exchange](../exchanges.md) rate limits

## Real-Time Data Fetching

The Fetch module downloads data directly from exchanges using [CCXT](../exchanges.md#ccxt-integration), making it ideal for:

- Getting the most recent market data
- Filling gaps in historical data
- Real-time data updates for [live trading](../guides/execution-modes.md#live-mode)

### Basic Fetch Usage


### Advanced Fetch Examples


### Multi-Exchange Data Collection


### Rate Limit Management


### Data Validation and Quality Checks


!!! warning "Rate Limit Considerations"
    Direct [exchange](../exchanges.md) fetching is heavily rate-limited, especially for smaller [timeframes](../guides/data-management.md#timeframes).
    Use archives for bulk historical data collection.

!!! tip "Fetch Best Practices"
    - **Recent Updates**: Use fetch for recent data updates and gap filling
    - **Rate Limiting**: Implement delays between requests to respect exchange limits
    - **Data Validation**: Always validate fetched data before using in [strategies](../guides/strategy-development.md)
    - **Raw Data**: Use `fetch_candles` for unchecked data when you need raw exchange responses## L
ive Data Streaming

The Watchers module enables real-time data tracking from exchanges and other sources, storing data locally for:

- Live trading operations
- Real-time data analysis
- Continuous market monitoring

### [OHLCV](../guides/data-management.md#ohlcv-data) Ticker Watcher

The ticker watcher monitors multiple pairs simultaneously using exchange ticker endpoints:


```julia
# Activate Planar project
import Pkg
Pkg.activate("Planar")

try
    using Planar
    @environment!
    
    # Example watcher output (this would be the result of displaying a watcher)
    println("Example watcher display:")
    println("17-element Watchers.Watcher20{Dict{String, NamedTup...Nothing, Float64}, Vararg{Float64, 7}}}}")
    println("Name: ccxt_ohlcv_ticker")
    println("Intervals: 5 seconds(TO), 5 seconds(FE), 6 minutes(FL)")
    println("Fetched: 2023-03-07T12:06:18.690 busy: true")
    println("Flushed: 2023-03-07T12:04:31.472")
    println("Active: true")
    println("Attempts: 0")
    
    # Note: In real usage, 'w' would be an actual watcher instance
    # w = create_watcher(...)  # This would create the actual watcher
    
catch e
    @warn "Planar not available: $e"
end
```

As a convention, the `view` property of a watcher shows the processed data:


### Single-Pair OHLCV Watcher

There is another OHLCV watcher based on trades, that tracks only one pair at a time with higher precision:


### Advanced Watcher Configuration


### Watcher Management


### Orderbook Watcher


### Custom Data Processing


### Error Handling and Resilience


### Data Persistence and Storage


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


## Generic Data Storage

If you want to save other kinds of data, there are the [`Planar.Data.save_data`](@ref) and [`Planar.Data.load_data`](@ref) functions. Unlike the ohlcv functions, these functions don't check for contiguity, so it is possible to store sparse data. The data, however, still requires a timestamp column, because data when saved can either be prepend or appended, therefore an index must still be available to maintain order.


### Serialized Data Storage

While OHLCV data requires a concrete type for storage (default `Float64`) generic data can either be saved with a shared type, or instead serialized. To serialize the data while saving pass the `serialize=true` argument to `save_data`, while to load serialized data pass `serialized=true` to `load_data`.


!!! warning "Data Contiguity"
    OHLCV save/load functions validate timestamp contiguity by default. Use `check=:none` to disable validation for irregular data.

!!! tip "Performance Optimization"
    - Use progressive loading (`raw=true`) for large datasets to avoid memory issues
    - Process data in chunks when dealing with very large time series
    - Consider serialization for complex data structures that don't fit standard numeric types

## Data Access Patterns

The Data module implements dataframe indexing by dates such that you can conveniently access rows by:


### Advanced Indexing Examples


### Timeframe Management

With ohlcv data, we can access the timeframe of the series directly from the dataframe by calling `timeframe!(df)`. This will either return the previously set timeframe or infer it from the `timestamp` column. You can set the timeframe by calling e.g. `timeframe!(df, tf"1m")` or `timeframe!!` to overwrite it.


### Efficient Data Slicing


### Progressive Data Loading

When loading data from storage, you can directly use the `ZArray` by passing `raw=true` to `load_ohlcv` or `as_z=true` or `with_z=true` to `load_data`. By managing the array directly you can avoid materializing the entire dataset, which is required when dealing with large amounts of data.


### Data Aggregation and Resampling

```julia
# Activate Planar project
import Pkg
Pkg.activate("Planar")

try
    using Planar
    using DataFrames
    @environment!
    
    # Aggregate data to different timeframes
    function resample_ohlcv(data, target_timeframe)
        # Group by target timeframe periods
        data.period = floor.(data.timestamp, target_timeframe)
        
        aggregated = combine(groupby(data, :period)) do group
            (
                timestamp = first(group.timestamp),
                open = first(group.open),
                high = maximum(group.high),
                low = minimum(group.low),
                close = last(group.close),
                volume = sum(group.volume)
            )
        end
        
        select!(aggregated, Not(:period))
        return aggregated
    end
    
    println("Data resampling function defined")
    
catch e
    @warn "Planar or DataFrames not available: $e"
end

# Example: Convert 1m data to 5m
minute_data = Data.load_ohlcv(Data.zi[], "binance", "BTC/USDT", "1m")
five_min_data = resample_ohlcv(minute_data, Minute(5))
```

Data is returned as a `DataFrame` with `open,high,low,close,volume,timestamp` columns.
Since these save/load functions require a timestamp column, they check that the provided index is contiguous, it should not have missing timestamps, according to the subject timeframe. It is possible to disable those checks by passing `check=:none`.

This comprehensive [data management](../guides/data-management.md) guide provides everything you need to efficiently collect, store, and access market data in Planar. Start with the basic collection methods and gradually explore more advanced features as your data requirements grow.