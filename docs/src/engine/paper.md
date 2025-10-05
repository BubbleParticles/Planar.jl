---
category: "strategy-development"
difficulty: "advanced"
topics: [execution-modes, margin-trading, exchanges, data-management, optimization, strategy-development, troubleshooting, visualization, configuration]
last_updated: "2025-10-04"---
---

# Running in Paper Mode

Paper mode provides a realistic [simulation](../guides/execution-modes.md#simulation-mode) environment that uses live [market data](../guides/data-management.md) while simulating order execution. This allows you to test [strategies](../guides/strategy-development.md) with real market conditions without risking actual capital.

## Configuration Options

In order to configure a [strategy](../guides/strategy-development.md) in paper mode, you can define the default mode in `user/[planar.toml](../config.md#configuration)-file)` or in your [strategy](../guides/strategy-development.md) project's `Project.toml` file. Alternatively, pass the mode as a keyword argument:

### Configuration via TOML Files

```toml
# user/[planar.toml](../config.md#configuration)-file)
[Example]
mode = "Paper"
[exchange]([exchanges](../exchanges.md).md) = "binance"
throttle = 5  # seconds between [strategy](../guides/strategy-development.md) calls
initial_cash = 10000.0
```

```toml
# Strategy Project.toml
[strategy]
mode = "Paper"
sandbox = true  # Use [exchange]([exchanges](../exchanges.md).md) sandbox/testnet
```

### Configuration via [Julia](https://julialang.org/) Code

```julia
using Strategies
s = strategy(:Example, mode=Paper())

# Or with additional parameters
s = strategy(:Example, 
    mode=Paper(), 
    [exchange]([exchanges](../exchanges.md).md)=:binance,
    initial_cash=10000.0,
    throttle=5
)
```

## Starting Paper Mode

To start the strategy, use the following command:

```julia
using PaperMode
start!(s)
```

### Advanced Startup Options

```julia
# Run in foreground with detailed logging
start!(s, foreground=true, verbose=true)

# Run in background
start!(s, foreground=false)

# Custom logging [configuration](../config.md)
start!(s, 
    foreground=true,
    log_level=:debug,
    log_file="paper_trading.log"
)

# With custom throttle settings
start!(s, 
    throttle=Second(10),  # Override default throttle
    max_iterations=1000   # Limit number of iterations
)
```

Upon executing this, the following log output is expected:

```julia
┌ Info: Starting strategy ExampleMargin in paper mode!
│
│     throttle: 5 seconds
│     [timeframes](../guides/data-management.md#timeframes): 1m(main), 1m(optional), 1m 15m 1h 1d(extras)
│     cash: USDT: 100.0 (on phemex) [100.0]
│     assets: ETH/USDT:USDT, BTC/USDT:USDT, SOL/USDT:USDT
│     margin: Isolated()
└
[ Info: 2023-07-07T04:49:51.051(ExampleMargin@phemex) 0.0/100.0[100.0](USDT), orders: 0/0(+/-) trades: 0/0/0(L/S/Q)
[ Info: 2023-07-07T04:49:56.057(ExampleMargin@phemex) 0.0/100.0[100.0](USDT), orders: 0/0(+/-) trades: 0/0/0(L/S/Q)
```

### Background Execution

To run the strategy as a background task:

```julia
start!(s, foreground=false)
```

The logs will be written either to the `s[:logfile]` key of the strategy object, if present, or to the output of the `runlog(s)` command.

### Log Management

```julia
# Set custom log file
s[:logfile] = "logs/paper_trading_$(now()).log"

# View current log file
println("Log file: $(runlog(s))")

# Tail logs in real-time
using Tail
tail_logs(runlog(s))

# Parse and analyze logs
function analyze_paper_logs(log_file)
    logs = readlines(log_file)
    
    # Extract performance metrics
    trade_logs = filter(l -> contains(l, "trades:"), logs)
    order_logs = filter(l -> contains(l, "orders:"), logs)
    
    println("Total log entries: $(length(logs))")
    println("Trade updates: $(length(trade_logs))")
    println("Order updates: $(length(order_logs))")
    
    return (logs=logs, trades=trade_logs, orders=order_logs)
end

log_analysis = analyze_paper_logs(runlog(s))
```

## Comprehensive Setup Examples

### Basic Spot Trading Setup

```julia
using Strategies, PaperMode

# Create spot trading strategy
s = strategy(:SimpleMA, mode=Paper())

# Configure universe
s.universe = [:BTC, :ETH, :ADA]
s.config.initial_cash = 10000.0
s.config.base_size = 100.0

# Set up data feeds
for asset in s.universe
    setup_live_data!(s, asset, "1m")
end

# Start [paper trading](../guides/execution-modes.md#paper-mode)
start!(s, foreground=true)
```

### Advanced Margin Trading Setup

```julia
using Strategies, PaperMode

# Create margin strategy with [isolated margin](../guides/strategy-development.md#margin-modes)
s = strategy(:MarginStrategy, 
    mode=Paper(),
    margin=Isolated(),
    exchange=:binance
)

# Configure margin parameters
s.config.initial_cash = 5000.0
s.config.max_leverage = 10.0
s.config.risk_per_trade = 0.02  # 2% risk per trade

# Set up multi-[timeframe](../guides/data-management.md#timeframes) data
[timeframes](../guides/data-management.md#timeframes) = ["1m", "5m", "15m", "1h"]
for asset in s.universe
    for tf in [timeframes](../guides/data-management.md#timeframes)
        setup_live_data!(s, asset, tf)
    end
end

# Configure risk management
s.config.max_drawdown = 0.10      # 10% max drawdown
s.config.daily_loss_limit = 0.05  # 5% daily loss limit

# Start with monitoring
start!(s, 
    foreground=true,
    monitor_risk=true,
    auto_stop_loss=true
)
```

### Multi-Exchange Paper Trading

```julia
# Set up [strategies](../guides/strategy-development.md) on multiple exchanges
exchanges = [:binance, :bybit, :okx]
[strategies](../guides/strategy-development.md) = Dict()

for exchange in exchanges
    s = strategy(:ArbitrageStrategy, 
        mode=Paper(),
        exchange=exchange,
        initial_cash=3333.33  # Split capital across exchanges
    )
    
    # Exchange-specific configuration
    if exchange == :binance
        s.config.fee_rate = 0.001
    elseif exchange == :bybit
        s.config.fee_rate = 0.0006
    else  # okx
        s.config.fee_rate = 0.0008
    end
    
    strategies[exchange] = s
end

# Start all strategies
for (exchange, strategy) in strategies
    @async start!(strategy, foreground=false)
    @info "Started [paper trading](../guides/execution-modes.md#paper-mode) on $exchange"
end

# Monitor all strategies
function monitor_multi_exchange()
    while true
        for (exchange, s) in strategies
            if isrunning(s)
                pnl = calculate_pnl(s)
                @info "$exchange PnL: $(round(pnl, digits=2)) USDT"
            end
        end
        sleep(60)  # Update every minute
    end
end

@async monitor_multi_exchange()
```

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
```julia
# Monitor real-time price updates
function setup_price_monitoring(s)
    for ai in s.universe
        @async begin
            while isrunning(s)
                current_price = get_live_price(ai)
                update_strategy_price!(s, ai, current_price)
                sleep(1)  # Update every second
            end
        end
    end
end
```

### Order Book Integration
```julia
# Access real-time order book data
function analyze_order_book(ai, depth=10)
    book = get_order_book(ai, depth)
    
    # Calculate spread
    spread = book.asks[1].price - book.bids[1].price
    spread_pct = spread / book.bids[1].price * 100
    
    # Calculate market depth
    bid_depth = sum(bid.amount for bid in book.bids)
    ask_depth = sum(ask.amount for ask in book.asks)
    
    return (
        spread = spread,
        spread_pct = spread_pct,
        bid_depth = bid_depth,
        ask_depth = ask_depth,
        imbalance = bid_depth / (bid_depth + ask_depth)
    )
end

# Use order book data in strategy
function smart_order_placement(s, ai, side, amount)
    book_analysis = analyze_order_book(ai)
    
    if book_analysis.spread_pct > 0.1  # Wide spread
        # Use limit orders closer to mid-price
        mid_price = (book_analysis.best_bid + book_analysis.best_ask) / 2
        
        if side == Buy
            price = mid_price * 1.001  # Slightly above mid
        else
            price = mid_price * 0.999  # Slightly below mid
        end
        
        return call!(s, GTCOrder{side}, ai; price=price, amount=amount, date=now())
    else
        # Tight spread, use market orders
        return call!(s, MarketOrder{side}, ai; amount=amount, date=now())
    end
end
```

## Performance Monitoring

### Real-Time Metrics
```julia
# Set up real-time performance monitoring
function setup_performance_monitoring(s)
    start_time = now()
    initial_balance = s.cash[s.config.base_currency]
    
    @async begin
        while isrunning(s)
            current_balance = calculate_total_balance(s)
            pnl = current_balance - initial_balance
            pnl_pct = pnl / initial_balance * 100
            
            # Calculate time-based metrics
            elapsed = now() - start_time
            daily_return = pnl_pct * (Day(1) / elapsed)
            
            # Log performance
            @info "Paper Trading Performance" pnl pnl_pct daily_return elapsed
            
            # Check stop conditions
            if pnl_pct < -10.0  # 10% loss
                @warn "Maximum loss reached, stopping strategy"
                stop!(s)
                break
            end
            
            sleep(300)  # Update every 5 minutes
        end
    end
end

# Enhanced performance tracking
mutable struct PaperTradingMetrics
    start_time::DateTime
    initial_balance::Float64
    peak_balance::Float64
    current_drawdown::Float64
    max_drawdown::Float64
    total_trades::Int
    winning_trades::Int
    total_fees::Float64
    
    PaperTradingMetrics(initial_balance) = new(
        now(), initial_balance, initial_balance, 0.0, 0.0, 0, 0, 0.0
    )
end

function update_metrics!(metrics::PaperTradingMetrics, s)
    current_balance = calculate_total_balance(s)
    
    # Update peak and drawdown
    if current_balance > metrics.peak_balance
        metrics.peak_balance = current_balance
        metrics.current_drawdown = 0.0
    else
        metrics.current_drawdown = (metrics.peak_balance - current_balance) / metrics.peak_balance
        metrics.max_drawdown = max(metrics.max_drawdown, metrics.current_drawdown)
    end
    
    # Update trade statistics
    metrics.total_trades = length(s.trades)
    metrics.winning_trades = count(t -> t.pnl > 0, s.trades)
    metrics.total_fees = sum(t -> t.fee, s.trades)
    
    return metrics
end
```


## See Also

- **[Exchanges](../exchanges.md)** - Exchange integration and configuration
- **[Config](../config.md)** - Exchange integration and configuration
- **[Optimization](../optimization.md)** - Performance optimization techniques
- **[Performance Issues](../troubleshooting/performance-issues.md)** - Troubleshooting: Performance optimization techniques
- **[Data Management](../guides/data-management.md)** - Guide: Data handling and management
- **[Exchanges](../exchanges.md)** - Data handling and management

## Risk Management in Paper Mode

### Position Sizing
```julia
# Dynamic position sizing based on volatility
function calculate_position_size(s, ai, risk_pct=0.02)
    # Get recent volatility
    volatility = calculate_volatility(ai, period=20)
    
    # Calculate position size based on volatility
    account_balance = calculate_total_balance(s)
    risk_amount = account_balance * risk_pct
    
    # Adjust for volatility
    position_size = risk_amount / volatility
    
    # Apply limits
    max_size = account_balance * 0.1  # Max 10% per position
    min_size = s.config.min_order_size
    
    return clamp(position_size, min_size, max_size)
end
```

### Stop Loss Management
```julia
# Implement trailing stops in paper mode
function implement_trailing_stops(s)
    @async begin
        while isrunning(s)
            for ai in s.universe
                if has_position(s, ai)
                    manage_trailing_stop(s, ai)
                end
            end
            sleep(10)  # Check every 10 seconds
        end
    end
end

function manage_trailing_stop(s, ai, trail_pct=0.03)
    position = get_position(s, ai)
    current_price = get_live_price(ai)
    
    if position.side == Long
        # Long position trailing stop
        if !haskey(position.metadata, :highest_price) || 
           current_price > position.metadata[:highest_price]
            position.metadata[:highest_price] = current_price
        end
        
        stop_price = position.metadata[:highest_price] * (1 - trail_pct)
        
        if current_price <= stop_price
            # Execute trailing stop
            call!(s, MarketOrder{Sell}, ai; 
                amount=position.size, 
                date=now()
            )
            @info "Trailing stop executed for $ai at $current_price"
        end
    end
end
```