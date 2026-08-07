## See Also

- **[Optimization](../optimization.md)** - Performance optimization techniques
- **[Performance Issues](../troubleshooting/performance-issues.md)** - Troubleshooting: Performance optimization techniques
- **[Data Management](../guides/data-management.md)** - Guide: Data handling and management
- **[Exchanges](../exchanges.md)** - Data handling and management
- **[Strategy Development](../guides/strategy-development.md)** - Guide: Strategy development and implementation
- **[Optimization](../optimization.md)** - Strategy development and implementation

## High-Frequency Trading (HFT) Backtesting Documentation

The `SimMode` class, also known as the planar backtester, utilizes Open-High-Low-Close-Volume ([OHLCV](../guides/data-management.md#Data-Collection-Methods)) data to simulate the execution of trades.

### Reasons to Avoid Tick-by-Tick Backtesting
Tick-by-tick backtesting may not be ideal due to several factors:
- **Data Availability**: Bid/ask tick data is often difficult to obtain and can be extremely voluminous, leading to increased resource consumption.
- **Data Reconstruction**: Attempting to reconstruct order book data from trade history is speculative and can introduce significant bias.
- **Overfitting Risks**: High-detail backtesting can cause strategies to overfit to specific market maker behaviors, resulting in additional bias.
- **Computational Costs**: Intensive data and computational requirements may limit backtesting to a short time frame, insufficient for evaluating performance through different market conditions.

### Implementing HFT Backtesting
Two approaches are available for HFT-style backtesting.

#### Built-in Tick-Based Backtesting
`SimMode` ships with a tick-based backtester that replays the market's trade stream trade by trade — no new execution mode is needed. See [Running a Backtest → Tick-by-Tick Backtesting](../engine/backtesting.md#Tick-by-Tick-Backtesting) for the full details. In short:

- Each universe asset needs a tick `DataFrame` with `:timestamp`, `:price`, `:amount` columns (the schema returned by `Planar.Fetch.fetch_trades`), stored with `Planar.Instances.setticks!`.
- The strategy implements `ping!(s, ctx, tick)` instead of `call!`.
- The backtest runs with:

```julia
ctx = TickContext(Sim(), TradeTickRange(s))
start!(s, ctx)
```

#### [OHLCV](../guides/data-management.md#Data-Collection-Methods)-Based Approach
- A simpler method involves using the [OHLCV](../guides/data-management.md#Data-Collection-Methods) model with extremely short-duration candles, such as `1s` candles. The backtester processes time steps, typically using the [strategy](../guides/strategy-development.md)'s base [timeframe](../guides/data-management.md#Timeframe-Management). By selecting a `1s` [timeframe](../guides/data-management.md#Timeframe-Management) and supplying the corresponding candles, you can achieve the desired time resolution for your [backtest](../guides/execution-modes.md#Simulation-Mode).
