---
category: "strategy-development"
difficulty: "advanced"
topics: [execution-modes, margin-trading, exchanges, data-management, optimization, strategy-development, troubleshooting, visualization, configuration]
last_updated: "2025-10-04"---
---

# Data Management

<!--
Keywords: [OHLCV data](../guides/data-management.md#ohlcv-data), Zarr storage, LMDB, data fetching, scrapers, watchers, historical data, real-time data, [market data](../guides/data-management.md)
Description: Comprehensive [data management](../guides/data-management.md) system for [OHLCV](../guides/data-management.md#ohlcv-data) and time-series [market data](../guides/data-management.md) using Zarr storage, LMDB backend, and multiple data collection methods.
-->

The Data module provides comprehensive storage and management of [OHLCV](../guides/data-management.md#ohlcv-data) (Open, High, Low, Close, Volume) data and other time-series [market data](../guides/data-management.md).

## Quick Navigation

- **[Storage Architecture](#storage-architecture)** - Understanding Zarr and LMDB backends
- **[Historical Data](#historical-data-with-scrapers)** - Using Scrapers for bulk data collection
- **[Real-Time Data](#real-time-data-with-fetch)** - Fetching live data from [exchanges](../exchanges.md)
- **[Live Streaming](#live-data-streaming-with-watchers)** - Continuous data monitoring

## Prerequisites

- Basic understanding of [OHLCV data concepts](getting-started/index.md)
- Familiarity with [Exchange setup]([exchanges](../exchanges.md).md)

## Related Topics

- **[Strategy Development]([strategy](../guides/strategy-development.md).md)** - Using data in trading [strategies](../guides/strategy-development.md)
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

[OHLCV data](../guides/data-management.md#ohlcv-data) is organized hierarchically using [`Planar.Data.key_path`](@ref):

## Data Architecture Overview

The Data module provides a comprehensive [data management](../guides/data-management.md) system with the following key components:

- **Storage Backend**: Zarr arrays with LMDB as the default store
- **Data Organization**: Hierarchical structure by [exchange](../[exchanges](../exchanges.md).md)/source, pair, and [timeframe](../guides/data-management.md#timeframes)
- **Data Types**: [OHLCV data](../guides/data-management.md#ohlcv-data), generic time-series data, and cached metadata
- **Access Patterns**: Progressive loading for large datasets, contiguous time-series validation
- **Performance**: Chunked storage, compression, and optimized indexing

### Storage Hierarchy

Data is organized in a hierarchical structure:
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

## Data Collection Methods

Planar provides multiple methods for collecting market data, each optimized for different use cases:

## Historical Data with Scrapers

The Scrapers module provides access to historical data archives from major exchanges, offering the most efficient method for obtaining large amounts of historical data.

**Supported Exchanges**: Binance and Bybit archives

### Basic Scraper Usage

```julia
using Scrapers: Scrapers as scr, BinanceData as bn

# Download [OHLCV](../guides/data-management.md#ohlcv-data) data for ETH
bn.binancedownload("eth", market=:data, freq=:monthly, kind=:klines)

# Load downloaded data into the storage system
bn.binanceload("eth", market=:data, freq=:monthly, kind=:klines)

# Note: Default market parameter is :um (USD-M futures)
```

### Advanced Scraper Examples

```julia
# Download multiple symbols at once
symbols = ["btc", "eth", "ada", "dot"]
for symbol in symbols
    bn.binancedownload(symbol, market=:um, freq=:monthly, kind=:klines)
    bn.binanceload(symbol, market=:um, freq=:monthly, kind=:klines)
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

### Market Types and Frequencies

```julia
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

!!! warning "Download Caching"
    Downloads are cached - requesting the same pair path again will only download newer archives.
    If data becomes corrupted, pass `reset=true` to force a complete redownload.

!!! tip "Performance Optimization"
    - **Monthly Archives**: Use for historical [backtesting](../guides/execution-modes.md#[simulation](../guides/execution-modes.md#simulation-mode)-mode) (faster download, larger chunks)
    - **Daily Archives**: Use for recent data or frequent updates
    - **Parallel Downloads**: Consider for multiple symbols, but respect [exchange](../exchanges.md) rate limits 

## Real-Time Data with Fetch

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
[timeframe](../guides/data-management.md#timeframes) = tf"1m"
pairs = ("BTC/USDT", "ETH/USDT")

# Will fetch the last 1000 candles, `to` can also be passed to download a specific range
fe.fetch_ohlcv(exc, timeframe, pairs; from=-1000) # or `fetch_candles` for unchecked data
```

### Advanced Fetch Examples

```julia
using TimeTicks
using Exchanges
using Fetch: Fetch as fe

# Initialize [exchange](../exchanges.md)
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
    Direct exchange fetching is heavily rate-limited, especially for smaller [timeframes](../guides/data-management.md#timeframes).
    Use archives for bulk historical data collection.

!!! tip "Fetch Best Practices"
    - **Recent Updates**: Use fetch for recent data updates and gap filling
    - **Rate Limiting**: Implement delays between requests to respect exchange limits
    - **Data Validation**: Always validate fetched data before using in [strategies](../guides/strategy-development.md)
    - **Raw Data**: Use `fetch_candles` for unchecked data when you need raw exchange responses

## Live Data Streaming with Watchers

The Watchers module enables real-time data tracking from exchanges and other sources, storing data locally for:

- Live trading operations
- Real-time data analysis
- Continuous market monitoring

### OHLCV Ticker Watcher

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

As a convention, the `view` property of a watcher shows the processed data. In this case, the candles processed
by the `ohlcv_ticker_watcher` will be stored in a dict.

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
# Create a watcher with custom data processing
function custom_data_processor(raw_data)
    # Custom processing logic
    processed = DataFrame(raw_data)
    
    # Add custom indicators or transformations
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
# Configure automatic data persistence
w = wi.ccxt_ohlcv_watcher(exc, "BTC/USDT"; 
                          timeframe=tf"1m",
                          auto_save=true,
                          save_interval=3600)  # Save every hour

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

```julia
using Planar
@environment!
@assert da === Data

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
```

### Generic Data Storage

If you want to save other kinds of data, there are the [`Planar.Data.save_data`](@ref) and [`Planar.Data.load_data`](@ref) functions. Unlike the ohlcv functions, these functions don't check for contiguity, so it is possible to store sparse data. The data, however, still requires a timestamp column, because data when saved can either be prepend or appended, therefore an index must still be available to maintain order.

```julia
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

Data is returned as a `DataFrame` with `open,high,low,close,volume,timestamp` columns.
Since these save/load functions require a timestamp column, they check that the provided index is contiguous, it should not have missing timestamps, according to the subject timeframe. It is possible to disable those checks by passing `check=:none`.

!!! warning "Data Contiguity"
    OHLCV save/load functions validate timestamp contiguity by default. Use `check=:none` to disable validation for irregular data.

!!! tip "Performance Optimization"
    - Use progressive loading (`raw=true`) for large datasets to avoid memory issues
    - Process data in chunks when dealing with very large time series
    - Consider serialization for complex data structures that don't fit standard numeric types

## Data Indexing and Access Patterns

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

## Caching and Performance Optimization

`Data.Cache.save_cache` and `Data.Cache.load_cache` can be used to store generic metadata like JSON payloads. The data is saved in the Planar data directory which is either under the `XDG_CACHE_DIR`[^1] if set or under `$HOME/.cache` by default.

### Basic Caching Usage

```julia
using Data.Cache

# Save metadata to cache
metadata = Dict(
    "last_update" => now(),
    "data_source" => "binance",
    "pairs_count" => 150,
    "status" => "active"
)

Cache.save_cache("exchange_metadata", metadata)

# Load from cache
cached_metadata = Cache.load_cache("exchange_metadata")
```

### Advanced Caching Examples

```julia
# Cache expensive computations
function get_or_compute_indicators(pair, timeframe; force_refresh=false)
    cache_key = "indicators_$(pair)_$(timeframe)"
    
    if !force_refresh
        try
            cached_result = Cache.load_cache(cache_key)
            @info "Loaded indicators from cache for $pair"
            return cached_result
        catch
            @info "Cache miss, computing indicators for $pair"
        end
    end
    
    # Expensive computation
    data = Data.load_ohlcv(Data.zi[], "binance", pair, timeframe)
    indicators = compute_technical_indicators(data)
    
    # Cache the result
    Cache.save_cache(cache_key, indicators)
    return indicators
end

# Cache with expiration
function cached_with_expiry(key, compute_fn; ttl_hours=24)
    cache_key = "$(key)_with_timestamp"
    
    try
        cached_data = Cache.load_cache(cache_key)
        cached_time = cached_data["timestamp"]
        
        if now() - cached_time < Hour(ttl_hours)
            @info "Using cached data for $key"
            return cached_data["data"]
        else
            @info "Cache expired for $key, recomputing"
        end
    catch
        @info "No valid cache found for $key"
    end
    
    # Compute fresh data
    fresh_data = compute_fn()
    
    # Cache with timestamp
    Cache.save_cache(cache_key, Dict(
        "data" => fresh_data,
        "timestamp" => now()
    ))
    
    return fresh_data
end
```

### Performance Optimization Strategies

```julia
# Optimize data loading with chunking
function load_data_optimized(source, pair, timeframe; chunk_size=10000)
    # Check if we can load progressively
    try
        z_array = Data.load_ohlcv(Data.zi[], source, pair, timeframe; raw=true)
        total_size = size(z_array, 1)
        
        if total_size > chunk_size
            @info "Large dataset detected ($total_size rows), using progressive loading"
            return z_array  # Return ZArray for progressive access
        else
            # Small dataset, load normally
            return Data.load_ohlcv(Data.zi[], source, pair, timeframe)
        end
    catch e
        @warn "Failed to optimize loading: $e"
        return Data.load_ohlcv(Data.zi[], source, pair, timeframe)
    end
end

# Memory-efficient data processing
function process_large_dataset_efficiently(source, pair, timeframe, process_fn)
    z_array = Data.load_ohlcv(Data.zi[], source, pair, timeframe; raw=true)
    total_size = size(z_array, 1)
    chunk_size = 5000
    
    results = []
    
    for start_idx in 1:chunk_size:total_size
        end_idx = min(start_idx + chunk_size - 1, total_size)
        
        # Load chunk
        chunk_data = z_array[start_idx:end_idx, :]
        chunk_df = DataFrame(chunk_data, Data.OHLCV_COLUMNS)
        
        # Process chunk
        chunk_result = process_fn(chunk_df)
        push!(results, chunk_result)
        
        # Optional: garbage collection for large datasets
        if start_idx % (chunk_size * 10) == 1
            GC.gc()
        end
    end
    
    return results
end
```

### Cache Management

```julia
# Cache cleanup utilities
function cleanup_old_cache(max_age_days=30)
    cache_dir = Cache.CACHE_PATH[]
    cutoff_date = now() - Day(max_age_days)
    
    for file in readdir(cache_dir)
        file_path = joinpath(cache_dir, file)
        if isfile(file_path)
            file_time = DateTime(unix2datetime(stat(file_path).mtime))
            if file_time < cutoff_date
                rm(file_path)
                @info "Removed old cache file: $file"
            end
        end
    end
end

# Cache size monitoring
function cache_size_info()
    cache_dir = Cache.CACHE_PATH[]
    total_size = 0
    file_count = 0
    
    for (root, dirs, files) in walkdir(cache_dir)
        for file in files
            file_path = joinpath(root, file)
            total_size += stat(file_path).size
            file_count += 1
        end
    end
    
    size_mb = total_size / (1024 * 1024)
    @info "Cache contains $file_count files, total size: $(round(size_mb, digits=2)) MB"
    
    return (files=file_count, size_mb=size_mb)
end
```

### Storage Configuration Optimization

```julia
# Optimize Zarr storage settings
function configure_optimal_storage()
    # Configure chunk sizes based on typical access patterns
    Data.DEFAULT_CHUNK_SIZE[] = 1000  # Optimize for time-series access
    
    # Enable compression for better storage efficiency
    # (This would be configured at the ZarrInstance level)
    @info "Storage [configuration](../config.md) optimized for time-series data"
end

# Monitor storage performance
function storage_performance_test(source, pair, timeframe, n_operations=100)
    @info "Testing storage performance..."
    
    # Test write performance
    test_data = Data.load_ohlcv(Data.zi[], source, pair, timeframe)
    write_times = []
    
    for i in 1:n_operations
        test_key = "perf_test_$i"
        start_time = time()
        Data.save_ohlcv(Data.zi[], "test_source", test_key, timeframe, test_data)
        push!(write_times, time() - start_time)
    end
    
    # Test read performance
    read_times = []
    for i in 1:n_operations
        test_key = "perf_test_$i"
        start_time = time()
        Data.load_ohlcv(Data.zi[], "test_source", test_key, timeframe)
        push!(read_times, time() - start_time)
    end
    
    # Cleanup test data
    for i in 1:n_operations
        # Would need a delete function here
    end
    
    avg_write = mean(write_times) * 1000  # Convert to ms
    avg_read = mean(read_times) * 1000
    
    @info "Average write time: $(round(avg_write, digits=2)) ms"
    @info "Average read time: $(round(avg_read, digits=2)) ms"
    
    return (write_ms=avg_write, read_ms=avg_read)
end
```

## Data Processing and Transformation

The Data module provides comprehensive tools for processing and transforming financial data. This section covers data cleaning, validation, and transformation techniques.

### Data Cleaning and Validation

```julia
using DataFrames
using Statistics

# Comprehensive data cleaning function
function clean_ohlcv_data(data::DataFrame)
    cleaned_data = copy(data)
    issues_found = []
    
    # Remove rows with missing values
    before_count = nrow(cleaned_data)
    dropmissing!(cleaned_data)
    if nrow(cleaned_data) < before_count
        push!(issues_found, "Removed $(before_count - nrow(cleaned_data)) rows with missing values")
    end
    
    # Fix invalid OHLC relationships
    invalid_high = cleaned_data.high .< max.(cleaned_data.open, cleaned_data.close)
    invalid_low = cleaned_data.low .> min.(cleaned_data.open, cleaned_data.close)
    
    if any(invalid_high)
        cleaned_data.high[invalid_high] = max.(cleaned_data.open[invalid_high], cleaned_data.close[invalid_high])
        push!(issues_found, "Fixed $(sum(invalid_high)) invalid high prices")
    end
    
    if any(invalid_low)
        cleaned_data.low[invalid_low] = min.(cleaned_data.open[invalid_low], cleaned_data.close[invalid_low])
        push!(issues_found, "Fixed $(sum(invalid_low)) invalid low prices")
    end
    
    # Remove extreme outliers (beyond 5 standard deviations)
    price_cols = [:open, :high, :low, :close]
    for col in price_cols
        mean_price = mean(cleaned_data[!, col])
        std_price = std(cleaned_data[!, col])
        outliers = abs.(cleaned_data[!, col] .- mean_price) .> 5 * std_price
        
        if any(outliers)
            # Replace outliers with median
            median_price = median(cleaned_data[!, col])
            cleaned_data[outliers, col] .= median_price
            push!(issues_found, "Fixed $(sum(outliers)) outliers in $col")
        end
    end
    
    # Remove negative volumes
    negative_volume = cleaned_data.volume .< 0
    if any(negative_volume)
        cleaned_data = cleaned_data[.!negative_volume, :]
        push!(issues_found, "Removed $(sum(negative_volume)) rows with negative volume")
    end
    
    # Sort by timestamp
    sort!(cleaned_data, :timestamp)
    
    if !isempty(issues_found)
        @info "Data cleaning completed:" issues_found
    end
    
    return cleaned_data
end

# Example usage
raw_data = Data.load_ohlcv(Data.zi[], "binance", "BTC/USDT", "1h")
clean_data = clean_ohlcv_data(raw_data)
```

### Gap Detection and Filling

```julia
using TimeTicks

# Detect gaps in time series data
function detect_gaps(data::DataFrame, expected_timeframe)
    gaps = []
    
    for i in 2:nrow(data)
        expected_next = data.timestamp[i-1] + expected_timeframe
        actual_next = data.timestamp[i]
        
        if actual_next > expected_next
            gap_duration = actual_next - expected_next
            push!(gaps, (
                start = data.timestamp[i-1],
                end = actual_next,
                duration = gap_duration,
                missing_candles = Int(gap_duration / expected_timeframe)
            ))
        end
    end
    
    return gaps
end

# Fill gaps with interpolated data
function fill_gaps(data::DataFrame, timeframe)
    filled_data = copy(data)
    gaps = detect_gaps(data, timeframe)
    
    for gap in gaps
        if gap.missing_candles <= 10  # Only fill small gaps
            # Create timestamps for missing candles
            missing_timestamps = [gap.start + i * timeframe for i in 1:gap.missing_candles-1]
            
            # Find surrounding data points
            before_idx = findfirst(x -> x == gap.start, data.timestamp)
            after_idx = findfirst(x -> x == gap.end, data.timestamp)
            
            if !isnothing(before_idx) && !isnothing(after_idx)
                before_candle = data[before_idx, :]
                after_candle = data[after_idx, :]
                
                # Linear interpolation for prices
                for (i, ts) in enumerate(missing_timestamps)
                    weight = i / gap.missing_candles
                    
                    interpolated_candle = DataFrame(
                        timestamp = [ts],
                        open = [before_candle.close],  # Use previous close as open
                        high = [before_candle.close * (1 - weight) + after_candle.open * weight],
                        low = [before_candle.close * (1 - weight) + after_candle.open * weight],
                        close = [before_candle.close * (1 - weight) + after_candle.open * weight],
                        volume = [0.0]  # Set volume to 0 for interpolated data
                    )
                    
                    filled_data = vcat(filled_data, interpolated_candle)
                end
            end
        end
    end
    
    sort!(filled_data, :timestamp)
    return filled_data
end

# Example usage
data_with_gaps = Data.load_ohlcv(Data.zi[], "binance", "BTC/USDT", "1h")
gaps = detect_gaps(data_with_gaps, Hour(1))
@info "Found $(length(gaps)) gaps in data"

filled_data = fill_gaps(data_with_gaps, Hour(1))
```

### Data Transformation and Feature Engineering

```julia
# Add [technical indicators](../guides/[strategy](../guides/strategy-development.md)-development.md#technical-indicators) and features
function add_technical_features(data::DataFrame)
    enhanced_data = copy(data)
    
    # Price-based features
    enhanced_data.price_change = [0.0; diff(enhanced_data.close)]
    enhanced_data.price_change_pct = enhanced_data.price_change ./ enhanced_data.close
    enhanced_data.typical_price = (enhanced_data.high .+ enhanced_data.low .+ enhanced_data.close) ./ 3
    enhanced_data.price_range = enhanced_data.high .- enhanced_data.low
    enhanced_data.body_size = abs.(enhanced_data.close .- enhanced_data.open)
    
    # Volume-based features
    enhanced_data.volume_sma_20 = rolling_mean(enhanced_data.volume, 20)
    enhanced_data.volume_ratio = enhanced_data.volume ./ enhanced_data.volume_sma_20
    
    # Volatility measures
    enhanced_data.volatility_20 = rolling_std(enhanced_data.price_change_pct, 20)
    enhanced_data.atr_14 = calculate_atr(enhanced_data, 14)
    
    # Time-based features
    enhanced_data.hour = hour.(enhanced_data.timestamp)
    enhanced_data.day_of_week = dayofweek.(enhanced_data.timestamp)
    enhanced_data.is_weekend = enhanced_data.day_of_week .>= 6
    
    return enhanced_data
end

# Rolling statistics helper functions
function rolling_mean(data, window)
    result = similar(data, Float64)
    for i in 1:length(data)
        start_idx = max(1, i - window + 1)
        result[i] = mean(data[start_idx:i])
    end
    return result
end

function rolling_std(data, window)
    result = similar(data, Float64)
    for i in 1:length(data)
        start_idx = max(1, i - window + 1)
        result[i] = i < window ? 0.0 : std(data[start_idx:i])
    end
    return result
end

function calculate_atr(data, period)
    tr = max.(
        data.high .- data.low,
        abs.(data.high .- [data.close[1]; data.close[1:end-1]]),
        abs.(data.low .- [data.close[1]; data.close[1:end-1]])
    )
    return rolling_mean(tr, period)
end
```

## Storage Configuration and Optimization

This section covers advanced storage [configuration](../config.md), [optimization](../optimization.md) techniques, and [troubleshooting](../troubleshooting/) for the Zarr/LMDB backend.

### Zarr Storage Configuration

```julia
# Configure Zarr storage for optimal performance
function configure_zarr_storage(; 
    chunk_size=1000,
    compression_level=3,
    cache_size_mb=100)
    
    # Set default chunk size for time-series data
    Data.DEFAULT_CHUNK_SIZE[] = chunk_size
    
    # Configure compression (would be done at ZarrInstance creation)
    storage_config = Dict(
        "chunk_size" => chunk_size,
        "compression" => "zstd",
        "compression_level" => compression_level,
        "cache_size" => cache_size_mb * 1024 * 1024
    )
    
    @info "Zarr storage configured" storage_config
    return storage_config
end

# Create optimized ZarrInstance
function create_optimized_zarr_instance(storage_path; config...)
    # This would create a new ZarrInstance with optimized settings
    # Implementation depends on the actual ZarrInstance constructor
    @info "Creating optimized Zarr instance at $storage_path"
    
    # Example [configuration](../config.md)
    optimized_config = configure_zarr_storage(; config...)
    
    # Return configured instance (pseudo-code)
    # return ZarrInstance(storage_path; optimized_config...)
end
```

### LMDB Configuration and Tuning

```julia
# LMDB performance tuning
function tune_lmdb_performance(; 
    map_size_gb=10,
    max_readers=126,
    sync_mode=:nosync)
    
    lmdb_config = Dict(
        "map_size" => map_size_gb * 1024^3,  # Convert GB to bytes
        "max_readers" => max_readers,
        "sync" => sync_mode,
        "writemap" => true,  # Use memory-mapped writes
        "metasync" => false  # Disable metadata sync for performance
    )
    
    @info "LMDB configuration optimized" lmdb_config
    return lmdb_config
end

# Monitor LMDB performance
function lmdb_performance_stats()
    # This would query LMDB statistics
    # Implementation depends on the LMDB wrapper
    stats = Dict(
        "map_size_used" => "N/A",  # Would get actual usage
        "page_size" => "N/A",
        "max_readers" => "N/A",
        "num_readers" => "N/A"
    )
    
    @info "LMDB Performance Statistics" stats
    return stats
end
```

### Storage Optimization Strategies

```julia
# Optimize storage for different access patterns
function optimize_for_access_pattern(pattern::Symbol)
    if pattern == :sequential
        # Optimize for sequential time-series access
        configure_zarr_storage(chunk_size=2000, compression_level=1)
        @info "Optimized for sequential access"
        
    elseif pattern == :random
        # Optimize for random access
        configure_zarr_storage(chunk_size=500, compression_level=5)
        @info "Optimized for random access"
        
    elseif pattern == :analytical
        # Optimize for analytical workloads
        configure_zarr_storage(chunk_size=5000, compression_level=6)
        @info "Optimized for analytical workloads"
        
    else
        @warn "Unknown access pattern: $pattern"
    end
end

# Storage space analysis
function analyze_storage_usage(source_filter=nothing)
    total_size = 0
    pair_sizes = Dict()
    
    # This would iterate through the Zarr storage
    # Implementation depends on ZarrInstance structure
    
    @info "Storage Analysis" total_size_mb=(total_size / 1024^2) pair_count=length(pair_sizes)
    
    # Show top 10 largest pairs
    sorted_pairs = sort(collect(pair_sizes), by=x->x[2], rev=true)
    for (i, (pair, size)) in enumerate(sorted_pairs[1:min(10, end)])
        @info "  $i. $pair: $(round(size/1024^2, digits=2)) MB"
    end
    
    return pair_sizes
end
```

### Data Validation and Integrity

```julia
# Comprehensive data validation
function validate_data_integrity(source, pair, timeframe)
    validation_results = Dict()
    
    try
        data = Data.load_ohlcv(Data.zi[], source, pair, timeframe)
        
        # Basic structure validation
        validation_results["row_count"] = nrow(data)
        validation_results["has_required_columns"] = all(col in names(data) for col in Data.OHLCV_COLUMNS)
        
        # Data quality checks
        validation_results["has_missing_values"] = any(ismissing, eachcol(data))
        validation_results["has_negative_prices"] = any(data.open .< 0) || any(data.high .< 0) || 
                                                   any(data.low .< 0) || any(data.close .< 0)
        validation_results["has_negative_volume"] = any(data.volume .< 0)
        validation_results["has_invalid_ohlc"] = any(data.high .< data.low) || 
                                               any(data.high .< data.open) || 
                                               any(data.high .< data.close) ||
                                               any(data.low .> data.open) || 
                                               any(data.low .> data.close)
        
        # Timestamp validation
        validation_results["is_sorted"] = issorted(data.timestamp)
        validation_results["has_duplicates"] = length(unique(data.timestamp)) != nrow(data)
        
        # Detect gaps
        gaps = detect_gaps(data, eval(Meta.parse("tf\"$timeframe\"")))
        validation_results["gap_count"] = length(gaps)
        validation_results["largest_gap_hours"] = isempty(gaps) ? 0 : maximum(gap.duration for gap in gaps) / Hour(1)
        
        validation_results["status"] = "valid"
        
    catch e
        validation_results["status"] = "error"
        validation_results["error"] = string(e)
    end
    
    return validation_results
end

# Batch validation across multiple pairs
function validate_multiple_pairs(source, pairs, timeframe)
    results = Dict()
    
    for pair in pairs
        @info "Validating $pair..."
        results[pair] = validate_data_integrity(source, pair, timeframe)
    end
    
    # Summary statistics
    valid_count = sum(result["status"] == "valid" for result in values(results))
    error_count = length(pairs) - valid_count
    
    @info "Validation Summary" valid_pairs=valid_count error_pairs=error_count
    
    # Report issues
    for (pair, result) in results
        if result["status"] != "valid"
            @warn "Issues found in $pair" result
        end
    end
    
    return results
end
```

### Troubleshooting Storage Issues

```julia
# Diagnose common storage problems
function diagnose_storage_issues()
    issues = []
    
    # Check disk space
    storage_path = Data.zi[].store.path  # Pseudo-code
    available_space = diskspace(storage_path)
    if available_space < 1024^3  # Less than 1GB
        push!(issues, "Low disk space: $(round(available_space/1024^3, digits=2)) GB available")
    end
    
    # Check LMDB health
    try
        lmdb_stats = lmdb_performance_stats()
        # Add LMDB-specific checks here
    catch e
        push!(issues, "LMDB access error: $e")
    end
    
    # Check for corrupted data
    test_pairs = ["BTC/USDT", "ETH/USDT"]  # Common pairs for testing
    for pair in test_pairs
        try
            test_data = Data.load_ohlcv(Data.zi[], "binance", pair, "1h")
            if nrow(test_data) == 0
                push!(issues, "No data found for test pair: $pair")
            end
        catch e
            push!(issues, "Cannot load test pair $pair: $e")
        end
    end
    
    if isempty(issues)
        @info "No storage issues detected"
    else
        @warn "Storage issues detected:" issues
    end
    
    return issues
end

# Repair corrupted data
function repair_data_corruption(source, pair, timeframe; backup=true)
    @info "Attempting to repair data for $source/$pair/$timeframe"
    
    if backup
        # Create backup before repair
        try
            original_data = Data.load_ohlcv(Data.zi[], source, pair, timeframe)
            backup_key = "backup_$(source)_$(pair)_$(timeframe)_$(now())"
            Data.save_ohlcv(Data.zi[], "backups", backup_key, timeframe, original_data)
            @info "Backup created: $backup_key"
        catch e
            @warn "Could not create backup: $e"
        end
    end
    
    try
        # Load and clean data
        corrupted_data = Data.load_ohlcv(Data.zi[], source, pair, timeframe; check=:none)
        cleaned_data = clean_ohlcv_data(corrupted_data)
        
        # Save cleaned data
        Data.save_ohlcv(Data.zi[], source, pair, timeframe, cleaned_data; reset=true)
        @info "Data repair completed for $pair"
        
        return true
    catch e
        @error "Data repair failed: $e"
        return false
    end
end
```

[^1]: Default path might be a scratchspace (from Scratch.jl) in the future

!!! tip "Performance Best Practices"
    - Use progressive loading (`raw=true`) for datasets larger than available memory
    - Implement caching for expensive computations with appropriate TTL
    - Monitor cache size and clean up old entries regularly
    - Use chunked processing for very large datasets
    - Configure appropriate chunk sizes based on your access patterns

## Real-Time Data Pipelines and Monitoring

This section covers advanced real-time data collection, processing, and monitoring using the Watchers system.

### Real-Time Data Pipeline Architecture

```julia
using Exchanges
using Planar.Watchers: Watchers as wc, WatchersImpls as wi

# Complete real-time data pipeline setup
function setup_realtime_pipeline(exchanges, pairs; 
                                 save_interval=300,
                                 monitoring_interval=60)
    
    pipeline = Dict(
        :watchers => [],
        :monitors => [],
        :config => Dict(
            :save_interval => save_interval,
            :monitoring_interval => monitoring_interval,
            :start_time => now()
        )
    )
    
    # Create watchers for each exchange
    for exchange_name in exchanges
        try
            exc = getexchange!(exchange_name)
            
            # Multi-pair ticker watcher
            ticker_watcher = wi.ccxt_ohlcv_tickers_watcher(
                exc;
                timeout_interval=10,
                fetch_interval=5,
                flush_interval=save_interval
            )
            
            # Individual pair watchers for high-precision data
            pair_watchers = []
            for pair in pairs
                try
                    pair_watcher = wi.ccxt_ohlcv_watcher(
                        exc, pair;
                        timeframe=tf"1m",
                        timeout_interval=15,
                        fetch_interval=10
                    )
                    push!(pair_watchers, pair_watcher)
                catch e
                    @warn "Failed to create watcher for $pair on $exchange_name: $e"
                end
            end
            
            exchange_watchers = Dict(
                :ticker => ticker_watcher,
                :pairs => pair_watchers,
                :exchange => exchange_name
            )
            
            push!(pipeline[:watchers], exchange_watchers)
            @info "Created watchers for $exchange_name"
            
        catch e
            @error "Failed to setup watchers for $exchange_name: $e"
        end
    end
    
    return pipeline
end
```

### Advanced Watcher Management

```julia
# Comprehensive watcher lifecycle management
function start_pipeline(pipeline)
    @info "Starting real-time data pipeline..."
    
    for exchange_watchers in pipeline[:watchers]
        exchange_name = exchange_watchers[:exchange]
        
        try
            # Start ticker watcher
            wc.start!(exchange_watchers[:ticker])
            @info "Started ticker watcher for $exchange_name"
            
            # Start individual pair watchers
            for pair_watcher in exchange_watchers[:pairs]
                wc.start!(pair_watcher)
            end
            @info "Started $(length(exchange_watchers[:pairs])) pair watchers for $exchange_name"
            
        catch e
            @error "Failed to start watchers for $exchange_name: $e"
        end
    end
    
    # Start monitoring task
    monitoring_task = @async monitor_pipeline(pipeline)
    pipeline[:monitoring_task] = monitoring_task
    
    @info "Pipeline started successfully"
end

function stop_pipeline(pipeline)
    @info "Stopping real-time data pipeline..."
    
    # Stop monitoring
    if haskey(pipeline, :monitoring_task)
        try
            Base.schedule(pipeline[:monitoring_task], InterruptException(), error=true)
        catch
        end
    end
    
    # Stop all watchers
    for exchange_watchers in pipeline[:watchers]
        exchange_name = exchange_watchers[:exchange]
        
        try
            wc.stop!(exchange_watchers[:ticker])
            
            for pair_watcher in exchange_watchers[:pairs]
                wc.stop!(pair_watcher)
            end
            
            @info "Stopped watchers for $exchange_name"
        catch e
            @warn "Error stopping watchers for $exchange_name: $e"
        end
    end
    
    @info "Pipeline stopped"
end
```

### Real-Time Data Processing

```julia
# Real-time data processing and aggregation
function process_realtime_data(pipeline; processing_interval=60)
    @async while true
        try
            for exchange_watchers in pipeline[:watchers]
                exchange_name = exchange_watchers[:exchange]
                
                # Process ticker data
                ticker_data = exchange_watchers[:ticker].view
                if !isempty(ticker_data)
                    process_ticker_data(ticker_data, exchange_name)
                end
                
                # Process individual pair data
                for pair_watcher in exchange_watchers[:pairs]
                    if haskey(pair_watcher, :view) && !isempty(pair_watcher.view)
                        process_pair_data(pair_watcher.view, pair_watcher.pair, exchange_name)
                    end
                end
            end
            
            sleep(processing_interval)
            
        catch InterruptException
            break
        catch e
            @error "Error in real-time processing: $e"
            sleep(processing_interval)
        end
    end
end

function process_ticker_data(ticker_data, exchange_name)
    # Process aggregated ticker data
    for (pair, data) in ticker_data
        if nrow(data) > 0
            # Calculate real-time metrics
            latest_candle = data[end, :]
            
            # Store processed metrics
            metrics = Dict(
                :pair => pair,
                :exchange => exchange_name,
                :price => latest_candle.close,
                :volume_24h => sum(data.volume),
                :price_change_24h => (latest_candle.close - data.open[1]) / data.open[1],
                :timestamp => latest_candle.timestamp
            )
            
            # Save to cache for quick access
            Cache.save_cache("realtime_$(exchange_name)_$(pair)", metrics)
        end
    end
end

function process_pair_data(pair_data, pair, exchange_name)
    if nrow(pair_data) > 10  # Ensure we have enough data
        # Calculate [technical indicators](../guides/[strategy](../guides/strategy-development.md)-development.md#technical-indicators) in real-time
        indicators = calculate_realtime_indicators(pair_data)
        
        # Store indicators
        indicator_data = Dict(
            :pair => pair,
            :exchange => exchange_name,
            :indicators => indicators,
            :timestamp => now()
        )
        
        Cache.save_cache("indicators_$(exchange_name)_$(pair)", indicator_data)
    end
end

function calculate_realtime_indicators(data)
    # Calculate common [technical indicators](../guides/strategy-development.md#technical-indicators)
    indicators = Dict()
    
    if nrow(data) >= 20
        # Moving averages
        indicators[:sma_20] = mean(data.close[end-19:end])
        indicators[:ema_20] = calculate_ema(data.close, 20)
        
        # [RSI](../guides/strategy-development.md#technical-indicators)
        indicators[:rsi_14] = calculate_rsi(data.close, 14)
        
        # Bollinger Bands
        sma_20 = indicators[:sma_20]
        std_20 = std(data.close[end-19:end])
        indicators[:bb_upper] = sma_20 + 2 * std_20
        indicators[:bb_lower] = sma_20 - 2 * std_20
        
        # Volume indicators
        indicators[:volume_sma_20] = mean(data.volume[end-19:end])
        indicators[:volume_ratio] = data.volume[end] / indicators[:volume_sma_20]
    end
    
    return indicators
end
```

### Monitoring and Alerting

```julia
# Comprehensive pipeline monitoring
function monitor_pipeline(pipeline)
    monitoring_interval = pipeline[:config][:monitoring_interval]
    
    while true
        try
            @info "=== Pipeline Health Check ==="
            
            total_watchers = 0
            active_watchers = 0
            data_points = 0
            
            for exchange_watchers in pipeline[:watchers]
                exchange_name = exchange_watchers[:exchange]
                
                # Check ticker watcher
                ticker_watcher = exchange_watchers[:ticker]
                total_watchers += 1
                
                if wc.isrunning(ticker_watcher)
                    active_watchers += 1
                    data_points += length(ticker_watcher.view)
                    @info "✓ $exchange_name ticker: $(length(ticker_watcher.view)) pairs"
                else
                    @warn "✗ $exchange_name ticker watcher stopped"
                    # Attempt restart
                    try
                        wc.start!(ticker_watcher)
                        @info "Restarted $exchange_name ticker watcher"
                    catch e
                        @error "Failed to restart $exchange_name ticker watcher: $e"
                    end
                end
                
                # Check pair watchers
                for (i, pair_watcher) in enumerate(exchange_watchers[:pairs])
                    total_watchers += 1
                    
                    if wc.isrunning(pair_watcher)
                        active_watchers += 1
                        if haskey(pair_watcher, :view)
                            pair_data_count = nrow(pair_watcher.view)
                            data_points += pair_data_count
                            @info "✓ $exchange_name pair $i: $pair_data_count candles"
                        end
                    else
                        @warn "✗ $exchange_name pair watcher $i stopped"
                        # Attempt restart
                        try
                            wc.start!(pair_watcher)
                            @info "Restarted $exchange_name pair watcher $i"
                        catch e
                            @error "Failed to restart pair watcher: $e"
                        end
                    end
                end
            end
            
            # Overall health metrics
            health_ratio = active_watchers / total_watchers
            uptime = now() - pipeline[:config][:start_time]
            
            @info "Pipeline Status" active_watchers total_watchers health_ratio data_points uptime
            
            # Alert on poor health
            if health_ratio < 0.8
                @warn "Pipeline health degraded: $(round(health_ratio*100, digits=1))% watchers active"
                send_alert("Pipeline health alert", "Only $(active_watchers)/$(total_watchers) watchers active")
            end
            
            sleep(monitoring_interval)
            
        catch InterruptException
            @info "Monitoring stopped"
            break
        catch e
            @error "Monitoring error: $e"
            sleep(monitoring_interval)
        end
    end
end

# Alert system integration
function send_alert(title, message)
    # This could integrate with various alerting systems
    @warn "ALERT: $title - $message"
    
    # Example: Save alert to cache for external monitoring
    alert_data = Dict(
        :title => title,
        :message => message,
        :timestamp => now(),
        :severity => "warning"
    )
    
    Cache.save_cache("alert_$(now())", alert_data)
end
```

### Data Quality Monitoring

```julia
# Real-time data quality monitoring
function monitor_data_quality(pipeline)
    @async while true
        try
            quality_report = Dict()
            
            for exchange_watchers in pipeline[:watchers]
                exchange_name = exchange_watchers[:exchange]
                exchange_quality = Dict()
                
                # Check ticker data quality
                ticker_data = exchange_watchers[:ticker].view
                ticker_quality = analyze_ticker_quality(ticker_data)
                exchange_quality[:ticker] = ticker_quality
                
                # Check pair data quality
                pair_qualities = []
                for pair_watcher in exchange_watchers[:pairs]
                    if haskey(pair_watcher, :view) && !isempty(pair_watcher.view)
                        pair_quality = analyze_pair_quality(pair_watcher.view, pair_watcher.pair)
                        push!(pair_qualities, pair_quality)
                    end
                end
                exchange_quality[:pairs] = pair_qualities
                
                quality_report[exchange_name] = exchange_quality
            end
            
            # Generate quality alerts
            check_quality_alerts(quality_report)
            
            # Save quality report
            Cache.save_cache("quality_report_$(now())", quality_report)
            
            sleep(300)  # Check every 5 minutes
            
        catch InterruptException
            break
        catch e
            @error "Quality monitoring error: $e"
            sleep(300)
        end
    end
end

function analyze_ticker_quality(ticker_data)
    quality_metrics = Dict(
        :total_pairs => length(ticker_data),
        :active_pairs => 0,
        :stale_data_pairs => 0,
        :invalid_data_pairs => 0
    )
    
    current_time = now()
    
    for (pair, data) in ticker_data
        if !isempty(data)
            quality_metrics[:active_pairs] += 1
            
            # Check for stale data (older than 5 minutes)
            latest_timestamp = maximum(data.timestamp)
            if current_time - latest_timestamp > Minute(5)
                quality_metrics[:stale_data_pairs] += 1
            end
            
            # Check for invalid data
            if any(data.high .< data.low) || any(data.volume .< 0)
                quality_metrics[:invalid_data_pairs] += 1
            end
        end
    end
    
    return quality_metrics
end

function analyze_pair_quality(pair_data, pair)
    quality_metrics = Dict(
        :pair => pair,
        :candle_count => nrow(pair_data),
        :latest_timestamp => maximum(pair_data.timestamp),
        :has_gaps => false,
        :invalid_candles => 0,
        :data_freshness_minutes => 0
    )
    
    if nrow(pair_data) > 1
        # Check for gaps
        time_diffs = diff(pair_data.timestamp)
        expected_diff = Minute(1)  # Assuming 1-minute data
        gaps = time_diffs .> expected_diff * 1.5
        quality_metrics[:has_gaps] = any(gaps)
        
        # Check for invalid candles
        invalid = (pair_data.high .< pair_data.low) .| 
                 (pair_data.volume .< 0) .| 
                 (pair_data.high .< pair_data.open) .| 
                 (pair_data.high .< pair_data.close) .| 
                 (pair_data.low .> pair_data.open) .| 
                 (pair_data.low .> pair_data.close)
        quality_metrics[:invalid_candles] = sum(invalid)
        
        # Data freshness
        latest_time = maximum(pair_data.timestamp)
        quality_metrics[:data_freshness_minutes] = (now() - latest_time) / Minute(1)
    end
    
    return quality_metrics
end

function check_quality_alerts(quality_report)
    for (exchange, quality) in quality_report
        # Check ticker quality
        ticker_quality = quality[:ticker]
        if ticker_quality[:stale_data_pairs] > ticker_quality[:total_pairs] * 0.1
            send_alert("Stale Data Alert", 
                      "$exchange has $(ticker_quality[:stale_data_pairs]) pairs with stale data")
        end
        
        if ticker_quality[:invalid_data_pairs] > 0
            send_alert("Invalid Data Alert", 
                      "$exchange has $(ticker_quality[:invalid_data_pairs]) pairs with invalid data")
        end
        
        # Check pair quality
        for pair_quality in quality[:pairs]
            if pair_quality[:data_freshness_minutes] > 10
                send_alert("Data Freshness Alert", 
                          "$(pair_quality[:pair]) on $exchange has stale data ($(pair_quality[:data_freshness_minutes]) minutes old)")
            end
            
            if pair_quality[:invalid_candles] > 0
                send_alert("Invalid Candles Alert", 
                          "$(pair_quality[:pair]) on $exchange has $(pair_quality[:invalid_candles]) invalid candles")
            end
        end
    end
end
```

### Complete Pipeline Example

```julia
# Complete example: Setting up a production real-time data pipeline
function setup_production_pipeline()
    # Configuration
    exchanges = [:binance, :kucoin, :bybit]
    pairs = ["BTC/USDT", "ETH/USDT", "ADA/USDT", "DOT/USDT"]
    
    # Setup pipeline
    pipeline = setup_realtime_pipeline(exchanges, pairs; 
                                      save_interval=300,    # Save every 5 minutes
                                      monitoring_interval=60) # Monitor every minute
    
    # Start pipeline
    start_pipeline(pipeline)
    
    # Start data processing
    processing_task = process_realtime_data(pipeline; processing_interval=30)
    
    # Start quality monitoring
    quality_task = monitor_data_quality(pipeline)
    
    # Store tasks for cleanup
    pipeline[:processing_task] = processing_task
    pipeline[:quality_task] = quality_task
    
    @info "Production pipeline started successfully"
    @info "Monitoring $(length(exchanges)) exchanges and $(length(pairs)) pairs"
    
    return pipeline
end

# Graceful shutdown
function shutdown_production_pipeline(pipeline)
    @info "Shutting down production pipeline..."
    
    # Stop processing tasks
    for task_key in [:processing_task, :quality_task, :monitoring_task]
        if haskey(pipeline, task_key)
            try
                Base.schedule(pipeline[task_key], InterruptException(), error=true)
            catch
            end
        end
    end
    
    # Stop watchers
    stop_pipeline(pipeline)
    
    @info "Production pipeline shutdown complete"
end

# Usage example
# pipeline = setup_production_pipeline()
# 
# # Run for some time...
# sleep(3600)  # Run for 1 hour
# 
# # Shutdown gracefully
# shutdown_production_pipeline(pipeline)
```

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
    - Cache processed data for quick access by trading [strategies](../guides/strategy-development.md)
    - Set up proper logging and error handling for debugging issues
