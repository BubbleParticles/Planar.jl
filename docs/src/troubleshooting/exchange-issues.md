---
title: "Exchange Issues"
description: "Solutions for exchange API and connectivity problems"
category: "troubleshooting"
---

# Exchange Issues

This guide helps resolve problems related to exchange connectivity, API authentication, and trading operations.

## API Authentication Issues

### Invalid API Credentials

**Problem**: "Invalid API key" or "Authentication failed" errors.

**Solution**:
1. Verify API key and secret in `user/secrets.toml`
2. Check API key permissions on exchange
3. Ensure API key is not expired
4. Test with sandbox/testnet first

### API Rate Limiting

**Problem**: "Rate limit exceeded" errors.

**Solution**:
```julia
# Reduce request frequency
config.exchange.rate_limit = 1000  # milliseconds between requests

# Use built-in rate limiting
config.exchange.enable_rate_limit = true
```

### IP Restrictions

**Problem**: API calls blocked due to IP restrictions.

**Solution**:
1. Add your IP to exchange whitelist
2. Use VPN if accessing from restricted region
3. Contact exchange support for IP issues

## Connectivity Issues

### Network Timeouts

**Problem**: Connection timeouts to exchange APIs.

**Solution**:
```julia
# Increase timeout settings
config.exchange.timeout = 30000  # 30 seconds

# Enable retry logic
config.exchange.retry_attempts = 3
```

### SSL/TLS Issues

**Problem**: SSL certificate verification failures.

**Solution**:
```julia
# For development only - not recommended for production
config.exchange.verify_ssl = false
```



## Exchange-Specific Issues

### Binance

**Common Issues**:
- API key restrictions (spot vs futures)
- Testnet vs mainnet confusion
- Symbol format differences

**Solutions**:
```julia
# Use correct Binance endpoint
config.exchanges.binance.sandbox = true  # for testnet
config.exchanges.binance.futures = true  # for futures trading
```

### Coinbase Pro

**Common Issues**:
- Passphrase requirement
- Sandbox environment setup

**Solutions**:
```toml
[exchanges.coinbase]
api_key = "your_key"
secret = "your_secret"
passphrase = "your_passphrase"
sandbox = true
```

### Kraken

**Common Issues**:
- API tier limitations
- Symbol naming conventions

**Solutions**:
- Verify API tier supports required features
- Use correct symbol format (e.g., "XBTUSD" not "BTCUSD")

## Data Issues

### Missing Market Data

**Problem**: No price data available for symbol.

**Solution**:
1. Verify symbol exists on exchange
2. Check if market is active/trading
3. Ensure timeframe is supported
4. Test with different symbol

### Incomplete Historical Data

**Problem**: Insufficient historical data for backtesting.

**Solution**:
```julia
# Check available data range
data_range = fetch_available_range(exchange, symbol, timeframe)

# Adjust backtest period
config.backtest.start_date = data_range.start
```

### Data Quality Issues

**Problem**: Gaps or inconsistencies in price data.

**Solution**:
```julia
# Enable data validation
config.data.validate_ohlcv = true
config.data.fill_gaps = true

# Use data cleaning
config.data.remove_outliers = true
```

## Trading Issues

### Order Placement Failures

**Problem**: Orders rejected by exchange.

**Solution**:
1. Check minimum order size requirements
2. Verify sufficient balance
3. Ensure price is within allowed range
4. Check market hours and status

### Position Management Issues

**Problem**: Position size or margin calculations incorrect.

**Solution**:
```julia
# Verify margin settings
config.trading.margin_mode = "isolated"  # or "cross"
config.trading.leverage = 1  # start with no leverage

# Check position sizing
config.risk.max_position_size = 0.1  # 10% of portfolio
```

### Slippage Issues

**Problem**: Significant price slippage on orders.

**Solution**:
```julia
# Use limit orders instead of market orders
config.trading.default_order_type = "limit"

# Add slippage protection
config.trading.max_slippage = 0.001  # 0.1%
```

## Monitoring and Debugging

### Enable Debug Logging

```julia
# Enable detailed exchange logging
config.logging.exchange_debug = true
config.logging.level = "DEBUG"
```

### Test Exchange Connectivity

```julia
# Test basic connectivity
using Planar
exchange = setup_exchange(:binance, sandbox=true)
test_connectivity(exchange)

# Test API authentication
test_authentication(exchange)
```

### Monitor API Usage

```julia
# Check rate limit status
rate_limit_info = exchange.get_rate_limit_status()

# Monitor API call frequency
config.monitoring.track_api_calls = true
```

## Emergency Procedures

### Stop All Trading

```julia
# Emergency stop - cancel all orders
emergency_stop(exchange)

# Close all positions (if supported)
close_all_positions(exchange)
```

### API Key Compromise

If you suspect API key compromise:

1. Immediately disable API key on exchange
2. Generate new API credentials
3. Update `user/secrets.toml`
4. Review recent trading activity
5. Enable IP restrictions

## Getting Help

For exchange-specific issues:

1. Check exchange status pages
2. Review exchange API documentation
3. Contact exchange support
4. Check [Planar GitHub Issues](https://github.com/defnlnotme/Planar.jl/issues)
5. Join community discussions

## Related Documentation

- [Configuration Guide](../config.md)
- [Installation Issues](installation-issues.md)
- [Performance Issues](performance-issues.md)