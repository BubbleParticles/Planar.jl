---
title: "Exchanges API"
description: "Exchange interfaces and connectivity"
category: "api-reference"
difficulty: "advanced"
prerequisites: ["getting-started", "exchanges"]
topics: ["api-reference", "exchanges", "connectivity", "ccxt"]
last_updated: "2025-10-04"
estimated_time: "Reference material"
---

# Exchanges API

The Exchanges module provides unified interfaces for connecting to cryptocurrency exchanges through the CCXT library. It handles exchange connectivity, market data access, and order management across multiple exchanges.

## Overview

The Exchanges module includes:
- Exchange connection and authentication management
- Unified market data interfaces
- Order placement and management
- Account and balance information
- Market information and trading rules
- Sandbox and live trading modes

## Core Exchange Types

### Exchange Identification

```julia
# Exchange ID type for type-safe exchange handling
struct ExchangeID{T} end

# Common exchange IDs
const BinanceID = ExchangeID{:binance}
const CoinbaseID = ExchangeID{:coinbase}
const KrakenID = ExchangeID{:kraken}
const BybitID = ExchangeID{:bybit}

# Create exchange ID
binance_id = ExchangeID(:binance)
```

### Exchange Connection

```julia
using Planar
@environment!

# Get exchange instance
exc = getexchange!(:binance; sandbox=true)
println("Connected to: $(exc.id)")

# Check connection status
if issandbox(exc)
    println("Running in sandbox mode")
else
    println("Running in live mode")
end

# Get exchange information
exchange_info = exc.info
println("Exchange name: $(exchange_info.name)")
println("Countries: $(exchange_info.countries)")
```

## Market Data Access

### Market Information

```julia
# Get available markets
markets = exc.markets
println("Available markets: $(length(markets))")

# Get specific market information
btc_usdt_market = markets["BTC/USDT"]
println("BTC/USDT Market Info:")
println("  Base: $(btc_usdt_market.base)")
println("  Quote: $(btc_usdt_market.quote)")
println("  Active: $(btc_usdt_market.active)")

# Market limits and precision
limits = market_limits(exc, "BTC/USDT")
precision = market_precision(exc, "BTC/USDT")

println("Trading Limits:")
println("  Min Amount: $(limits.amount.min)")
println("  Max Amount: $(limits.amount.max)")
println("  Min Price: $(limits.price.min)")
println("  Max Price: $(limits.price.max)")

println("Precision:")
println("  Amount: $(precision.amount)")
println("  Price: $(precision.price)")
```

### Fee Information

```julia
# Get trading fees for a market
fees = market_fees(exc, "BTC/USDT")
println("Trading Fees:")
println("  Maker: $(fees.maker * 100)%")
println("  Taker: $(fees.taker * 100)%")

# Calculate fee for a trade
trade_amount = 1.0  # 1 BTC
trade_price = 45000.0  # $45,000
trade_value = trade_amount * trade_price

maker_fee = trade_value * fees.maker
taker_fee = trade_value * fees.taker

println("Fee for $trade_value trade:")
println("  Maker fee: $maker_fee")
println("  Taker fee: $taker_fee")
println("  Savings with maker: $(taker_fee - maker_fee)")
```

### Market Data Retrieval

```julia
# Fetch OHLCV data
symbol = "BTC/USDT"
timeframe = "1h"
limit = 100

ohlcv_data = fetch_ohlcv(exc, timeframe, symbol; limit=limit)
println("Fetched $(length(ohlcv_data[symbol].data.close)) candles")

# Get latest ticker
ticker = exc.fetch_ticker(symbol)
println("Current BTC/USDT:")
println("  Bid: $(ticker.bid)")
println("  Ask: $(ticker.ask)")
println("  Last: $(ticker.last)")
println("  Volume: $(ticker.baseVolume)")

# Get order book
orderbook = exc.fetch_order_book(symbol, limit=10)
println("Order Book (top 5):")
println("Bids:")
for i in 1:min(5, length(orderbook.bids))
    price, amount = orderbook.bids[i]
    println("  $price: $amount")
end
println("Asks:")
for i in 1:min(5, length(orderbook.asks))
    price, amount = orderbook.asks[i]
    println("  $price: $amount")
end
```

## Account Management

### Account Information

```julia
# Get account information
account_info = account(exc)
println("Account: $account_info")

# Get all available accounts (for exchanges that support multiple accounts)
all_accounts = accounts(exc)
println("Available accounts: $all_accounts")

# Get current active account
current_acc = current_account(exc)
println("Current account: $current_acc")

# Switch account (if supported)
# set_account!(exc, "spot")  # Switch to spot account
```

### Balance Information

```julia
# Get account balances
balances = exc.fetch_balance()
println("Account Balances:")

for (currency, balance_info) in balances
    if balance_info.total > 0
        println("  $currency:")
        println("    Total: $(balance_info.total)")
        println("    Free: $(balance_info.free)")
        println("    Used: $(balance_info.used)")
    end
end

# Get specific currency balance
btc_balance = balances["BTC"]
usdt_balance = balances["USDT"]

println("BTC Balance: $(btc_balance.free) ($(btc_balance.total) total)")
println("USDT Balance: $(usdt_balance.free) ($(usdt_balance.total) total)")
```

## Order Management

### Order Placement

```julia
# Place a limit buy order
function place_limit_buy_order(exc, symbol, amount, price)
    try
        order = exc.create_limit_buy_order(symbol, amount, price)
        println("Buy order placed:")
        println("  ID: $(order.id)")
        println("  Symbol: $(order.symbol)")
        println("  Amount: $(order.amount)")
        println("  Price: $(order.price)")
        println("  Status: $(order.status)")
        return order
    catch e
        @error "Failed to place buy order" exception=e
        return nothing
    end
end

# Place a limit sell order
function place_limit_sell_order(exc, symbol, amount, price)
    try
        order = exc.create_limit_sell_order(symbol, amount, price)
        println("Sell order placed:")
        println("  ID: $(order.id)")
        println("  Symbol: $(order.symbol)")
        println("  Amount: $(order.amount)")
        println("  Price: $(order.price)")
        println("  Status: $(order.status)")
        return order
    catch e
        @error "Failed to place sell order" exception=e
        return nothing
    end
end

# Example usage (in sandbox mode)
if issandbox(exc)
    # Place a small test order
    test_order = place_limit_buy_order(exc, "BTC/USDT", 0.001, 40000.0)
end
```

### Order Monitoring

```julia
# Get open orders
open_orders = exc.fetch_open_orders("BTC/USDT")
println("Open orders for BTC/USDT: $(length(open_orders))")

for order in open_orders
    println("Order $(order.id):")
    println("  Side: $(order.side)")
    println("  Amount: $(order.amount)")
    println("  Price: $(order.price)")
    println("  Filled: $(order.filled)")
    println("  Remaining: $(order.remaining)")
    println("  Status: $(order.status)")
end

# Get order history
order_history = exc.fetch_orders("BTC/USDT", limit=10)
println("Recent orders: $(length(order_history))")

# Cancel an order
function cancel_order_safe(exc, order_id, symbol)
    try
        result = exc.cancel_order(order_id, symbol)
        println("Order $order_id cancelled successfully")
        return result
    catch e
        @error "Failed to cancel order $order_id" exception=e
        return nothing
    end
end
```

## Exchange Configuration

### Exchange Parameters

```julia
# Get exchange parameters
exchange_params = params(exc)
println("Exchange Parameters:")
for (key, value) in exchange_params
    println("  $key: $value")
end

# Set exchange parameters
function configure_exchange(exc; api_key=nothing, secret=nothing, sandbox=false)
    if !isnothing(api_key)
        exc.apiKey = api_key
    end
    if !isnothing(secret)
        exc.secret = secret
    end
    exc.sandbox = sandbox
    
    println("Exchange configured:")
    println("  Sandbox: $(exc.sandbox)")
    println("  API Key: $(isnothing(exc.apiKey) ? "Not set" : "Set")")
end
```

### Market Symbol Mapping

```julia
# Get market symbols for strategy
function get_strategy_markets(s::Strategy)
    markets = marketsid(s)
    println("Strategy markets: $markets")
    return markets
end

# Convert between symbol formats
function normalize_symbol(symbol::String, exc)
    # Different exchanges may use different symbol formats
    # This function normalizes them
    
    if exc.id == :binance
        return replace(symbol, "/" => "")  # BTC/USDT -> BTCUSDT
    elseif exc.id == :coinbase
        return replace(symbol, "/" => "-")  # BTC/USDT -> BTC-USDT
    else
        return symbol  # Keep original format
    end
end

# Get all tradeable symbols
function get_tradeable_symbols(exc, base_currencies=["BTC", "ETH", "ADA"])
    tradeable = String[]
    
    for (symbol, market) in exc.markets
        if market.active && market.base in base_currencies
            push!(tradeable, symbol)
        end
    end
    
    return sort(tradeable)
end
```

## Error Handling and Resilience

### Connection Management

```julia
# Robust exchange connection
function connect_exchange_robust(exchange_id::Symbol; max_retries=3, sandbox=true)
    for attempt in 1:max_retries
        try
            exc = getexchange!(exchange_id; sandbox=sandbox)
            
            # Test connection
            exc.fetch_markets()
            
            println("Successfully connected to $exchange_id (attempt $attempt)")
            return exc
        catch e
            @warn "Connection attempt $attempt failed" exception=e
            if attempt == max_retries
                @error "Failed to connect after $max_retries attempts"
                rethrow(e)
            end
            sleep(2^attempt)  # Exponential backoff
        end
    end
end

# Rate limit handling
function fetch_with_rate_limit(exc, fetch_func, args...; max_retries=3)
    for attempt in 1:max_retries
        try
            return fetch_func(args...)
        catch e
            if occursin("rate limit", string(e)) || occursin("429", string(e))
                wait_time = 2^attempt
                @warn "Rate limit hit, waiting $wait_time seconds" attempt=attempt
                sleep(wait_time)
            else
                rethrow(e)
            end
        end
    end
    error("Max retries exceeded for rate-limited request")
end
```

### Market Data Validation

```julia
# Validate market data
function validate_ohlcv_data(data, symbol)
    if isempty(data)
        @error "No data received for $symbol"
        return false
    end
    
    # Check for reasonable values
    for i in 1:length(data.open)
        o, h, l, c, v = data.open[i], data.high[i], data.low[i], data.close[i], data.volume[i]
        
        # Basic OHLCV validation
        if !(l <= o <= h && l <= c <= h)
            @error "Invalid OHLCV data at index $i" open=o high=h low=l close=c
            return false
        end
        
        # Volume should be non-negative
        if v < 0
            @error "Negative volume at index $i" volume=v
            return false
        end
    end
    
    return true
end

# Safe data fetching
function fetch_ohlcv_safe(exc, symbol, timeframe; limit=100, max_retries=3)
    for attempt in 1:max_retries
        try
            data = fetch_with_rate_limit(exc, exc.fetch_ohlcv, symbol, timeframe, nothing, limit)
            
            if validate_ohlcv_data(data, symbol)
                return data
            else
                @warn "Invalid data received for $symbol, retrying..."
            end
        catch e
            @warn "Data fetch failed for $symbol (attempt $attempt)" exception=e
            if attempt == max_retries
                rethrow(e)
            end
            sleep(1)
        end
    end
end
```

## Multi-Exchange Support

### Exchange Comparison

```julia
# Compare fees across exchanges
function compare_exchange_fees(symbol, exchanges)
    println("Fee Comparison for $symbol:")
    println("=" ^ 40)
    
    for exc in exchanges
        try
            fees = market_fees(exc, symbol)
            println("$(exc.id):")
            println("  Maker: $(fees.maker * 100)%")
            println("  Taker: $(fees.taker * 100)%")
        catch e
            println("$(exc.id): Error getting fees - $e")
        end
    end
end

# Find best exchange for trading
function find_best_exchange(symbol, exchanges; prefer_maker=true)
    best_exchange = nothing
    best_fee = Inf
    
    for exc in exchanges
        try
            fees = market_fees(exc, symbol)
            fee = prefer_maker ? fees.maker : fees.taker
            
            if fee < best_fee
                best_fee = fee
                best_exchange = exc
            end
        catch e
            @warn "Could not get fees for $(exc.id)" exception=e
        end
    end
    
    return best_exchange, best_fee
end
```

## Complete API Reference

```@autodocs
Modules = [Planar.Exchanges, Planar.Exchanges.ExchangeTypes]
```

## See Also

- **[CCXT API](ccxt.md)** - CCXT library integration and utilities
- **[Engine API](engine.md)** - Core execution engine functions
- **[Strategies API](strategies.md)** - Strategy base classes and interfaces
- **[Exchange Configuration Guide](../guides/exchanges.md)** - Setting up exchange connections
- **[Troubleshooting](../troubleshooting/exchange-issues.md)** - Common exchange connection issues
