---
title: "Data Management Guide"
description: "Comprehensive guide to data handling and management in Planar"
category: "guides"
difficulty: "intermediate"
topics: [data-management, ohlcv, timeframes]
last_updated: "2025-10-04"
---

# Data Management Guide

<!--
Keywords: [OHLCV data](../guides/data-management.md#ohlcv-data), Zarr storage, LMDB, data fetching, scrapers, watchers, historical data, real-time data, [market data](../guides/data-management.md)
Description: Comprehensive [data management](../guides/data-management.md) system for [OHLCV](../guides/data-management.md#ohlcv-data) and time-series [market data](../guides/data-management.md) using Zarr storage, LMDB backend, and multiple data collection methods.
-->

This comprehensive guide covers Planar's [data management](../guides/data-management.md) system for [OHLCV](../guides/data-management.md#ohlcv-data) (Open, High, Low, Close, Volume) data and other time-series [market data](../guides/data-management.md). Learn how to efficiently collect, store, and access market data using multiple collection methods and storage backends.

## Quick Navigation

- **[Storage Architecture](#storage-architecture)** - Understanding Zarr and LMDB backends
- **[Data Collection Methods](#data-collection-methods)** - Overview of collection approaches
- **[Historical Data](#historical-data-collection)** - Using Scrapers for bulk data collection
- **[Real-Time Data](#real-time-data-fetching)** - Fetching live data from [exchanges](../exchanges.md)
- **[Live Streaming](#live-data-streaming)** - Continuous data monitoring with Watchers
- **[Custom Data Sources](#custom-data-sources)** - Integrating your own data
- **[Data Access Patterns](#data-access-patterns)** - Efficient data querying and indexing
- **[Performance Optimization](#performance-[optimization](../optimization.md))** - Caching and [optimization](../optimization.md) [strategies](../guides/strategy-development.md)
- **[Troubleshooting](#[troubleshooting](../troubleshooting/))** - Common issues and solutions

## Prerequisites

- Basic understanding of [OHLCV data concepts](../getting-started/index.md)
- Familiarity with [Exchange setup](../[exchanges](../exchanges.md).md)

## Related Topics

- **[Strategy Development]([strategy](../guides/strategy-development.md)-development.md)** - Using data in trading [strategies](../guides/strategy-development.md)
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

- **Use Scrapers** for initial historical data collection and [backtesting](../guides/execution-modes.md#[simulation](../guides/execution-modes.md#simulation-mode)-mode) datasets
- **Use Fetch** for recent data updates and filling gaps in historical data
- **Use Watchers** for [live trading](../guides/execution-modes.md#live-mode) and real-time analysis

**⚠️ Data collection issues?** See [Performance Issues: Data-Related](../troubleshooting/performance-issues.md#data-related-performance-issues) for slow loading and database problems, or [Exchange Issues](../troubleshooting/exchange-issues.md) for connectivity problems.
##
 Historical Data Collection

The Scrapers module provides access to historical data archives from major exchanges, offering the most efficient method for obtaining large amounts of historical data.

**Supported Exchanges**: Binance and Bybit archives

### Basic Scraper Usage

```julia
using Scrapers: Scrapers as scr, BinanceData as bn

# Download [OHLCV data](../guides/data-management.md#ohlcv-data) for ETH
bn.binancedownload("eth", market=:data, freq=:monthly, kind=:klines)

# Load downloaded data into the storage system
bn.binanceload("eth", market=:data, freq=:monthly, kind=:klines)

# Note: Default market parameter is :um (USD-M futures)
```

### Market Types and Frequencies

```julia
using Scrapers: Scrapers as scr, BinanceData as bn

# Different market types
bn.binancedownload("btc", market=:spot, freq=:monthly, kind=:klines)    # Spot market
bn.binancedownload("btc", market=:um, freq=:monthly, kind=:klines)      # USD-M futures
bn.binancedownload("btc", market=:cm, freq=:monthly, kind=:klines)      # Coin-M futures

# Different frequencies
bn.binancedownload("eth", market=:um, freq=:daily, kind=:klines)        # Daily archives
bn.binancedownload("eth", market=:um, freq=:monthly, kind=:klines)      # Monthly archives

# Different data types
bn.binancedownload("btc", market=:um, freq=:monthly, kind=:trades)      # Trade data
bn.binancedownload("btc", market=:um, freq=:monthly, kind=:aggTrades)   # Aggregated trades
```

### Advanced Scraper Examples

```julia
using Dates

# Try to load Scrapers with error handling
try
    using Scrapers: Scrapers as scr, BinanceData as bn
    
    # Download multiple symbols at once
    symbols = ["btc", "eth", "ada", "dot"]
    for symbol in symbols
        bn.binancedownload(symbol, market=:um, freq=:monthly, kind=:klines)
        bn.binanceload(symbol, market=:um, freq=:monthly, kind=:klines)
    end
    @info "Scrapers functionality available"
catch e
    @warn "Scrapers module not available: $e"
    @info "This is normal in some testing environments"
end

# Show all symbols that can be downloaded
available_symbols = bn.binancesyms(market=:data)
println("Available symbols: $(length(available_symbols))")

# Filter by quote currency (default is "usdt")
usdc_pairs = scr.selectsyms(["eth", "btc"], bn.binancesyms(market=:data), quote_currency="usdc")
println("USDC pairs: $usdc_pairs")

# Download specific date ranges
bn.binancedownload("btc", market=:um, freq=:daily, kind=:klines, 
                   from=Date(2023, 1, 1), to=Date(2023, 12, 31))
```

### Error Handling and Data Validation

```julia
# Handle download errors gracefully
function safe_download(symbol, market=:um)
    try
        bn.binancedownload(symbol, market=market, freq=:monthly, kind=:klines)
        bn.binanceload(symbol, market=market, freq=:monthly, kind=:klines)
        @info "Successfully downloaded $symbol"
        return true
    catch e
        @warn "Failed to download $symbol: $e"
        return false
    end
end

# Batch download with error handling
symbols = ["btc", "eth", "ada", "invalid_symbol"]
successful = filter(safe_download, symbols)
println("Successfully downloaded: $successful")
```

### Bybit Scrapers

```julia
using Scrapers: BybitData as bb

# Download Bybit data
bb.bybitdownload("btc", market=:linear, freq=:monthly, kind=:klines)
bb.bybitload("btc", market=:linear, freq=:monthly, kind=:klines)

# Available Bybit markets
bb.bybitsyms(market=:linear)  # Linear perpetuals
bb.bybitsyms(market=:spot)    # Spot trading
```

!!! warning "Download Caching"
    Downloads are cached - requesting the same pair path again will only download newer archives.
    If data becomes corrupted, pass `reset=true` to force a complete redownload.

!!! tip "Performance Optimization"
    - **Monthly Archives**: Use for historical [backtesting](../guides/execution-modes.md#[simulation](../guides/execution-modes.md#simulation-mode)-mode) (faster download, larger chunks)
    - **Daily Archives**: Use for recent data or frequent updates
    - **Parallel Downloads**: Consider for multiple symbols, but respect [exchange](../exchanges.md) rate limits

## Real-Time Data Fetching

The Fetch module downloads data directly from exchanges using [CCXT](../exchanges.md#ccxt-integration), making it ideal for:

- Getting the most recent market data
- Filling gaps in historical data
- Real-time data updates for [live trading](../guides/execution-modes.md#live-mode)

### Basic Fetch Usage

```julia
using TimeTicks
using Exchanges
using Fetch: Fetch as fe

exc = getexchange!(:kucoin)
timeframe = tf"1m"
pairs = ("BTC/USDT", "ETH/USDT")

# Will fetch the last 1000 candles, `to` can also be passed to download a specific range
fe.fetch_ohlcv(exc, timeframe, pairs; from=-1000) # or `fetch_candles` for unchecked data
```

### Advanced Fetch Examples

```julia
using TimeTicks
using Exchanges
using Fetch: Fetch as fe
using Dates

# Initialize exchange
exc = getexchange!(:binance)

# Fetch specific date ranges
start_date = DateTime(2024, 1, 1)
end_date = DateTime(2024, 1, 31)
pairs = ["BTC/USDT", "ETH/USDT", "ADA/USDT"]

# Fetch with explicit date range
data = fe.fetch_ohlcv(exc, tf"1h", pairs; from=start_date, to=end_date)

# Fetch recent data (last N candles)
recent_data = fe.fetch_ohlcv(exc, tf"5m", "BTC/USDT"; from=-100)

# Fetch and automatically save to storage
fe.fetch_ohlcv(exc, tf"1d", pairs; from=-365, save=true)
```

### Multi-Exchange Data Collection

```julia
using TimeTicks
using Exchanges
using Fetch: Fetch as fe

# Collect data from multiple exchanges
exchanges = [:binance, :kucoin, :bybit]
pair = "BTC/USDT"
timeframe = tf"1h"

for exchange_name in exchanges
    try
        exc = getexchange!(exchange_name)
        data = fe.fetch_ohlcv(exc, timeframe, pair; from=-100, save=true)
        @info "Fetched data from $exchange_name: $(nrow(data)) candles"
    catch e
        @warn "Failed to fetch from $exchange_name: $e"
    end
end
```

### Rate Limit Management

```julia
using TimeTicks
using Exchanges
using Fetch: Fetch as fe

# Fetch with rate limit awareness
function fetch_with_delays(exc, timeframe, pairs; delay_ms=1000)
    results = Dict()
    for pair in pairs
        try
            data = fe.fetch_ohlcv(exc, timeframe, pair; from=-1000)
            results[pair] = data
            @info "Fetched $pair: $(nrow(data)) candles"
            
            # Respect rate limits
            sleep(delay_ms / 1000)
        catch e
            @warn "Failed to fetch $pair: $e"
            results[pair] = nothing
        end
    end
    return results
end

# Usage
exc = getexchange!(:binance)
pairs = ["BTC/USDT", "ETH/USDT", "ADA/USDT", "DOT/USDT"]
data = fetch_with_delays(exc, tf"1h", pairs; delay_ms=500)
```

### Data Validation and Quality Checks

```julia
using TimeTicks
using Exchanges
using Fetch: Fetch as fe

# Fetch with validation
function fetch_and_validate(exc, timeframe, pair; from=-1000)
    data = fe.fetch_ohlcv(exc, timeframe, pair; from=from)
    
    # Basic validation
    if nrow(data) == 0
        @warn "No data received for $pair"
        return nothing
    end
    
    # Check for missing timestamps
    expected_count = abs(from)
    if nrow(data) < expected_count * 0.9  # Allow 10% tolerance
        @warn "Incomplete data for $pair: got $(nrow(data)), expected ~$expected_count"
    end
    
    # Check for data quality
    if any(data.high .< data.low)
        @warn "Data quality issue: high < low in some candles"
    end
    
    return data
end

# Usage
exc = getexchange!(:kucoin)
validated_data = fetch_and_validate(exc, tf"1m", "BTC/USDT"; from=-500)
```

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
using Exchanges
using Planar.Watchers: Watchers as wc, WatchersImpls as wi

exc = getexchange!(:kucoin)
w = wi.ccxt_ohlcv_tickers_watcher(exc;)
wc.start!(w)
```

```julia
>>> w
17-element Watchers.Watcher20{Dict{String, NamedTup...Nothing, Float64}, Vararg{Float64, 7}}}}}
Name: ccxt_ohlcv_ticker
Intervals: 5 seconds(TO), 5 seconds(FE), 6 minutes(FL)
Fetched: 2023-03-07T12:06:18.690 busy: true
Flushed: 2023-03-07T12:04:31.472
Active: true
Attemps: 0
```

As a convention, the `view` property of a watcher shows the processed data:

```julia
>>> w.view
Dict{String, DataFrames.DataFrame} with 220 entries:
  "HOOK/USDT"          => 5×6 DataFrame…
  "ETH/USD:USDC"       => 5×6 DataFrame…
  "PEOPLE/USDT:USDT"   => 5×6 DataFrame…
```

### Single-Pair OHLCV Watcher

There is another OHLCV watcher based on trades, that tracks only one pair at a time with higher precision:

```julia
w = wi.ccxt_ohlcv_watcher(exc, "BTC/USDT:USDT"; timeframe=tf"1m")
w.view
956×6 DataFrame
 Row │ timestamp            open     high     low      close    volume  
     │ DateTime             Float64  Float64  Float64  Float64  Float64 
─────┼──────────────────────────────────────────────────────────────────
...
```

### Advanced Watcher Configuration

```julia
using Exchanges
using Planar.Watchers: Watchers as wc, WatchersImpls as wi

# Configure watcher with custom parameters
exc = getexchange!(:binance)

# Multi-pair watcher with custom intervals
w = wi.ccxt_ohlcv_tickers_watcher(
    exc;
    timeout_interval=10,      # Fetch timeout in seconds
    fetch_interval=5,         # How often to fetch data
    flush_interval=300        # How often to flush to storage (5 minutes)
)

# Start the watcher
wc.start!(w)

# Monitor watcher status
println("Watcher active: $(wc.isrunning(w))")
println("Last fetch: $(w.last_fetch)")
println("Data points: $(length(w.view))")
```

### Watcher Management

```julia
using Exchanges
using Planar.Watchers: Watchers as wc, WatchersImpls as wi

# Start multiple watchers for different exchanges
watchers = []

for exchange_name in [:binance, :kucoin, :bybit]
    try
        exc = getexchange!(exchange_name)
        w = wi.ccxt_ohlcv_tickers_watcher(exc)
        wc.start!(w)
        push!(watchers, w)
        @info "Started watcher for $exchange_name"
    catch e
        @warn "Failed to start watcher for $exchange_name: $e"
    end
end

# Monitor all watchers
function monitor_watchers(watchers)
    for (i, w) in enumerate(watchers)
        status = wc.isrunning(w) ? "RUNNING" : "STOPPED"
        pairs_count = length(w.view)
        @info "Watcher $i: $status, tracking $pairs_count pairs"
    end
end

# Stop all watchers when done
function cleanup_watchers(watchers)
    for w in watchers
        try
            wc.stop!(w)
            @info "Stopped watcher"
        catch e
            @warn "Error stopping watcher: $e"
        end
    end
end
```

### Orderbook Watcher

```julia
# Monitor orderbook data for a specific pair
orderbook_watcher = wi.ccxt_orderbook_watcher(exc, "BTC/USDT")
wc.start!(orderbook_watcher)

# Access orderbook data
orderbook_data = orderbook_watcher.view
println("Bids: $(length(orderbook_data.bids))")
println("Asks: $(length(orderbook_data.asks))")
```

### Custom Data Processing

```julia
using DataFrames
using Statistics

# Create a watcher with custom data processing
function custom_data_processor(raw_data)
    # Custom processing logic
    processed = DataFrame(raw_data)
    
    # Add custom indicators or transformations (example implementations)
    # Note: Replace with your preferred technical analysis library
    function rolling_mean(data, window)
        return [i <= window ? mean(data[1:i]) : mean(data[i-window+1:i]) for i in 1:length(data)]
    end
    
    function rolling_std(data, window)
        return [i <= window ? std(data[1:i]) : std(data[i-window+1:i]) for i in 1:length(data)]
    end
    
    processed.sma_20 = rolling_mean(processed.close, 20)
    processed.volatility = rolling_std(processed.close, 20)
    
    return processed
end

# Apply custom processing to watcher data
w = wi.ccxt_ohlcv_watcher(exc, "ETH/USDT"; processor=custom_data_processor)
wc.start!(w)
```

### Error Handling and Resilience

```julia
using TimeTicks
using Exchanges
using Planar.Watchers: Watchers as wc, WatchersImpls as wi

# Robust watcher with error handling
function create_resilient_watcher(exchange_name, pair)
    max_retries = 3
    retry_count = 0
    
    while retry_count < max_retries
        try
            exc = getexchange!(exchange_name)
            w = wi.ccxt_ohlcv_watcher(exc, pair; timeframe=tf"1m")
            
            # Set up error callbacks
            w.on_error = (error) -> begin
                @warn "Watcher error: $error"
                # Could implement reconnection logic here
            end
            
            wc.start!(w)
            @info "Successfully started watcher for $pair on $exchange_name"
            return w
            
        catch e
            retry_count += 1
            @warn "Attempt $retry_count failed: $e"
            if retry_count < max_retries
                sleep(2^retry_count)  # Exponential backoff
            end
        end
    end
    
    error("Failed to create watcher after $max_retries attempts")
end

# Usage
resilient_watcher = create_resilient_watcher(:binance, "BTC/USDT")
```

### Data Persistence and Storage

```julia
using TimeTicks
using Exchanges

# Try to load watcher modules with error handling
try
    using Planar.Watchers: Watchers as wc, WatchersImpls as wi
    using Planar.Data: Data
    
    # Setup exchange first
    exc = getexchange!(:binance)
    
    # Configure automatic data persistence
    w = wi.ccxt_ohlcv_watcher(exc, "BTC/USDT"; 
                              timeframe=tf"1m",
                              auto_save=true,
                              save_interval=3600)  # Save every hour
    @info "Watcher configured successfully"
catch e
    @warn "Watcher modules not available: $e"
    @info "This is normal in some testing environments"
end

# Manual data saving
function save_watcher_data(w, source_name="live_data")
    data = w.view
    if !isempty(data)
        # Save to the data system
        Data.save_ohlcv(Data.zi[], source_name, w.pair, w.timeframe, data)
        @info "Saved $(nrow(data)) candles to storage"
    end
end

# Periodic saving
@async while wc.isrunning(w)
    sleep(300)  # Every 5 minutes
    save_watcher_data(w)
end
```

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

```julia
using Planar
@environment!
@assert da === Data

# Example custom data loader function
function my_custom_data_loader()
    # This is a placeholder - replace with your actual data loading logic
    using DataFrames, Dates
    return DataFrame(
        timestamp = [DateTime(2024, 1, 1) + Hour(i) for i in 1:10],
        open = rand(10) * 50000 .+ 45000,
        high = rand(10) * 50000 .+ 45000,
        low = rand(10) * 50000 .+ 45000,
        close = rand(10) * 50000 .+ 45000,
        volume = rand(10) * 1000
    )
end

source_name = "mysource"
pair = "BTC123/USD"
timeframe = "1m"
zi = Data.zi # the global zarr instance, or use your own
mydata = my_custom_data_loader()
da.save_ohlcv(zi, source_name, pair, timeframe, mydata)
```

To load the data back:

```julia
da.load_ohlcv(zi, source_name, pair, timeframe)
```

### Advanced Custom Data Examples

```julia
using DataFrames
using Dates
using CSV

# Example: Custom data from CSV files
function load_csv_ohlcv(filepath)
    df = CSV.read(filepath, DataFrame)
    
    # Ensure proper column names and types
    rename!(df, Dict(
        "Date" => "timestamp",
        "Open" => "open",
        "High" => "high", 
        "Low" => "low",
        "Close" => "close",
        "Volume" => "volume"
    ))
    
    # Convert timestamp to DateTime
    df.timestamp = DateTime.(df.timestamp)
    
    # Ensure proper column order
    select!(df, [:timestamp, :open, :high, :low, :close, :volume])
    
    return df
end

# Save custom CSV data
csv_data = load_csv_ohlcv("my_data.csv")
Data.save_ohlcv(Data.zi[], "csv_source", "CUSTOM/PAIR", "1h", csv_data)
```

### Custom Data Validation

```julia
using Planar.Data: Data

# Example: Custom data with validation
function save_validated_ohlcv(source, pair, timeframe, data)
    # Validate data structure
    required_cols = [:timestamp, :open, :high, :low, :close, :volume]
    if !all(col in names(data) for col in required_cols)
        error("Missing required columns. Need: $required_cols")
    end
    
    # Validate data quality
    if any(data.high .< data.low)
        @warn "Data quality issue: some high prices are lower than low prices"
    end
    
    if any(data.volume .< 0)
        @warn "Data quality issue: negative volume detected"
    end
    
    # Check for duplicates
    if length(unique(data.timestamp)) != nrow(data)
        @warn "Duplicate timestamps detected, removing duplicates"
        data = unique(data, :timestamp)
    end
    
    # Sort by timestamp
    sort!(data, :timestamp)
    
    # Save with validation
    try
        Data.save_ohlcv(Data.zi[], source, pair, timeframe, data)
        @info "Successfully saved $(nrow(data)) candles for $pair"
    catch e
        @error "Failed to save data: $e"
        rethrow(e)
    end
end
```

### Working with Large Custom Datasets

```julia
using Planar.Data: Data

# Example: Processing large datasets in chunks
function save_large_dataset(source, pair, timeframe, large_data; chunk_size=10000)
    total_rows = nrow(large_data)
    chunks_saved = 0
    
    for start_idx in 1:chunk_size:total_rows
        end_idx = min(start_idx + chunk_size - 1, total_rows)
        chunk = large_data[start_idx:end_idx, :]
        
        try
            # For first chunk, reset any existing data
            reset_flag = (start_idx == 1)
            Data.save_ohlcv(Data.zi[], source, pair, timeframe, chunk; 
                           reset=reset_flag)
            chunks_saved += 1
            @info "Saved chunk $chunks_saved: rows $start_idx-$end_idx"
        catch e
            @error "Failed to save chunk $start_idx-$end_idx: $e"
            break
        end
    end
    
    @info "Completed saving $chunks_saved chunks for $pair"
end
```### Gener
ic Data Storage

If you want to save other kinds of data, there are the [`Planar.Data.save_data`](@ref) and [`Planar.Data.load_data`](@ref) functions. Unlike the ohlcv functions, these functions don't check for contiguity, so it is possible to store sparse data. The data, however, still requires a timestamp column, because data when saved can either be prepend or appended, therefore an index must still be available to maintain order.

```julia
using DataFrames
using Planar.Data: Data

# Example indicator calculation functions (replace with your preferred library)
function calculate_rsi(prices)
    return rand(length(prices)) * 100  # Placeholder RSI calculation
end

function calculate_macd(prices)
    return rand(length(prices)) * 2 .- 1  # Placeholder MACD calculation
end

function calculate_bollinger_upper(prices)
    return prices .* 1.02  # Placeholder Bollinger upper band
end

function calculate_bollinger_lower(prices)
    return prices .* 0.98  # Placeholder Bollinger lower band
end

# Example: Saving custom indicator data
function save_custom_indicators(source, pair, timeframe, data)
    # Custom data with timestamp and various indicators
    indicator_data = DataFrame(
        timestamp = data.timestamp,
        rsi = calculate_rsi(data.close),
        macd = calculate_macd(data.close),
        bollinger_upper = calculate_bollinger_upper(data.close),
        bollinger_lower = calculate_bollinger_lower(data.close)
    )
    
    # Save as generic data (not OHLCV)
    Data.save_data(Data.zi[], source, pair, "indicators_$timeframe", indicator_data)
end

# Load custom indicators
indicators = Data.load_data(Data.zi[], "my_source", "BTC/USDT", "indicators_1h")
```

### Serialized Data Storage

While OHLCV data requires a concrete type for storage (default `Float64`) generic data can either be saved with a shared type, or instead serialized. To serialize the data while saving pass the `serialize=true` argument to `save_data`, while to load serialized data pass `serialized=true` to `load_data`.

```julia
using DataFrames
using Dates
using Planar.Data: Data

# Example: Storing complex data structures
complex_data = DataFrame(
    timestamp = [DateTime(2024, 1, 1), DateTime(2024, 1, 2)],
    metadata = [Dict("exchange" => "binance", "fees" => 0.1), 
                Dict("exchange" => "kucoin", "fees" => 0.1)],
    nested_arrays = [[1, 2, 3], [4, 5, 6]]
)

# Save with serialization
Data.save_data(Data.zi[], "complex_source", "BTC/USDT", "metadata", 
               complex_data; serialize=true)

# Load serialized data
loaded_complex = Data.load_data(Data.zi[], "complex_source", "BTC/USDT", 
                                "metadata"; serialized=true)
```

!!! warning "Data Contiguity"
    OHLCV save/load functions validate timestamp contiguity by default. Use `check=:none` to disable validation for irregular data.

!!! tip "Performance Optimization"
    - Use progressive loading (`raw=true`) for large datasets to avoid memory issues
    - Process data in chunks when dealing with very large time series
    - Consider serialization for complex data structures that don't fit standard numeric types

## Data Access Patterns

The Data module implements dataframe indexing by dates such that you can conveniently access rows by:

```julia
df[dt"2020-01-01", :high] # get the high of the date 2020-01-01
df[dtr"2020-..2021-", [:high, :low]] # get all high and low for the year 2020
after(df, dt"2020-01-01") # get all candles after the date 2020-01-01
before(df, dt"2020-01-01") # get all candles up until the date 2020-01-01
```

### Advanced Indexing Examples

```julia
using TimeTicks
using Dates

# Load sample data
data = Data.load_ohlcv(Data.zi[], "binance", "BTC/USDT", "1h")

# Date range selections
jan_2024 = data[dtr"2024-01-01..2024-01-31", :]
q1_2024 = data[dtr"2024-01-01..2024-03-31", :]

# Specific time periods
morning_hours = data[hour.(data.timestamp) .∈ Ref(8:12), :]
weekdays_only = data[dayofweek.(data.timestamp) .≤ 5, :]

# Price-based filtering
high_volume = data[data.volume .> quantile(data.volume, 0.95), :]
price_breakouts = data[data.high .> 1.02 .* data.open, :]

# Combined conditions
volatile_periods = data[
    (data.high .- data.low) ./ data.open .> 0.05 .&& 
    data.volume .> median(data.volume), 
    :
]
```

### Timeframe Management

With ohlcv data, we can access the timeframe of the series directly from the dataframe by calling `timeframe!(df)`. This will either return the previously set timeframe or infer it from the `timestamp` column. You can set the timeframe by calling e.g. `timeframe!(df, tf"1m")` or `timeframe!!` to overwrite it.

```julia
# Get current timeframe
current_tf = timeframe!(data)
println("Current timeframe: $current_tf")

# Set timeframe explicitly
timeframe!(data, tf"1h")

# Force overwrite timeframe
timeframe!!(data, tf"1h")

# Validate timeframe consistency
function validate_timeframe(df, expected_tf)
    inferred_tf = timeframe!(df)
    if inferred_tf != expected_tf
        @warn "Timeframe mismatch: expected $expected_tf, got $inferred_tf"
        return false
    end
    return true
end
```

### Efficient Data Slicing

```julia
# Efficient slicing for large datasets
function get_recent_data(source, pair, timeframe, days_back=30)
    # Calculate start date
    end_date = now()
    start_date = end_date - Day(days_back)
    
    # Load only the required date range
    full_data = Data.load_ohlcv(Data.zi[], source, pair, timeframe)
    recent_data = after(full_data, start_date)
    
    return recent_data
end

# Memory-efficient processing of large datasets
function process_data_by_month(source, pair, timeframe, year)
    results = Dict()
    
    for month in 1:12
        start_date = DateTime(year, month, 1)
        end_date = DateTime(year, month, daysinmonth(year, month))
        
        # Load data for specific month
        full_data = Data.load_ohlcv(Data.zi[], source, pair, timeframe)
        month_data = full_data[dtr"$(start_date)..$(end_date)", :]
        
        if !isempty(month_data)
            # Process month data
            monthly_stats = (
                avg_price = mean(month_data.close),
                total_volume = sum(month_data.volume),
                volatility = std(month_data.close),
                candle_count = nrow(month_data)
            )
            results[month] = monthly_stats
        end
    end
    
    return results
end
```

### Progressive Data Loading

When loading data from storage, you can directly use the `ZArray` by passing `raw=true` to `load_ohlcv` or `as_z=true` or `with_z=true` to `load_data`. By managing the array directly you can avoid materializing the entire dataset, which is required when dealing with large amounts of data.

```julia
# Example: Progressive loading for large datasets
function analyze_large_dataset_progressively(source, pair, timeframe)
    # Load as ZArray for progressive access
    z_array = Data.load_ohlcv(Data.zi[], source, pair, timeframe; raw=true)
    
    # Process data in chunks
    chunk_size = 1000
    total_size = size(z_array, 1)
    
    results = []
    for start_idx in 1:chunk_size:total_size
        end_idx = min(start_idx + chunk_size - 1, total_size)
        
        # Load only the chunk we need
        chunk_data = z_array[start_idx:end_idx, :]
        chunk_df = DataFrame(chunk_data, Data.OHLCV_COLUMNS)
        
        # Process chunk (e.g., calculate statistics)
        chunk_stats = (
            mean_close = mean(chunk_df.close),
            max_volume = maximum(chunk_df.volume),
            date_range = (minimum(chunk_df.timestamp), maximum(chunk_df.timestamp))
        )
        
        push!(results, chunk_stats)
        @info "Processed chunk $start_idx:$end_idx"
    end
    
    return results
end
```

### Data Aggregation and Resampling

```julia
# Aggregate data to different [timeframes](../guides/data-management.md#timeframes)
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

# Example: Convert 1m data to 5m
minute_data = Data.load_ohlcv(Data.zi[], "binance", "BTC/USDT", "1m")
five_min_data = resample_ohlcv(minute_data, Minute(5))
```

Data is returned as a `DataFrame` with `open,high,low,close,volume,timestamp` columns.
Since these save/load functions require a timestamp column, they check that the provided index is contiguous, it should not have missing timestamps, according to the subject timeframe. It is possible to disable those checks by passing `check=:none`.

This comprehensive [data management](../guides/data-management.md) guide provides everything you need to efficiently collect, store, and access market data in Planar. Start with the basic collection methods and gradually explore more advanced features as your data requirements grow.