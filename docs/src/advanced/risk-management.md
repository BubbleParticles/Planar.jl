# Risk Management

Risk management controls protect capital across strategy development, paper testing, and live trading. Planar exposes risk parameters through strategy configuration and expects layered controls before deploying with real funds.

## Position Sizing

Size positions conservatively, especially when transitioning between modes. The `risk_level` parameter in `[MyStrategy.params]` caps the fraction of capital committed per position:

```toml
[MyStrategy]
include_file = "strategies/MyStrategy.jl"
mode = "Paper"

[MyStrategy.params]
risk_level = 0.02
max_positions = 5
```

`risk_level` limits the fraction of capital allocated to a single position, and `max_positions` limits the number of concurrently open positions. Combined, they bound total market exposure.

## Stop Losses

Implement multiple layers of stop-loss protection:

- **Strategy-level stops** that close a position when price moves against it by a fixed percentage
- **Exchange-level stop orders** (see the [order types](../engine/backtesting.md#Limit-Order-Types) documentation) as a backstop when the strategy process is unavailable
- **Time-based exits** that close positions that have not behaved as expected within a window

## Diversification

Avoid concentrating positions in correlated assets. Spread exposure across uncorrelated markets, and consider a [multi-exchange setup](../exchanges.md) to reduce single-point-of-failure risk.

## Capital Limits

Set strict daily and total loss limits and enforce them in code:

- A daily loss cap that stops trading for the day once reached
- A maximum drawdown threshold that pauses the strategy and alerts the operator
- A maximum deployed capital fraction, ramped up gradually

## Margin and Leverage

When trading margin, keep liquidation distance in mind. The margin mode is set per strategy (`NoMargin`, `Isolated`, or `Cross` — see [Margin Trading](../guides/strategy-development.md#Margin-Trading-Concepts)), and the `leveraged` exchange option controls which sides may use leverage:

```toml
[binance]
leveraged = "from"  # "from", "to", or "both"
```

Planar adjusts the [liquidation buffer](../engine/backtesting.md#Liquidations) through the `PLANAR_LIQUIDATION_BUFFER` environment variable. In [isolated margin](../guides/strategy-development.md#Margin-Modes) mode, positions are liquidated when equity falls below the buffer threshold.

## Emergency Procedures

Have clear emergency stop procedures before going live:

- A single documented `call!` path that closes all open positions and cancels open orders
- Exchange-level API key revocation as the last resort: revoke the keys, then remove the exchange credentials from `user/secrets.toml`
- A monitoring contact who is alerted when the strategy stops responding

## See Also

- **[Execution Modes](../guides/execution-modes.md)** - Mode transitions and the per-mode risk management checklist
- **[Live Trading](../engine/live.md)** - What changes when real capital is at stake
- **[Monitoring](../guides/monitoring.md)** - Watching watchers and live background tasks
- **[Strategy Development](../guides/strategy-development.md)** - Margin concepts and position management
