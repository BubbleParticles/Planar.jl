---
category: "strategy-development"
difficulty: "advanced"
topics: [execution-modes, margin-trading, exchanges, data-management, optimization, strategy-development, troubleshooting, visualization, configuration]
last_updated: "2025-10-04"---
---

# Running in Paper Mode

Paper mode provides a realistic [simulation](../guides/execution-modes.md#simulation-mode) environment that uses live [market data](../guides/../guides/../guides/data-management.md) while simulating order execution. This allows you to test [strategies](../guides/../guides/strategy-development.md) with real market conditions without risking actual capital.

## Configuration Options

In order to configure a [strategy](../guides/../guides/strategy-development.md) in paper mode, you can define the default mode in `user/[planar.toml](../config.md#configuration)-file)` or in your [strategy](../guides/../guides/strategy-development.md) project's `Project.toml` file. Alternatively, pass the mode as a keyword argument:

### Configuration via TOML Files

```toml
# user/[planar.toml](../config.md#configuration)-file)
[Example]
mode = "Paper"
[exchange]([exchanges](../exchanges.md).md) = "binance"
throttle = 5  # seconds between [strategy](../guides/../guides/strategy-development.md) calls
initial_cash = 10000.0
```

```toml
# Strategy Project.toml
[strategy]
mode = "Paper"
sandbox = true  # Use [exchange]([exchanges](../exchanges.md).md) sandbox/testnet
```

### Configuration via [Julia](https://julialang.org/) Code


## Starting Paper Mode

To start the strategy, use the following command:


### Advanced Startup Options


Upon executing this, the following log output is expected:


### Background Execution

To run the strategy as a background task:


The logs will be written either to the `s[:logfile]` key of the strategy object, if present, or to the output of the `runlog(s)` command.

### Log Management


## Comprehensive Setup Examples

### Basic Spot Trading Setup


### Advanced Margin Trading Setup


### Multi-Exchange Paper Trading


# Understanding Paper Mode

When you initiate paper mode, asset prices are monitored in real-time from the exchange. Order execution in Paper Mode is similar to SimMode, albeit the actual price, the trade amount, and the order execution sequence are guided by real-time exchange data.

## Order Execution Mechanics

### Market Orders
- **Market Orders** are executed by surveying the order book and sweeping available bids/asks. Consequently, the final price and amount reflect the average of all the entries available on the order book.
- Execution includes realistic slippage based on order book depth
- Large orders may experience partial fills across multiple price levels

### Limit Orders  
- **Limit Orders** sweep the order book as well, though only for bids/asks that are below the limit price set for the order. If a Good-Till-Canceled (GTC) order is not entirely filled, a task is generated that continuously monitors the exchange's trade history. Trades that align with the order's limit price are used to fulfill the remainder of the limit order amount.
- Orders are queued and filled based on real market movements
- Partial fills are handled realistically based on market liquidity

## Real-Time Data Integration

### Price Feeds

### Order Book Integration

## Performance Monitoring

### Real-Time Metrics


## See Also

- **[Exchanges](../exchanges.md)** - Exchange integration and configuration
- **[Config](../config.md)** - Exchange integration and configuration
- **[Optimization](../optimization.md)** - Performance optimization techniques
- **[Performance Issues](../troubleshooting/performance-issues.md)** - Troubleshooting: Performance optimization techniques
- **[Data Management](../guides/../guides/../guides/data-management.md)** - Guide: Data handling and management
- **[Exchanges](../exchanges.md)** - Data handling and management

## Risk Management in Paper Mode

### Position Sizing

### Stop Loss Management