# Configuration Reference

Planar is configured through TOML files plus environment variables. The full guide is in [Configuration](../config.md); this page is a quick reference.

## Files

| Path | Purpose |
|------|---------|
| `user/planar.toml` | Strategies, exchanges, data sources, logging |
| `user/secrets.toml` | API keys and credentials (never commit to version control) |

## Environment Variables

| Variable | Effect |
|----------|--------|
| `PLANAR_CONFIG_PATH` | Path to a custom `planar.toml` |
| `PLANAR_SECRETS_PATH` | Path to a custom `secrets.toml` |
| `PLANAR_LOG_LEVEL` | Override the logging level |
| `PLANAR_MODE` | Default execution mode |

## Strategy Entries

```toml
[MyStrategy]
include_file = "strategies/MyStrategy.jl"
mode = "Paper"  # Paper, Live, or Simulation

[MyStrategy.params]  # strategy-specific parameters
risk_level = 0.02
max_positions = 5
```

Package-based strategies are registered under `[sources]`:

```toml
[sources]
AdvancedStrategy = "strategies/AdvancedStrategy/Project.toml"
```

## Exchange Entries

```toml
[binance]
leveraged = "from"  # "from", "to", or "both"
sandbox = false

[bybit]
futures = true
testnet = false
```

## Data and Logging

```toml
[data]
cache_enabled = true
cache_duration = "1h"
default_timeframe = "1m"

[logging]
level = "INFO"  # DEBUG, INFO, WARN, ERROR
```

## Secrets

```toml
[exchanges.binance]
apiKey = "..."
secret = "..."
```

See [Secrets Management](../config.md#Secrets-Management) for the full structure and security best practices.

## See Also

- **[Configuration Guide](../config.md)** - Full documentation
- **[Installation Guide](../getting-started/installation.md)** - First-time setup
- **[Getting Started](../getting-started/index.md)** - Begin here
