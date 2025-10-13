---
category: "strategy-development"
difficulty: "advanced"
topics: [execution-modes, margin-trading, exchanges, data-management, optimization, strategy-development, troubleshooting, visualization, configuration]
last_updated: "2025-10-04"---
---

# Running a Backtest

To perform a [backtest](../guides/execution-modes.md#simulationmode), you need to construct a [Strategy Documentation](../[strategy](../guides/strategy-development.md). Once the [strategy](../guides/strategy-development.md) is created, you can call the `start!` function on it to begin the [backtest](../guides/execution-modes.md#simulationmode).

The entry function that is called in all modes is `call!(s::Strategy, ts::DateTime, ctx)`. This function takes three arguments:
- `s`: The strategy object that you have created.
- `ts`: The current date. In live mode, it is very close to `now()`, while in [simulation](../guides/execution-modes.md#simulation-mode) mode, it is the date of the iteration step.
- `ctx`: Additional context information that can be passed to the function.

During the [backtest](../guides/execution-modes.md#simulation-mode), the `call!` function is responsible for executing the strategy's logic at each timestep. It is called repeatedly with updated values of `ts` until the backtest is complete.

It is important to note that the `call!` function should be implemented in your strategy module according to your specific trading logic.

## Backtest Configuration

Before running a backtest, you can configure various parameters to control the simulation behavior:

### Time Range Configuration


### Initial Capital and Position Sizing


### Performance Optimization Settings

For large backtests, consider these [optimization](../optimization.md) settings:


## Basic Example

Here is an example of how to use the `call!` function in a strategy module:


Let's run a backtest.


Our backtest indicates that our strategy:

- Operated on **3 assets** (instances)
- Executed **977 trades**
- Started with **100 USDT** and finished with **32 USDT** in cash, and assets worth **156 USDT**
- The asset with the minimum value at the end was **BTC**, and the one with the maximum value was **XMR**
- At the end, there were **3 open buy orders** and **no open sell orders**.

## Comprehensive Backtest Example

Here's a more detailed example showing a complete [backtesting](../guides/execution-modes.md#simulation-mode) workflow:


## Advanced Backtesting Features

### Multi-Timeframe Backtesting


### Walk-Forward Analysis

# Orders

To place a limit order within your strategy, you call `call!` just like any call to the executor. Here are the arguments:


Where `s` is your `Strategy{Sim, ...}` instance, `ai` is the `AssetInstance` to which the order refers (it should be one present in your `s.universe`). The `amount` is the quantity in base currency and `date` should be the one fed to the `call!` function. During [backtesting](../guides/execution-modes.md#simulation-mode), this would be the current timestamp being evaluated, and during [live trading](../guides/execution-modes.md#live-mode), it would be a recent timestamp. If you look at the example strategy, `ts` is _current_ and `ats` is _available_. The available timestamp `ats` is the one that matches the last candle that doesn't give you forward knowledge. The `date` given to the order call (`call!`) must always be the _current_ timestamp.

A limit order call might return a trade if the order was queued correctly. If the trade hasn't completed the order, the order is queued in `s.buy/sellorders[ai]`. If `isnothing(trade)` is `true`, it means the order failed and was not scheduled. This can happen if the cost of the trade did not meet the asset limits, or there wasn't enough commitable cash. If instead `ismissing(trade)` is `true`, it means that the order was scheduled, but no trade has yet been performed. In backtesting, this happens if the price of the order is too low (buy) or too high (sell) for the current candle high/low prices.

## Limit Order Types

In addition to GTC (Good Till Canceled) orders, there are also IOC (Immediate Or Cancel) and FOK (Fill Or Kill) orders:

- **GTC (Good Till Canceled)**: This order remains active until it is either filled or canceled. Best for [strategies](../guides/strategy-development.md) that can wait for favorable prices.
- **IOC (Immediate Or Cancel)**: This order must be executed immediately. Any portion of the order that cannot be filled immediately will be canceled. Useful for capturing immediate opportunities.
- **FOK (Fill Or Kill)**: This order must be executed in its entirety or not at all. Ideal when you need exact position sizes.

All three are subtypes of a limit order, `<: LimitOrder>`. You can create them by calling `call!` as shown below:


### Comprehensive Order Examples

#### Basic Limit Orders


#### Advanced Order Strategies


#### Order Management Patterns


## Market Order Types

Market order types include:

- **MarketOrder**: This order is executed at the best available price in the market. Use when immediate execution is more important than price.
- **LiquidationOrder**: This order is similar to a MarketOrder, but its execution price might differ from the candle price due to forced liquidation mechanics.
- **ReduceOnlyOrder**: This is a market order that is automatically triggered when manually closing a position. Only reduces existing positions, never increases them.

All of these behave in the same way, except for the LiquidationOrder. For example, a ReduceOnlyOrder is triggered when manually closing a position, as shown below:


### Market Order Examples

#### Basic Market Orders


#### Advanced Market Order Strategies


#### Risk Management with Market Orders


## Market Orders

Although the ccxt library allows setting `timeInForce` for market orders because [exchanges](../exchanges.md) generally permit it, there isn't definitive information about how a market order is handled in these cases. Given that we are dealing with cryptocurrencies, some contexts like open and close times days are lost. It's plausible that `timeInForce` only matters when the order book doesn't have enough liquidity; otherwise, market orders are always _immediate_ and _fully filled_ orders. For this reason, we always consider market orders as FOK orders, and they will always have `timeInForce` set to FOK when executed live (through ccxt) to match the backtester.

!!! warning "Market orders can be surprising"
    Market orders _always_ go through in the backtest. If the candle has no volume, the order incurs in _heavy_ slippage, and the execution price of the trades _can_ exceed the candle high/low price.

## Checks

Before an order is created, several checks are performed to sanitize the values. For instance, if the specified amount is too small, the system will automatically adjust it to the minimum allowable amount. However, if there isn't sufficient cash after this adjustment, the order will fail. For more information on precision and limits, please refer to the [ccxt documentation](http://docs.ccxt.com/#/?id=precision-and-limits).

## Fees

The fees are derived from the `AssetInstance` `fees` property, which is populated by parsing the ccxt data for the specific symbol. Every trade takes these fees into account.

## Slippage

Slippage is factored into the trade execution process. Here's how it works for different types of orders:

- **Limit Orders**: These can only experience positive slippage. When an order is placed and the price moves in your favor, the actual execution price becomes slightly lower (for buy orders) or higher (for sell orders). The slippage formula considers volatility (high/low) and fill ratio (amount/volume). The more volume the order takes from the candle, the lower the positive slippage will be. Conversely, higher volatility leads to higher positive slippage. Positive slippage is only added for candles that move against the order side, meaning it will only be added on red candles for buys, and green candles for sells.

- **Market Orders**: These can only experience negative slippage. There is always a minimum slippage added, which by default corresponds to the difference between open and close prices (other formulas are available, check the API reference). On top of this, additional skew is added based on volume and volatility.

## Liquidations

In [isolated margin](../guides/strategy-development.md#margin-modes) mode, liquidations are triggered by checking the `LIQUIDATION_BUFFER`. You can customize the buffer size by setting the value of the environment variable `PLANAR_LIQUIDATION_BUFFER`. This allows you to adjust the threshold at which liquidations are triggered.

To obtain more accurate estimations, you can utilize the effective funding rate. This can be done by downloading the funding rate history using the `Fetch` module. By analyzing the funding rate history, you can gain insights into the funding costs associated with trading in [isolated margin](../guides/strategy-development.md#margin-modes) mode.

### Liquidation Mechanics

#### Liquidation Buffer Configuration


#### Liquidation Price Calculation


#### Liquidation Risk Management


### Funding Rate Integration



## See Also

- **[Exchanges](../exchanges.md)** - Exchange integration and configuration
- **[Config](../config.md)** - Exchange integration and configuration
- **[Optimization](../optimization.md)** - Performance optimization techniques
- **[Performance Issues](../troubleshooting/performance-issues.md)** - Troubleshooting: Performance optimization techniques
- **[Data Management](../guides/data-management.md)** - Guide: Data handling and management
- **[Exchanges](../exchanges.md)** - Data handling and management

## Backtesting Performance

Local benchmarking indicates that the `:Example` strategy, which employs FOK orders, operates on three assets, trades in spot markets, and utilizes a simple logic (which can be reviewed in the strategy code) to execute orders, currently takes approximately `~8 seconds` to cycle through `~1.3M * 3 (assets) ~= 3.9M candles`, executing `~6000 trades` on a single x86 core.

It's crucial to note that the type of orders executed and the number of trades performed can significantly impact the runtime, aside from other evident factors like additional strategy logic or the number of assets. Therefore, caution is advised when interpreting claims about a backtester's ability to process X rows in Y time without additional context. Furthermore, our order creation logic always ensures that order inputs adhere to the [exchanges](../exchanges.md)'s [limits](https://docs.ccxt.com/#/README?id=precision-and-limits), and we also incorporate slippage and probability calculations, enabling the backtester to be "MC simmable".

Backtesting a strategy with margin will inevitably be slower due to the need to account for all the necessary calculations, such as position states and liquidation triggers.

### Performance Optimization Guidelines

#### Memory Management


#### CPU Optimization


#### I/O Optimization


### Performance Benchmarks

| Strategy Type | Assets | Timeframe | Candles | Trades | Time | Memory |
|---------------|--------|-----------|---------|--------|------|--------|
| Simple MA | 3 | 1h | 3.9M | 6K | 8s | 2GB |
| Complex Multi-TF | 10 | 1h/4h/1d | 12M | 15K | 45s | 6GB |
| Margin Strategy | 5 | 15m | 8M | 25K | 120s | 4GB |
| High-Freq | 1 | 1m | 2M | 50K | 30s | 1GB |

### Profiling and Debugging


### Optimization Recommendations

1. **Data Management**:
   - Use Zarr format for large datasets
   - Implement data chunking for memory efficiency
   - Cache frequently accessed indicators

2. **Strategy Logic**:
   - Minimize allocations in hot paths
   - Use in-place operations where possible
   - Avoid unnecessary calculations in the main loop

3. **Order Processing**:
   - Batch order operations when possible
   - Use appropriate order types for your strategy
   - Consider order frequency impact on performance

4. **Multi-Asset Strategies**:
   - Enable parallel processing for independent assets
   - Balance memory usage vs. processing speed
   - Consider asset correlation in [optimization](../optimization.md)
