<!--
title: "Configuration Guide"
description: "Complete guide to configuring Planar for trading, including strategy setup, exchange configuration, and secrets management"
category: "reference"
difficulty: "beginner"
-->

# Configuration Guide

Planar uses a flexible configuration system based on TOML files to manage strategies, exchanges, and sensitive credentials. This guide covers all aspects of configuration from basic setup to advanced customization.

## Configuration Files Overview

Planar uses two main configuration files:

- **`user/planar.toml`** - Main configuration file for strategies, exchanges, and general settings
- **`user/secrets.toml`** - Secure storage for API keys and sensitive credentials

## Configuration File

The main configuration file `user/planar.toml` serves as the central hub for all Planar settings. This file contains strategy definitions, exchange configurations, and system preferences.

### Basic Structure

```toml
# Strategy definitions
[StrategyName]
include_file = "strategies/StrategyName.jl"

# Package-based strategies
[sources]
AdvancedStrategy = "strategies/AdvancedStrategy/Project.toml"

# Exchange configurations
[binance]
leveraged = "from"

[bybit]
futures = true
```

### Strategy Configuration

Strategies can be configured in two ways:

#### File-based Strategies

Simple strategies defined in single Julia files:

```toml
[MyStrategy]
include_file = "strategies/MyStrategy.jl"
mode = "Paper"  # Optional: Paper, Live, or Simulation
```

#### Package-based Strategies

Complex strategies organized as Julia packages:

```toml
[sources]
MyAdvancedStrategy = "strategies/MyAdvancedStrategy/Project.toml"
```

### Exchange Configuration

Configure exchange-specific settings for each supported exchange:

```toml
# Binance configuration
[binance]
leveraged = "from"  # Leverage mode: "from", "to", or "both"
sandbox = false     # Use sandbox environment

# Bybit configuration  
[bybit]
futures = true      # Enable futures trading
testnet = false     # Use testnet environment

# KuCoin configuration
[kucoin]
futures = false     # Disable futures trading

# KuCoin Futures (separate configuration)
[kucoinfutures]
futures = true
```

### Execution Mode Configuration

Set default execution modes for strategies:

```toml
[MyStrategy]
include_file = "strategies/MyStrategy.jl"
mode = "Paper"      # Default mode: Paper, Live, or Simulation
```

Available modes:
- **Simulation** - Historical backtesting with no real market connection
- **Paper** - Real-time simulation with live market data but no actual trades
- **Live** - Real trading with actual market orders

## Secrets Management

Sensitive information like API keys and credentials are stored separately in `user/secrets.toml` for security.

### API Keys Structure

```toml
# Exchange API credentials
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

### Third-party Service Keys

For data providers and external services:

```toml
[default]
coinmarketcap_apikey = "your_coinmarketcap_key"
alpha_vantage = "your_alpha_vantage_key"
fred_apikey = "your_fred_api_key"
```

### Security Best Practices

- **Never commit secrets.toml to version control** - Add it to `.gitignore`
- **Use environment-specific keys** - Separate keys for development and production
- **Enable IP restrictions** - Limit API access to your server's IP address
- **Use minimal permissions** - Only enable required trading permissions
- **Rotate keys regularly** - Change API keys periodically for security

## Advanced Configuration

### Multi-Exchange Setup

Configure multiple exchanges for diversified trading:

```toml
# Primary exchange
[binance]
leveraged = "from"
primary = true

# Secondary exchange
[bybit]
futures = true
backup = true

# Spot-only exchange
[kucoin]
futures = false
spot_only = true
```

### Strategy Parameters

Pass parameters to strategies through configuration:

```toml
[MyStrategy]
include_file = "strategies/MyStrategy.jl"
mode = "Paper"

# Strategy-specific parameters
[MyStrategy.params]
risk_level = 0.02
max_positions = 5
rebalance_frequency = "daily"
```

### Data Source Configuration

Configure data fetching and storage:

```toml
[data]
cache_enabled = true
cache_duration = "1h"
default_timeframe = "1m"
max_history_days = 365

[data.sources]
primary = "binance"
backup = ["bybit", "kucoin"]
```

### Logging Configuration

Control logging levels and output:

```toml
[logging]
level = "INFO"  # DEBUG, INFO, WARN, ERROR
file_output = true
console_output = true
log_directory = "user/logs"
```

## Environment Variables

Some settings can be overridden using environment variables:

- `PLANAR_CONFIG_PATH` - Path to custom planar.toml file
- `PLANAR_SECRETS_PATH` - Path to custom secrets.toml file
- `PLANAR_LOG_LEVEL` - Override logging level
- `PLANAR_MODE` - Default execution mode

## Configuration Validation

Planar validates configuration files on startup and provides helpful error messages for common issues:

### Common Configuration Errors

1. **Missing Strategy Files**
   ```
   Error: Strategy file not found: strategies/MyStrategy.jl
   ```

2. **Invalid Exchange Configuration**
   ```
   Error: Unknown exchange configuration key: 'invalid_option'
   ```

3. **Missing API Credentials**
   ```
   Error: API credentials not found for exchange: binance
   ```

### Validation Commands

Test your configuration before running strategies:


## Configuration Examples

### Basic Trading Setup

```toml
# Simple strategy configuration
[MyFirstStrategy]
include_file = "strategies/MyFirstStrategy.jl"
mode = "Paper"

# Single exchange setup
[binance]
leveraged = "from"
```

### Advanced Multi-Strategy Setup

```toml
# Multiple strategies
[TrendFollowing]
include_file = "strategies/TrendFollowing.jl"
mode = "Live"

[MeanReversion]
include_file = "strategies/MeanReversion.jl"
mode = "Paper"

# Package-based strategies
[sources]
ArbitrageBot = "strategies/ArbitrageBot/Project.toml"
GridTrader = "strategies/GridTrader/Project.toml"

# Multiple exchanges
[binance]
leveraged = "from"
primary = true

[bybit]
futures = true
backup = true

[kucoin]
futures = false
spot_only = true
```

## Troubleshooting Configuration

### Common Issues

1. **Configuration File Not Found**
   - Ensure `user/planar.toml` exists in the correct location
   - Check file permissions and accessibility

2. **Invalid TOML Syntax**
   - Validate TOML syntax using online validators
   - Check for missing quotes, brackets, or commas

3. **Strategy Loading Errors**
   - Verify strategy file paths are correct
   - Ensure strategy files contain valid Julia code

4. **API Authentication Failures**
   - Verify API keys in `user/secrets.toml`
   - Check API key permissions on exchange
   - Ensure IP restrictions allow your connection

### Getting Help

If you encounter configuration issues:

1. Check the [troubleshooting guide](troubleshooting/index.md)
2. Review [exchange-specific issues](troubleshooting/exchange-issues.md)
3. Validate your configuration syntax
4. Test with minimal configuration first

## See Also

- [Getting Started Guide](getting-started/installation.md) - Initial setup and installation
- [Strategy Development](guides/../guides/strategy-development.md) - Creating and configuring strategies
- [Exchange Integration](exchanges.md) - Exchange-specific configuration details
- [Troubleshooting](troubleshooting/index.md) - Common configuration problems
- [API Reference](API/api.md) - Configuration API documentation