---
category: "strategy-development"
difficulty: "advanced"
topics: [execution-modes, margin-trading, exchanges, data-management, optimization, strategy-development, troubleshooting, visualization, configuration]
last_updated: "2025-10-04"---
---

# Running a Backtest

To perform a [backtest](../guides/execution-modes.md#[simulation](../guides/execution-modes.md#simulation-mode)-mode), you need to construct a [strategy](../guides/strategy-development.md) by following the guidelines in the [Strategy Documentation](../[strategy](../guides/strategy-development.md).md). Once the [strategy](../guides/strategy-development.md) is created, you can call the `start!` function on it to begin the [backtest](../guides/execution-modes.md#[simulation](../guides/execution-modes.md#simulation-mode)-mode).

The entry function that is called in all modes is `call!(s::Strategy, ts::DateTime, ctx)`. This function takes three arguments:
- `s`: The strategy object that you have created.
- `ts`: The current date. In live mode, it is very close to `now()`, while in [simulation](../guides/execution-modes.md#simulation-mode) mode, it is the date of the iteration step.
- `ctx`: Additional context information that can be passed to the function.

During the [backtest](../guides/execution-modes.md#simulation-mode), the `call!` function is responsible for executing the strategy's logic at each timestep. It is called repeatedly with updated values of `ts` until the backtest is complete.

It is important to note that the `call!` function should be implemented in your strategy module according to your specific trading logic.

## Backtest Configuration

Before running a backtest, you can configure various parameters to control the simulation behavior:

### Time Range Configuration

```julia
# Set specific date range for [backtesting](../guides/execution-modes.md#simulation-mode)
s = strategy(:Example)
# Configure backtest period
s.config.start_date = DateTime("2023-01-01")
s.config.end_date = DateTime("2023-12-31")
```

### Initial Capital and Position Sizing

```julia
# Configure initial capital and base position size
s.config.initial_cash = 10000.0  # USDT
s.config.base_size = 100.0       # Base order size in USDT
```

### Performance Optimization Settings

For large backtests, consider these [optimization](../optimization.md) settings:

```julia
# Enable parallel processing for multi-asset [strategies](../guides/strategy-development.md)
s.config.parallel = true

# Adjust memory usage for large datasets
s.config.chunk_size = 10000  # Process data in chunks

# Enable progress reporting
s.config.show_progress = true
```

## Basic Example

Here is an example of how to use the `call!` function in a strategy module:

```julia
module ExampleStrategy

# Define the call! function
call!(s::Strategy, ts::DateTime, ctx) = begin
    # Insert your trading logic here
end

end
```

Let's run a backtest.

```julia
using Engine.Strategies
using Engine.Executors: SimMode as sm
s = strategy(:Example)
# Load data in the strategy universe (you need to already have it)
fill!(s) # or stub!(s.universe, datadict)
# backtest the strategy within the period available from the loaded data.
sm.start!(s)
# Lets see how we fared:
display(s)
## output
Name: Example
Config: 10.0(USDT)(Base Size), 100.0(USDT)(Initial Cash)
Universe: 3 instances, 1 [exchanges](../exchanges.md)
Holdings: assets(trades): 2(977), min BTC: 23.13(USDT), max XMR: 79.611(USDT)
Pending buys: 3
Pending sells: 0
USDT: 32.593 (Cash)
USDT: 156.455 (Total)
```

Our backtest indicates that our strategy:

- Operated on **3 assets** (instances)
- Executed **977 trades**
- Started with **100 USDT** and finished with **32 USDT** in cash, and assets worth **156 USDT**
- The asset with the minimum value at the end was **BTC**, and the one with the maximum value was **XMR**
- At the end, there were **3 open buy orders** and **no open sell orders**.

## Comprehensive Backtest Example

Here's a more detailed example showing a complete [backtesting](../guides/execution-modes.md#simulation-mode) workflow:

```julia
using Engine.Strategies
using Engine.Executors: SimMode as sm
using Data
using Metrics

# Create and configure strategy
s = strategy(:MovingAverageCrossover)

# Configure backtest parameters
s.config.initial_cash = 10000.0
s.config.base_size = 100.0
s.config.start_date = DateTime("2023-01-01")
s.config.end_date = DateTime("2023-06-30")

# Load historical data
universe = [:BTC, :ETH, :ADA]
for asset in universe
    data = fetch_ohlcv(asset, "1h", s.config.start_date, s.config.end_date)
    load_data!(s, asset, data)
end

# Fill strategy universe with data
fill!(s)

# Run backtest with progress monitoring
@time sm.start!(s)

# Analyze results
println("=== Backtest Results ===")
display(s)

# Calculate performance metrics
returns = calculate_returns(s)
sharpe_ratio = calculate_sharpe(returns)
max_drawdown = calculate_max_drawdown(s)

println("\n=== Performance Metrics ===")
println("Total Return: $(round(total_return(s) * 100, digits=2))%")
println("Sharpe Ratio: $(round(sharpe_ratio, digits=3))")
println("Max Drawdown: $(round(max_drawdown * 100, digits=2))%")
println("Number of Trades: $(length(s.trades))")
println("Win Rate: $(round(win_rate(s) * 100, digits=2))%")
```

## Advanced Backtesting Features

### Multi-Timeframe Backtesting

```julia
# Configure multiple [timeframes](../guides/data-management.md#timeframes) for analysis
s.config.primary_timeframe = "1h"
s.config.secondary_timeframes = ["4h", "1d"]

# Load data for different [timeframes](../guides/data-management.md#timeframes)
for tf in [s.config.primary_timeframe; s.config.secondary_timeframes]
    for asset in s.universe
        data = fetch_ohlcv(asset, tf, s.config.start_date, s.config.end_date)
        load_data!(s, asset, data, [timeframe](../guides/data-management.md#timeframes)=tf)
    end
end
```

### Walk-Forward Analysis

```julia
# Perform walk-forward analysis
function walk_forward_backtest(strategy_name, start_date, end_date, window_months=3)
    results = []
    current_date = start_date
    
    while current_date < end_date
        window_end = current_date + Month(window_months)
        
        s = strategy(strategy_name)
        s.config.start_date = current_date
        s.config.end_date = min(window_end, end_date)
        
        fill!(s)
        sm.start!(s)
        
        push!(results, (
            period = (current_date, s.config.end_date),
            return = total_return(s),
            trades = length(s.trades),
            sharpe = calculate_sharpe(calculate_returns(s))
        ))
        
        current_date = window_end
    end
    
    return results
end

# Run walk-forward analysis
wf_results = walk_forward_backtest(:Example, DateTime("2023-01-01"), DateTime("2023-12-31"))
```
# Orders

To place a limit order within your strategy, you call `call!` just like any call to the executor. Here are the arguments:

```julia
trade = call!(s, GTCOrder{Buy}, ai; price, amount, date=ts)
```

Where `s` is your `Strategy{Sim, ...}` instance, `ai` is the `AssetInstance` to which the order refers (it should be one present in your `s.universe`). The `amount` is the quantity in base currency and `date` should be the one fed to the `call!` function. During [backtesting](../guides/execution-modes.md#simulation-mode), this would be the current timestamp being evaluated, and during [live trading](../guides/execution-modes.md#live-mode), it would be a recent timestamp. If you look at the example strategy, `ts` is _current_ and `ats` is _available_. The available timestamp `ats` is the one that matches the last candle that doesn't give you forward knowledge. The `date` given to the order call (`call!`) must always be the _current_ timestamp.

A limit order call might return a trade if the order was queued correctly. If the trade hasn't completed the order, the order is queued in `s.buy/sellorders[ai]`. If `isnothing(trade)` is `true`, it means the order failed and was not scheduled. This can happen if the cost of the trade did not meet the asset limits, or there wasn't enough commitable cash. If instead `ismissing(trade)` is `true`, it means that the order was scheduled, but no trade has yet been performed. In backtesting, this happens if the price of the order is too low (buy) or too high (sell) for the current candle high/low prices.

## Limit Order Types

In addition to GTC (Good Till Canceled) orders, there are also IOC (Immediate Or Cancel) and FOK (Fill Or Kill) orders:

- **GTC (Good Till Canceled)**: This order remains active until it is either filled or canceled. Best for [strategies](../guides/strategy-development.md) that can wait for favorable prices.
- **IOC (Immediate Or Cancel)**: This order must be executed immediately. Any portion of the order that cannot be filled immediately will be canceled. Useful for capturing immediate opportunities.
- **FOK (Fill Or Kill)**: This order must be executed in its entirety or not at all. Ideal when you need exact position sizes.

All three are subtypes of a limit order, `<: LimitOrder>`. You can create them by calling `call!` as shown below:

```julia
trade = call!(s, IOCOrder{Buy}, ai; price, amount, date=ts)
trade = call!(s, FOKOrder{Sell}, ai; price, amount, date=ts)
```

### Comprehensive Order Examples

#### Basic Limit Orders

```julia
# Place a GTC buy order at support level
support_price = current_price * 0.95
trade = call!(s, GTCOrder{Buy}, ai; 
    price=support_price, 
    amount=s.config.base_size, 
    date=ts
)

# Place a GTC sell order at resistance
resistance_price = current_price * 1.05
trade = call!(s, GTCOrder{Sell}, ai; 
    price=resistance_price, 
    amount=position_size, 
    date=ts
)
```

#### Advanced Order Strategies

```julia
# Ladder orders - multiple orders at different price levels
function place_buy_ladder(s, ai, base_price, levels=5, spacing=0.01)
    trades = []
    for i in 1:levels
        price = base_price * (1 - i * spacing)
        amount = s.config.base_size / levels
        
        trade = call!(s, GTCOrder{Buy}, ai; 
            price=price, 
            amount=amount, 
            date=ts
        )
        push!(trades, trade)
    end
    return trades
end

# Scale-in strategy with IOC orders
function scale_in_position(s, ai, target_amount, max_slippage=0.002)
    remaining = target_amount
    filled_amount = 0.0
    
    while remaining > s.config.min_order_size && filled_amount < target_amount
        # Try to fill immediately with IOC
        chunk_size = min(remaining, s.config.base_size)
        max_price = current_price(ai) * (1 + max_slippage)
        
        trade = call!(s, IOCOrder{Buy}, ai; 
            price=max_price, 
            amount=chunk_size, 
            date=ts
        )
        
        if !isnothing(trade) && !ismissing(trade)
            filled_amount += trade.amount
            remaining -= trade.amount
        else
            break  # No more liquidity available
        end
    end
    
    return filled_amount
end
```

#### Order Management Patterns

```julia
# Cancel and replace strategy
function update_order_price(s, ai, old_order, new_price)
    # Cancel existing order
    cancel!(s, old_order)
    
    # Place new order at updated price
    new_trade = call!(s, GTCOrder{typeof(old_order.side)}, ai;
        price=new_price,
        amount=old_order.amount,
        date=ts
    )
    
    return new_trade
end

# Conditional order placement
function place_conditional_order(s, ai, condition_func, order_params...)
    if condition_func(s, ai, ts)
        return call!(s, order_params...)
    end
    return nothing
end

# Example: Place buy order only if [RSI](../guides/strategy-development.md#technical-indicators) is oversold
rsi_condition = (s, ai, ts) -> calculate_rsi(ai, ts) < 30
trade = place_conditional_order(s, ai, rsi_condition, 
    GTCOrder{Buy}, ai; price=current_price * 0.98, amount=100.0, date=ts
)
```

## Market Order Types

Market order types include:

- **MarketOrder**: This order is executed at the best available price in the market. Use when immediate execution is more important than price.
- **LiquidationOrder**: This order is similar to a MarketOrder, but its execution price might differ from the candle price due to forced liquidation mechanics.
- **ReduceOnlyOrder**: This is a market order that is automatically triggered when manually closing a position. Only reduces existing positions, never increases them.

All of these behave in the same way, except for the LiquidationOrder. For example, a ReduceOnlyOrder is triggered when manually closing a position, as shown below:

```julia
call!(s, ai, Long(), now(), PositionClose())
```

### Market Order Examples

#### Basic Market Orders

```julia
# Emergency exit - market sell all positions
for ai in s.universe
    if has_position(s, ai)
        position_size = get_position_size(s, ai)
        trade = call!(s, MarketOrder{Sell}, ai; 
            amount=position_size, 
            date=ts
        )
    end
end

# Quick entry on breakout
if price_breakout_detected(ai, ts)
    trade = call!(s, MarketOrder{Buy}, ai; 
        amount=s.config.base_size, 
        date=ts
    )
end
```

#### Advanced Market Order Strategies

```julia
# TWAP (Time-Weighted Average Price) execution
function execute_twap(s, ai, total_amount, duration_minutes=60)
    intervals = 12  # Execute every 5 minutes
    amount_per_interval = total_amount / intervals
    interval_duration = duration_minutes / intervals
    
    for i in 1:intervals
        # Wait for next interval (in [live trading](../guides/execution-modes.md#live-mode))
        if i > 1
            sleep(interval_duration * 60)  # Convert to seconds
        end
        
        trade = call!(s, MarketOrder{Buy}, ai; 
            amount=amount_per_interval, 
            date=ts + Minute(i * interval_duration)
        )
        
        # Log execution
        @info "TWAP execution $i/$intervals: $(trade.amount) at $(trade.price)"
    end
end

# VWAP (Volume-Weighted Average Price) execution
function execute_vwap(s, ai, total_amount, volume_threshold=0.1)
    executed_amount = 0.0
    
    while executed_amount < total_amount
        current_volume = get_current_volume(ai, ts)
        max_order_size = current_volume * volume_threshold
        
        order_size = min(
            total_amount - executed_amount,
            max_order_size,
            s.config.max_order_size
        )
        
        if order_size >= s.config.min_order_size
            trade = call!(s, MarketOrder{Buy}, ai; 
                amount=order_size, 
                date=ts
            )
            
            if !isnothing(trade)
                executed_amount += trade.amount
            end
        end
        
        # Wait for next volume update
        ts += Minute(1)
    end
end
```

#### Risk Management with Market Orders

```julia
# Stop-loss with market orders
function implement_stop_loss(s, ai, stop_loss_pct=0.05)
    if has_position(s, ai)
        entry_price = get_position_entry_price(s, ai)
        current_price = get_current_price(ai, ts)
        position_size = get_position_size(s, ai)
        
        # Calculate stop loss level
        if is_long_position(s, ai)
            stop_price = entry_price * (1 - stop_loss_pct)
            if current_price <= stop_price
                # Execute stop loss
                trade = call!(s, MarketOrder{Sell}, ai; 
                    amount=position_size, 
                    date=ts
                )
                @warn "Stop loss triggered for $ai at $current_price"
            end
        else  # Short position
            stop_price = entry_price * (1 + stop_loss_pct)
            if current_price >= stop_price
                # Execute stop loss (buy to cover)
                trade = call!(s, MarketOrder{Buy}, ai; 
                    amount=abs(position_size), 
                    date=ts
                )
                @warn "Stop loss triggered for $ai at $current_price"
            end
        end
    end
end

# Trailing stop with market orders
function implement_trailing_stop(s, ai, trail_pct=0.03)
    if has_position(s, ai) && is_long_position(s, ai)
        current_price = get_current_price(ai, ts)
        highest_price = get_highest_price_since_entry(s, ai)
        
        # Update highest price
        if current_price > highest_price
            set_highest_price_since_entry!(s, ai, current_price)
            highest_price = current_price
        end
        
        # Check trailing stop
        trail_stop_price = highest_price * (1 - trail_pct)
        if current_price <= trail_stop_price
            position_size = get_position_size(s, ai)
            trade = call!(s, MarketOrder{Sell}, ai; 
                amount=position_size, 
                date=ts
            )
            @info "Trailing stop triggered for $ai at $current_price"
        end
    end
end
```

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

```julia
# Set liquidation buffer (default: 0.02 = 2%)
ENV["PLANAR_LIQUIDATION_BUFFER"] = "0.015"  # 1.5% buffer

# Or configure in strategy
s.config.liquidation_buffer = 0.015
```

#### Liquidation Price Calculation

```julia
# Calculate liquidation price for long position
function calculate_liquidation_price_long(entry_price, [leverage](../guides/strategy-development.md#margin-modes), buffer=0.02)
    liquidation_price = entry_price * (1 - (1/[leverage](../guides/strategy-development.md#margin-modes)) + buffer)
    return liquidation_price
end

# Calculate liquidation price for short position  
function calculate_liquidation_price_short(entry_price, [leverage](../guides/strategy-development.md#margin-modes), buffer=0.02)
    liquidation_price = entry_price * (1 + (1/leverage) - buffer)
    return liquidation_price
end

# Example usage
entry_price = 50000.0
leverage = 10.0
liq_price_long = calculate_liquidation_price_long(entry_price, leverage)
liq_price_short = calculate_liquidation_price_short(entry_price, leverage)

println("Long liquidation price: $liq_price_long")
println("Short liquidation price: $liq_price_short")
```

#### Liquidation Risk Management

```julia
# Monitor liquidation risk
function check_liquidation_risk(s, ai)
    if has_margin_position(s, ai)
        current_price = get_current_price(ai, ts)
        liquidation_price = get_liquidation_price(s, ai)
        
        # Calculate distance to liquidation
        if is_long_position(s, ai)
            risk_pct = (current_price - liquidation_price) / current_price
        else
            risk_pct = (liquidation_price - current_price) / current_price
        end
        
        # Alert if approaching liquidation
        if risk_pct < 0.05  # Less than 5% away from liquidation
            @warn "Liquidation risk for $ai: $(round(risk_pct*100, digits=2))% away"
            
            # Consider reducing position size
            if risk_pct < 0.02  # Less than 2% away
                reduce_position_size(s, ai, 0.5)  # Reduce by 50%
            end
        end
        
        return risk_pct
    end
    return nothing
end

# Automatic position size adjustment based on liquidation risk
function adjust_position_for_liquidation_risk(s, ai, target_risk_pct=0.10)
    if has_margin_position(s, ai)
        current_risk = check_liquidation_risk(s, ai)
        
        if current_risk < target_risk_pct
            # Calculate safe position size
            current_size = get_position_size(s, ai)
            safe_size = current_size * (current_risk / target_risk_pct)
            
            # Reduce position to safe size
            reduction_amount = current_size - safe_size
            if reduction_amount > s.config.min_order_size
                trade = call!(s, ReduceOnlyOrder{opposite_side(get_position_side(s, ai))}, ai;
                    amount=reduction_amount,
                    date=ts
                )
                @info "Reduced position size for $ai by $reduction_amount"
            end
        end
    end
end
```

### Funding Rate Integration

```julia
# Download and analyze funding rates
using Fetch

function analyze_funding_costs(ai, start_date, end_date)
    # Fetch funding rate history
    funding_rates = fetch_funding_rates(ai, start_date, end_date)
    
    # Calculate statistics
    avg_funding = mean(funding_rates.rate)
    max_funding = maximum(funding_rates.rate)
    min_funding = minimum(funding_rates.rate)
    
    # Estimate daily funding cost
    daily_funding_cost = avg_funding * 3  # 3 funding periods per day
    
    return (
        average = avg_funding,
        maximum = max_funding,
        minimum = min_funding,
        daily_cost = daily_funding_cost,
        annual_cost = daily_funding_cost * 365
    )
end

# Incorporate funding costs in strategy
function adjust_for_funding_costs(s, ai, position_duration_days)
    funding_analysis = analyze_funding_costs(ai, ts - Day(30), ts)
    
    # Estimate total funding cost for position duration
    estimated_funding_cost = funding_analysis.daily_cost * position_duration_days
    
    # Adjust profit target to account for funding
    base_profit_target = 0.02  # 2%
    adjusted_profit_target = base_profit_target + abs(estimated_funding_cost)
    
    return adjusted_profit_target
end

# Example: Long position with funding cost consideration
function open_long_with_funding_analysis(s, ai, hold_days=7)
    funding_cost = adjust_for_funding_costs(s, ai, hold_days)
    
    # Only open position if expected return exceeds funding cost
    expected_return = calculate_expected_return(s, ai)
    
    if expected_return > funding_cost * 1.5  # 50% margin above funding cost
        trade = call!(s, MarketOrder{Buy}, ai; 
            amount=s.config.base_size, 
            date=ts
        )
        
        # Set profit target accounting for funding
        profit_target = get_current_price(ai, ts) * (1 + funding_cost + 0.01)
        set_profit_target!(s, ai, profit_target)
        
        @info "Opened long position for $ai with funding-adjusted target: $profit_target"
    else
        @info "Skipping long position for $ai due to high funding costs"
    end
end
```


## See Also

- **[Exchanges](../exchanges.md)** - Exchange integration and configuration
- **[Config](../config.md)** - Exchange integration and configuration
- **[Optimization](../optimization.md)** - Performance optimization techniques
- **[Performance Issues](../troubleshooting/performance-issues.md)** - Troubleshooting: Performance optimization techniques
- **[Data Management](../guides/data-management.md)** - Guide: Data handling and management
- **[Exchanges](../exchanges.md)** - Data handling and management

## Backtesting Performance

Local benchmarking indicates that the `:Example` strategy, which employs FOK orders, operates on three assets, trades in spot markets, and utilizes a simple logic (which can be reviewed in the strategy code) to execute orders, currently takes approximately `~8 seconds` to cycle through `~1.3M * 3 (assets) ~= 3.9M candles`, executing `~6000 trades` on a single x86 core.

It's crucial to note that the type of orders executed and the number of trades performed can significantly impact the runtime, aside from other evident factors like additional strategy logic or the number of assets. Therefore, caution is advised when interpreting claims about a backtester's ability to process X rows in Y time without additional context. Furthermore, our order creation logic always ensures that order inputs adhere to the [exchange](../[exchanges](../exchanges.md).md)'s [limits](https://docs.ccxt.com/#/README?id=precision-and-limits), and we also incorporate slippage and probability calculations, enabling the backtester to be "MC simmable".

Backtesting a strategy with margin will inevitably be slower due to the need to account for all the necessary calculations, such as position states and liquidation triggers.

### Performance Optimization Guidelines

#### Memory Management

```julia
# For large backtests, optimize memory usage
s.config.memory_limit = 8_000_000_000  # 8GB limit
s.config.gc_frequency = 10000          # Garbage collect every 10k iterations

# Use data chunking for very large datasets
s.config.chunk_processing = true
s.config.chunk_size = 50000           # Process 50k candles at a time
```

#### CPU Optimization

```julia
# Enable multi-threading for parallel asset processing
ENV["JULIA_NUM_THREADS"] = "8"

# Configure parallel processing
s.config.parallel_assets = true       # Process assets in parallel
s.config.parallel_indicators = true   # Calculate indicators in parallel
```

#### I/O Optimization

```julia
# Optimize data loading
s.config.preload_data = true          # Load all data into memory
s.config.cache_indicators = true      # Cache calculated indicators
s.config.lazy_loading = false         # Disable lazy loading for speed

# Use memory-mapped files for very large datasets
s.config.use_mmap = true
```

### Performance Benchmarks

| Strategy Type | Assets | Timeframe | Candles | Trades | Time | Memory |
|---------------|--------|-----------|---------|--------|------|--------|
| Simple MA | 3 | 1h | 3.9M | 6K | 8s | 2GB |
| Complex Multi-TF | 10 | 1h/4h/1d | 12M | 15K | 45s | 6GB |
| Margin Strategy | 5 | 15m | 8M | 25K | 120s | 4GB |
| High-Freq | 1 | 1m | 2M | 50K | 30s | 1GB |

### Profiling and Debugging

```julia
using Profile

# Profile your backtest
@profile sm.start!(s)
Profile.print()

# Memory profiling
using BenchmarkTools
@benchmark sm.start!(s) samples=1 evals=1

# Detailed timing analysis
function profile_backtest(s)
    times = Dict()
    
    # Time data loading
    times[:data_loading] = @elapsed fill!(s)
    
    # Time strategy execution
    times[:execution] = @elapsed sm.start!(s)
    
    # Time metrics calculation
    times[:metrics] = @elapsed calculate_metrics(s)
    
    return times
end

timing_results = profile_backtest(s)
```

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
