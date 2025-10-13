---
category: "strategy-development"
difficulty: "advanced"
topics: [execution-modes, data-management, optimization, strategy-development, troubleshooting]
last_updated: "2025-10-04"---
---

## See Also

- **[Optimization](../optimization.md)** - Performance optimization techniques
- **[Performance Issues](../troubleshooting/performance-issues.md)** - Troubleshooting: Performance optimization techniques
- **[Data Management](../guides/data-management.md)** - Guide: Data handling and management
- **[Exchanges](../exchanges.md)** - Data handling and management
- **[Strategy Development](../guides/strategy-development.md)** - Guide: Strategy development and implementation
- **[Optimization](../optimization.md)** - Strategy development and implementation

## High-Frequency Trading (HFT) Backtesting Documentation

The `SimMode` class, also known as the planar backtester, utilizes Open-High-Low-Close-Volume ([OHLCV](../guides/data-management.md#ohlcv-data)) data to simulate the execution of trades.

### Reasons to Avoid Tick-by-Tick Backtesting
Tick-by-tick backtesting may not be ideal due to several factors:
- **Data Availability**: Bid/ask tick data is often difficult to obtain and can be extremely voluminous, leading to increased resource consumption.
- **Data Reconstruction**: Attempting to reconstruct order book data from trade history is speculative and can introduce significant bias.
- **Overfitting Risks**: High-detail backtesting can cause strategies to overfit to specific market maker behaviors, resulting in additional bias.
- **Computational Costs**: Intensive data and computational requirements may limit backtesting to a short time frame, insufficient for evaluating performance through different market conditions.

### Implementing HFT Backtesting
Should you decide to implement HFT backtesting, consider the following two approaches:

#### [OHLCV](../guides/data-management.md#ohlcv-data)-Based Approach
- A simpler method involves using the [OHLCV](../guides/data-management.md#ohlcv-data) model with extremely short-duration candles, such as `1s` candles. The backtester processes time steps, typically using the [strategy](../guides/strategy-development.md)'s base [timeframe](../guides/data-management.md#timeframes). By selecting a `1s` [timeframe](../guides/data-management.md#timeframes) and supplying the corresponding candles, you can achieve the desired time resolution for your [backtest](../guides/execution-modes.md#simulation-mode).

#### Tick-Based Approach
- A more complex method requires developing a new execution mode, which could be named `TickSimMode`. This involves adapting the `[backtest](../guides/execution-modes.md#simulation-mode)!` function to handle tick data. While order creation logic may remain largely unchanged, functions like `volumeat(ai, date)` or `openat, closeat`, which currently fetch candle data, need to be modified. These functions should be tailored to compute the trade's actual price and volume from the tick data. This is analogous to customizing functions such as `limitorder_ifprice!` to work with tick data.
- If you have access to full trades history, then you can reconstruct the orderbook (not implemented), and then the execution logic of `PaperMode` can be repurposed for the tick based backtester because it already operates with orderbook data.

\```example
/ Example of setting up a 1-second OHLCV [backtest](../guides/execution-modes.md#simulation-mode)
/ Note: Actual implementation details will vary based on your specific backtesting framework
SimMode backtester = new SimMode("1s");
backtester.loadData("path/to/1s_candle_data.csv");
backtester.run();
\```
