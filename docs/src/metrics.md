---
category: "strategy-development"
difficulty: "advanced"
topics: [execution-modes, exchanges, optimization, strategy-development, troubleshooting, visualization]
last_updated: "2025-10-04"---
---

# Metrics Module Documentation

The `Metrics` module provides functions for analyzing the outcomes of [backtest](../guides/execution-modes.md#[simulation](../guides/execution-modes.md#simulation-mode)-mode) runs within the trading [strategy](../guides/strategy-development.md) framework.

### Resampling Trades

Using the [`Metrics.resample_trades`](@ref) function, trades can be resampled to a specified time frame. This aggregates the profit and loss (PnL) of each trade for every asset in the [strategy](../guides/strategy-development.md) over the given period.


In the example above, all trades are resampled to a daily resolution (`1d`), summing the PnL for each asset within the strategy.

### Trade Balance Calculation

The [`Metrics.trades_balance`](@ref) function calculates the cumulative balance over time for a given time frame, using the `cum_total` column as a reference. This function relies on the prior resampling of trades through `resample_trades`.


### Performance Metrics

The module includes implementations of common trading performance [metrics](./API/metrics.md) such as Sharpe ratio (`sharpe`), Sortino ratio (`sortino`), Calmar ratio (`calmar`), and expectancy (`expectancy`).


Each of these functions calculates the respective metric over a daily time frame, with `rfr` representing the risk-free rate, which is an optional parameter for the Sharpe and Sortino ratios.

### Multi-Metric Calculation

To calculate multiple metrics simultaneously, use the `multi` function. It allows for the normalization of results, ensuring metric values are constrained between 0 and 1.


The `normalize` option normalizes the metric values by dividing by a predefined constant and then clipping the results to the range [0, 1].

## See Also

- **[Exchanges](../exchanges.md)** - Exchange integration and configuration
- **[Config](../config.md)** - Exchange integration and configuration
- **[Optimization](../optimization.md)** - Performance optimization techniques
- **[Performance Issues](../troubleshooting/performance-issues.md)** - Troubleshooting: Performance optimization techniques
- **[Strategy Development](../guides/strategy-development.md)** - Guide: Strategy development and implementation
- **[Optimization](../optimization.md)** - Strategy development and implementation
