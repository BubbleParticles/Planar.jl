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

### SSL/TLS Issues

**Problem**: SSL certificate verification failures.

**Solution**:



## Exchange-Specific Issues

### Binance

**Common Issues**:
- API key restrictions (spot vs futures)
- Testnet vs mainnet confusion
- Symbol format differences

**Solutions**:

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

### Data Quality Issues

**Problem**: Gaps or inconsistencies in price data.

**Solution**:

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

### Slippage Issues

**Problem**: Significant price slippage on orders.

**Solution**:

## Monitoring and Debugging

### Enable Debug Logging


### Test Exchange Connectivity


### Monitor API Usage


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