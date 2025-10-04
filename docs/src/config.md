---
category: "getting-started"
difficulty: "advanced"
topics: [exchanges, troubleshooting, getting-started, strategy-development, configuration]
last_updated: "2025-10-04"---
---

The bot is configured using a file named `user/[planar.toml](../config.md#[configuration](../config.md)-file)`, which serves as the default [configuration](../config.md) file. This file typically contains:

- Minor [exchange](../[exchanges](../exchanges.md).md) configurations, which are referenced using the `ExchangeID` symbol as the key for the [exchange](../[exchanges](../exchanges.md).md)'s config section.
- Strategy settings, where the [strategy](../guides/strategy-development.md) module's name is used as the section key. Each [strategy](../guides/strategy-development.md) section may include:
  - `include_file`: Specifies the path to the [strategy](../guides/strategy-development.md)'s entry file.
  - `margin`: Defines the margin mode used when initializing the strategy.

It is generally unnecessary to populate the [configuration](../config.md) file with numerous options, as most settings should be predefined as constants within the strategy's module. This design helps to prevent confusion that could arise from a combination of config options and strategy constants potentially conflicting with each other.

Exchange [API keys](../getting-started/installation.md#api-configuration) are stored in dedicated files named following the pattern `\${ExchangeID}[_sandbox].json`. The `_sandbox` suffix is added for keys associated with sandbox endpoints. By default, [exchanges](../exchanges.md) are initiated in sandbox mode. In scenarios where an [exchange](../exchanges.md) does not offer a sandbox environment, the `sandbox` parameter must be explicitly set to `false` when calling the exchange creation function. Here's an example of such a call:

```julia
getexchange!(:okx, sandbox=false)
```

**⚠️ API authentication issues?** See [Exchange Issues: API Authentication](../troubleshooting/exchange-issues.md#api-authentication-issues) for credential setup and troubleshooting.

For third-party applications within the `Watchers` module, the configuration is managed via a separate file named `[secrets.toml](../config.md#secrets-management)`.

## See Also

- **[Installation](../getting-started/installation.md)** - Initial setup and configuration
- **[Strategy Development](../guides/strategy-development.md)** - Strategy-specific configuration
- **[](../troubleshooting/)** - Configuration troubleshooting
- **[Exchanges](../exchanges.md)** - Exchange integration and configuration
- **[Optimization](../optimization.md)** - Strategy development and implementation
- **[Installation Issues](../troubleshooting/installation-issues.md)** - Troubleshooting: Installation and setup guidance
