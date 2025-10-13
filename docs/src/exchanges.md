<!--
title: "Exchange Integration"
description: "Complete guide to exchange integration in Planar, including CCXT support, configuration, and troubleshooting"
category: "reference"
difficulty: "intermediate"
-->

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


### Trading Operations

Execute trades across different exchanges with a unified interface:


### Account Information

Access account balances and trading history:


## Multi-Exchange Trading

Planar supports trading across multiple exchanges simultaneously:

### Exchange Selection Strategy


### Cross-Exchange Arbitrage


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


### Rate Limiting

CCXT automatically handles rate limiting for most exchanges:


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


### Batch Operations

Use batch operations when available:


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


## Advanced Usage

### Custom Exchange Implementation

Extend Planar with custom exchange support:


### WebSocket Integration

Use WebSocket connections for real-time data:


## Future Developments

Planned enhancements to exchange integration:

- **DEX Support** - Integration with decentralized exchanges
- **Additional Protocols** - Support for more blockchain protocols  
- **Enhanced WebSocket** - Improved real-time data handling
- **Order Routing** - Intelligent order routing across exchanges

## See Also

- [Configuration Guide](config.md) - Exchange configuration details
- [Strategy Development](guides/../guides/strategy-development.md) - Using exchanges in strategies
- [Troubleshooting](troubleshooting/exchange-issues.md) - Exchange-specific problem resolution
- [API Reference](API/exchanges.md) - Exchange API documentation
- [CCXT Documentation](https://docs.ccxt.com/) - Underlying CCXT library reference