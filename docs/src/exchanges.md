---
category: "strategy-development"
difficulty: "intermediate"
topics: [execution-modes, exchanges, data-management, troubleshooting, getting-started, strategy-development, configuration]
last_updated: "2025-10-04"---
---

# Exchanges

Every trade, order, asset instance, and [strategy](../guides/strategy-development.md) is parameterized against an `ExchangeID`, which is a type constructed from the name (`Symbol`) of an [exchange](../[exchanges](../exchanges.md).md). Currently, the bot supports [CCXT](../[exchanges](../exchanges.md).md#ccxt-integration) with [exchanges](../exchanges.md) subtypes of `CcxtExchange`.

There is only one [exchange](../exchanges.md) instance (one sandbox and one non-sandbox) constructed per [exchange](../exchanges.md), so calling [`Planar.Engine.Exchanges.getexchange!`](@ref) will always return the same object for each exchange (w.r.t. `sandbox` and `account` options). The sandbox instance is generally a test-net with synthetic markets. The account name indicates which api keys to use.

We try to parse as much info from the ([CCXT](../exchanges.md#ccxt-integration)) exchange such that we can fill attributes such as:
- Markets
- Timeframes
- Asset trading fees, limits, precision
- Funding rates

The support for exchanges is a best-effort basis. To overview if the exchange is likely compatible with the bot, call `check`:

``` julia
using Planar
@environment!
e = getexchange!(:bybit)
exs.check(e, type=:basic) # for [backtesting](../guides/execution-modes.md#[simulation](../guides/execution-modes.md#simulation-mode)-mode) and [paper trading](../guides/execution-modes.md#paper-mode)
exs.check(e, type=:live) # for live support
```

The bot tries to use the WebSocket API if available, otherwise, it falls back to the basic REST API. The [API keys](../getting-started/installation.md#api-[configuration](../config.md)) are read from a file in the `user/` directory named after the exchange name like `user/bybit.json` for the Bybit exchange or `user/bybit_sandbox.json` for the respective sandbox [API keys](../getting-started/installation.md#api-[configuration](../config.md)). The JSON file has to contain the fields `apiKey`, `secret`, and `password`.

**⚠️ Connection problems?** See [Exchange Issues](../troubleshooting/exchange-issues.md) for solutions to API authentication, connectivity, and trading operation problems.

The [strategy](../guides/strategy-development.md) quote currency and each asset currency is a subtype of [`Planar.Engine.Exchanges.CurrencyCash`](@ref), which is a `Number` where operations respect the precision defined by the exchange.

Some commonly fetched information is cached with a TTL, like tickers, markets, and balances.

## Exchange Types
Basic exchange types, and global exchange vars.

```@autodocs; canonical=false
Modules = [Planar.Exchanges.ExchangeTypes]
```

## Construct and query exchanges

Helper module for downloading data off exchanges.
```@autodocs; canonical=false
Modules = [Planar.Engine.Exchanges]
Pages = ["exchanges.jl", "tickers.jl", "-data.jl"]
```


## See Also

- **[Data Management](../guides/data-management.md)** - Fetch data from exchanges
- **[Config](../config.md)** - Configure exchange connections
- **[Exchange Issues](../troubleshooting/exchange-issues.md)** - Solve exchange connectivity problems
- **[Strategy Development](../guides/strategy-development.md)** - Guide: Strategy development and implementation
- **[Optimization](../optimization.md)** - Strategy development and implementation
- **[Execution Modes](../guides/execution-modes.md)** - Guide: Backtesting and simulation

## Fetching data from exchanges

Helper module for downloading data off exchanges.
```@autodocs; canonical=false
Modules = [Fetch]
```

[1]: It is possible that in the future the bot will work with the hummingbot gateway for DEX support, and at least another exchange type natively implemented (from psydyllic).
