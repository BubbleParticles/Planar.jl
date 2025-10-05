---
title: "Exchange Integration"
description: "Complete guide to exchange integration in Planar, including CCXT support, configuration, and troubleshooting"
category: "reference"
difficulty: "intermediate"
---

# Exchange Integration

Planar provides unified access to 100+ cryptocurrency exchanges through the CCXT library integration. This guide covers exchange setup, configuration, and advanced usage patterns for trading across multiple exchanges.

## Overview

Planar's exchange system is built around the concept of exchange instances that provide a consistent interface regardless of the underlying exchange API. Each exchange is represented by a subtype of `CcxtExchange` that wraps the CCXT library functionality.

### Key Features

- **100+ Exchange Support** - Access to major cryptocurrency exchanges via CCXT
- **Unified Interface** - Consistent API across all supported exchanges
- **Sandbox Support** - Test trading strategies without real money
- **Multi-Account Support** - Manage multiple API keys per exchange
- **Real-time Data** - WebSocket and REST API support for live market data
- **Order Management** - Unified order types and execution across exchanges

## CCXT Integration

Planar uses the CCXT library through Ccxt.jl to provide exchange connectivity. CCXT is a comprehensive cryptocurrency trading library that standardizes exchange APIs.

### Supported Exchanges

Popular exchanges supported through CCXT include:

- **Binance** - World's largest cryptocurrency exchange
- **Bybit** - Derivatives and spot trading
- **KuCoin** - Global cryptocurrency exchange
- **Coinbase Pro** - Professional trading platform
- **Kraken** - Established European exchange
- **OKX** - Global crypto exchange and derivatives platform
- **Huobi** - Major Asian cryptocurrency exchange

For a complete list of supported exchanges, see the [CCXT documentation](https://docs.ccxt.com/).

### Exchange Instance Management

Planar maintains one exchange instance per exchange configuration (sandbox/production and account combinations). This ensures efficient resource usage and consistent state management.

```julia
using Planar

# Get exchange instance (creates if doesn't exist)
binance = getexchange!(:binance)
bybit_testnet = getexchange!(:bybit, sandbox=true)
```

## Exchange Configuration

Configure exchanges in your `user/planar.toml` file with exchange-specific settings:

### Basic Configuration

```toml
# Binance configuration
[binance]
leveraged = "from"  # Leverage mode for margin trading
sandbox = false     # Use production environment

# Bybit configuration
[bybit]
futures = true      # Enable futures trading
testnet = false     # Use production environment

# KuCoin configuration
[kucoin]
futures = false     # Spot trading only
```

### Advanced Configuration Options

```toml
[binance]
leveraged = "from"          # "from", "to", or "both"
sandbox = false             # Production vs sandbox
timeout = 30000            # Request timeout in milliseconds
rateLimit = 1200           # Rate limit in milliseconds
enableRateLimit = true     # Enable automatic rate limiting
```

### API Credentials

Store API credentials securely in `user/secrets.toml`:

```toml
[exchanges.binance]
apiKey = "your_binance_api_key"
secret = "your_binance_secret_key"

[exchanges.bybit]
apiKey = "your_bybit_api_key"
secret = "your_bybit_secret_key"

[exchanges.coinbase]
apiKey = "your_coinbase_api_key"
secret = "your_coinbase_secret_key"
passphrase = "your_coinbase_passphrase"
```

## Exchange Features

### Market Data Access

Access real-time and historical market data:

```julia
# Get available markets
markets = fetch_markets(exchange)

# Get current ticker data
ticker = fetch_ticker(exchange, "BTC/USDT")

# Get order book
orderbook = fetch_order_book(exchange, "BTC/USDT")

# Get OHLCV data
ohlcv = fetch_ohlcv(exchange, "BTC/USDT", "1h")
```

### Trading Operations

Execute trades across different exchanges with a unified interface:

```julia
# Place market order
order = create_market_buy_order(exchange, "BTC/USDT", 0.001)

# Place limit order
order = create_limit_sell_order(exchange, "BTC/USDT", 0.001, 50000)

# Check order status
status = fetch_order_status(exchange, order.id, "BTC/USDT")

# Cancel order
cancel_order(exchange, order.id, "BTC/USDT")
```

### Account Information

Access account balances and trading history:

```julia
# Get account balance
balance = fetch_balance(exchange)

# Get trading history
trades = fetch_my_trades(exchange, "BTC/USDT")

# Get order history
orders = fetch_orders(exchange, "BTC/USDT")
```

## Multi-Exchange Trading

Planar supports trading across multiple exchanges simultaneously:

### Exchange Selection Strategy

```julia
# Define exchange preferences
primary_exchange = :binance
backup_exchanges = [:bybit, :kucoin]

# Get best available exchange
function get_best_exchange(symbol)
    try
        return getexchange!(primary_exchange)
    catch
        for backup in backup_exchanges
            try
                return getexchange!(backup)
            catch
                continue
            end
        end
        error("No available exchanges for $symbol")
    end
end
```

### Cross-Exchange Arbitrage

```julia
# Compare prices across exchanges
function find_arbitrage_opportunities(symbol)
    exchanges = [:binance, :bybit, :kucoin]
    prices = Dict()
    
    for exchange_id in exchanges
        try
            exchange = getexchange!(exchange_id)
            ticker = fetch_ticker(exchange, symbol)
            prices[exchange_id] = ticker.bid
        catch e
            @warn "Failed to get price from $exchange_id: $e"
        end
    end
    
    return prices
end
```

## Sandbox and Testing

Use sandbox environments for safe testing:

### Sandbox Configuration

```toml
[binance]
sandbox = true  # Use Binance testnet

[bybit]
testnet = true  # Use Bybit testnet
```

### Sandbox API Keys

Configure separate API keys for sandbox environments:

```toml
[exchanges.binance_sandbox]
apiKey = "testnet_api_key"
secret = "testnet_secret_key"

[exchanges.bybit_testnet]
apiKey = "testnet_api_key"
secret = "testnet_secret_key"
```

## Error Handling and Resilience

### Connection Management

Planar automatically handles connection issues and retries:

```julia
# Automatic retry on connection failure
try
    ticker = fetch_ticker(exchange, "BTC/USDT")
catch NetworkError
    # Automatic reconnection and retry
    sleep(1)
    ticker = fetch_ticker(exchange, "BTC/USDT")
end
```

### Rate Limiting

CCXT automatically handles rate limiting for most exchanges:

```julia
# Rate limiting is handled automatically
for symbol in ["BTC/USDT", "ETH/USDT", "SOL/USDT"]
    ticker = fetch_ticker(exchange, symbol)  # Automatically rate limited
end
```

### Error Types

Common exchange-related errors:

- **NetworkError** - Connection issues
- **ExchangeError** - Exchange-specific errors
- **AuthenticationError** - Invalid API credentials
- **InsufficientFunds** - Not enough balance for trade
- **InvalidOrder** - Order parameters are invalid

## Performance Optimization

### Connection Pooling

Reuse exchange instances for better performance:

```julia
# Good: Reuse exchange instance
exchange = getexchange!(:binance)
for symbol in symbols
    ticker = fetch_ticker(exchange, symbol)
end

# Avoid: Creating new instances
for symbol in symbols
    exchange = getexchange!(:binance)  # Inefficient
    ticker = fetch_ticker(exchange, symbol)
end
```

### Batch Operations

Use batch operations when available:

```julia
# Fetch multiple tickers at once
tickers = fetch_tickers(exchange, ["BTC/USDT", "ETH/USDT", "SOL/USDT"])

# Batch order placement (exchange-dependent)
orders = create_orders(exchange, order_list)
```

## Troubleshooting

### Common Issues

1. **API Authentication Failures**
   - Verify API keys in `user/secrets.toml`
   - Check API key permissions on exchange
   - Ensure IP whitelist includes your address

2. **Connection Timeouts**
   - Check network connectivity
   - Increase timeout settings in configuration
   - Use sandbox environment for testing

3. **Rate Limit Exceeded**
   - Enable automatic rate limiting
   - Reduce request frequency
   - Use WebSocket connections for real-time data

4. **Market Not Available**
   - Verify symbol format (e.g., "BTC/USDT" vs "BTCUSDT")
   - Check if market is active on the exchange
   - Ensure futures/spot configuration matches market type

### Debug Mode

Enable debug logging for troubleshooting:

```julia
ENV["JULIA_DEBUG"] = "Exchanges"
exchange = getexchange!(:binance)
```

## Advanced Usage

### Custom Exchange Implementation

Extend Planar with custom exchange support:

```julia
# Define custom exchange type
struct MyCustomExchange <: AbstractExchange
    # Exchange-specific fields
end

# Implement required interface methods
function fetch_ticker(exchange::MyCustomExchange, symbol::String)
    # Custom implementation
end
```

### WebSocket Integration

Use WebSocket connections for real-time data:

```julia
# Create WebSocket watcher
watcher = ccxt_ohlcv_watcher(exchange, "BTC/USDT", timeframe="1m")

# Start real-time data collection
start!(watcher)

# Access real-time data
current_price = last_price(watcher)
```

## Future Developments

Planned enhancements to exchange integration:

- **DEX Support** - Integration with decentralized exchanges
- **Additional Protocols** - Support for more blockchain protocols  
- **Enhanced WebSocket** - Improved real-time data handling
- **Order Routing** - Intelligent order routing across exchanges

## See Also

- [Configuration Guide](config.md) - Exchange configuration details
- [Strategy Development](guides/strategy-development.md) - Using exchanges in strategies
- [Troubleshooting](troubleshooting/exchange-issues.md) - Exchange-specific problem resolution
- [API Reference](API/exchanges.md) - Exchange API documentation
- [CCXT Documentation](https://docs.ccxt.com/) - Underlying CCXT library reference