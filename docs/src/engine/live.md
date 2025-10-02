# Running in Live Mode

A strategy in live mode operates against the exchange API defined by the strategy. This mode executes real trades with actual capital, so proper configuration and risk management are critical.

## Initial Setup and Configuration

To construct the strategy, use the same methods as in [paper mode](./paper.md), but with additional security considerations:

```julia
using Strategies
s = strategy(:Example, mode=Live(), sandbox=false) # The 'sandbox' parameter is passed to the strategy `call!(::Type, ::Any, ::LoadStrategy)` function
start!(s, foreground=true)
```

### API Configuration and Security

#### Exchange API Setup

```julia
# Configure API credentials securely
s.config.api_key = ENV["EXCHANGE_API_KEY"]        # Never hardcode keys
s.config.api_secret = ENV["EXCHANGE_API_SECRET"]
s.config.api_passphrase = ENV["EXCHANGE_PASSPHRASE"]  # For some exchanges

# Use sandbox for testing
s = strategy(:Example, 
    mode=Live(), 
    sandbox=true,  # Use testnet/sandbox
    exchange=:binance
)
```

#### Security Best Practices

```julia
# 1. Use environment variables for sensitive data
# Set in your shell or .envrc file:
# export BINANCE_API_KEY="your_api_key"
# export BINANCE_API_SECRET="your_api_secret"

# 2. Restrict API permissions
# - Enable only necessary permissions (trading, reading)
# - Disable withdrawal permissions
# - Use IP whitelisting when possible

# 3. Use separate API keys for different strategies
api_config = Dict(
    :scalping_strategy => (
        key = ENV["BINANCE_SCALPING_KEY"],
        secret = ENV["BINANCE_SCALPING_SECRET"]
    ),
    :swing_strategy => (
        key = ENV["BINANCE_SWING_KEY"], 
        secret = ENV["BINANCE_SWING_SECRET"]
    )
)

s.config.api_credentials = api_config[:scalping_strategy]
```

### Comprehensive Live Trading Setup

#### Basic Live Trading Configuration

```julia
using Strategies, LiveMode

# Create live strategy with full configuration
s = strategy(:LiveTradingBot,
    mode=Live(),
    exchange=:binance,
    sandbox=false,  # Set to true for testing
    initial_cash=1000.0,  # Start with smaller amount
    max_position_size=0.1  # Limit position sizes
)

# Configure risk management
s.config.max_daily_loss = 50.0      # Stop if daily loss exceeds $50
s.config.max_drawdown = 0.05        # Stop if drawdown exceeds 5%
s.config.position_limit = 0.2       # Max 20% per position
s.config.emergency_stop = true      # Enable emergency stop

# Set up monitoring
s.config.telegram_alerts = true
s.config.email_alerts = true
s.config.log_level = :info

start!(s, foreground=true)
```

#### Advanced Multi-Asset Live Setup

```julia
# Advanced live trading setup with multiple assets
s = strategy(:MultiAssetLive,
    mode=Live(),
    exchange=:binance,
    sandbox=false
)

# Configure universe with risk limits per asset
universe_config = Dict(
    :BTC => (max_position=0.3, risk_per_trade=0.02),
    :ETH => (max_position=0.25, risk_per_trade=0.015),
    :ADA => (max_position=0.15, risk_per_trade=0.01)
)

for (asset, config) in universe_config
    add_asset!(s, asset, 
        max_position=config.max_position,
        risk_per_trade=config.risk_per_trade
    )
end

# Set up real-time data feeds
for asset in keys(universe_config)
    setup_live_feed!(s, asset, ["1m", "5m", "15m"])
end

# Configure advanced risk management
s.config.correlation_limit = 0.7    # Limit correlated positions
s.config.sector_limit = 0.4         # Max 40% in any sector
s.config.volatility_adjustment = true  # Adjust sizes based on volatility

start!(s, 
    foreground=true,
    auto_rebalance=true,
    risk_monitoring=true
)
```

## How Live Mode Works

When you start live mode, `call!` functions are forwarded to the exchange API to fulfill the request. We set up background tasks to ensure events update the local state in a timely manner. Specifically, we run:

- A `Watcher` to monitor the balance. This runs in both spot (`NoMarginStrategy`) and derivatives (`MarginStrategy`). In the case of spot, the balance updates both the cash of the strategy's main currency and all the currencies in the strategy universe. For derivatives, it is used only to update the main currency.
- A `Watcher` to monitor positions when margin is used (`MarginStrategy`). The number of contracts of the open position represents the cash of the long/short `Position` in the `AssetInstance` (`MarginInstance`). This means that *non-zero balances* of a currency other than the strategy's main currency *won't be considered*.
- A long-running task that monitors all the order events of an asset. The task starts when a new order is requested and stops if there haven't been orders open for a while for the subject asset.
- A long-running task that monitors all trade events of an asset. This task starts and stops along with the order background task.

Similar to other modes, the return value of a `call!` function for creating an order will be:

- A `Trade` if a trade event was observed shortly after the order creation.
- `missing` if the order was successfully created but not immediately executed.
- `nothing` if the order failed to be created, either because of local checks (e.g., not enough cash) or some other exchange error (e.g., API timeout).

### Background Task Management

#### Watcher Configuration

```julia
# Configure balance watcher
s.config.balance_watcher = (
    enabled = true,
    interval = 30,  # Check every 30 seconds
    retry_count = 3,
    timeout = 10
)

# Configure position watcher for margin strategies
s.config.position_watcher = (
    enabled = true,
    interval = 15,  # Check every 15 seconds
    sync_on_startup = true,
    alert_on_changes = true
)

# Configure order event monitoring
s.config.order_monitoring = (
    enabled = true,
    timeout = 300,  # 5 minutes timeout
    retry_interval = 5,
    max_retries = 10
)
```

#### Custom Watchers

```julia
# Create custom watcher for specific metrics
function setup_custom_watchers(s)
    # PnL monitoring watcher
    @async begin
        while isrunning(s)
            try
                current_pnl = calculate_unrealized_pnl(s)
                if current_pnl < -s.config.max_daily_loss
                    @error "Daily loss limit exceeded: $current_pnl"
                    emergency_stop!(s)
                end
                
                # Log PnL every minute
                @info "Current PnL: $(round(current_pnl, digits=2)) USDT"
                sleep(60)
            catch e
                @error "PnL watcher error: $e"
                sleep(30)  # Wait before retrying
            end
        end
    end
    
    # Market condition watcher
    @async begin
        while isrunning(s)
            try
                market_volatility = calculate_market_volatility(s.universe)
                if market_volatility > s.config.max_volatility_threshold
                    @warn "High market volatility detected: $market_volatility"
                    reduce_position_sizes!(s, 0.5)  # Reduce positions by 50%
                end
                sleep(120)  # Check every 2 minutes
            catch e
                @error "Market watcher error: $e"
                sleep(60)
            end
        end
    end
end

# Start custom watchers
setup_custom_watchers(s)
```

### Order Execution and State Management

#### Order State Tracking

```julia
# Enhanced order tracking
mutable struct LiveOrderTracker
    pending_orders::Dict{String, Any}
    completed_orders::Dict{String, Any}
    failed_orders::Dict{String, Any}
    retry_queue::Vector{String}
    
    LiveOrderTracker() = new(Dict(), Dict(), Dict(), String[])
end

function track_order_execution(s, order_id, order_details)
    tracker = get_order_tracker(s)
    tracker.pending_orders[order_id] = (
        details = order_details,
        timestamp = now(),
        retries = 0
    )
    
    # Monitor order status
    @async begin
        while order_id in keys(tracker.pending_orders)
            try
                status = get_order_status(s, order_id)
                
                if status.filled
                    # Order completed
                    tracker.completed_orders[order_id] = tracker.pending_orders[order_id]
                    delete!(tracker.pending_orders, order_id)
                    @info "Order $order_id completed"
                    break
                elseif status.cancelled || status.expired
                    # Order failed
                    tracker.failed_orders[order_id] = tracker.pending_orders[order_id]
                    delete!(tracker.pending_orders, order_id)
                    @warn "Order $order_id failed: $(status.reason)"
                    break
                end
                
                sleep(5)  # Check every 5 seconds
            catch e
                @error "Error tracking order $order_id: $e"
                sleep(10)
            end
        end
    end
end
```

### Risk Management and Monitoring

#### Real-Time Risk Monitoring

```julia
# Comprehensive risk monitoring system
function setup_risk_monitoring(s)
    @async begin
        risk_metrics = Dict()
        
        while isrunning(s)
            try
                # Calculate current risk metrics
                risk_metrics[:total_exposure] = calculate_total_exposure(s)
                risk_metrics[:leverage_ratio] = calculate_leverage_ratio(s)
                risk_metrics[:correlation_risk] = calculate_correlation_risk(s)
                risk_metrics[:liquidity_risk] = calculate_liquidity_risk(s)
                
                # Check risk limits
                check_risk_limits(s, risk_metrics)
                
                # Log risk status
                @info "Risk Status" risk_metrics
                
                sleep(30)  # Update every 30 seconds
            catch e
                @error "Risk monitoring error: $e"
                sleep(60)
            end
        end
    end
end

function check_risk_limits(s, metrics)
    # Total exposure limit
    if metrics[:total_exposure] > s.config.max_total_exposure
        @error "Total exposure limit exceeded: $(metrics[:total_exposure])"
        reduce_all_positions!(s, 0.7)  # Reduce all positions by 30%
    end
    
    # Leverage limit
    if metrics[:leverage_ratio] > s.config.max_leverage
        @error "Leverage limit exceeded: $(metrics[:leverage_ratio])"
        close_highest_risk_positions!(s)
    end
    
    # Correlation risk
    if metrics[:correlation_risk] > 0.8
        @warn "High correlation risk detected"
        diversify_positions!(s)
    end
end
```

#### Emergency Procedures

```julia
# Emergency stop procedures
function emergency_stop!(s, reason="Manual trigger")
    @error "EMERGENCY STOP TRIGGERED: $reason"
    
    # Stop strategy execution
    stop!(s)
    
    # Cancel all pending orders
    cancel_all_orders!(s)
    
    # Close all positions (optional, based on configuration)
    if s.config.emergency_close_positions
        close_all_positions!(s)
    end
    
    # Send alerts
    send_emergency_alert!(s, reason)
    
    # Log emergency stop
    log_emergency_event!(s, reason)
end

# Automated circuit breakers
function setup_circuit_breakers(s)
    # Daily loss circuit breaker
    @async begin
        daily_start_balance = calculate_total_balance(s)
        
        while isrunning(s)
            current_balance = calculate_total_balance(s)
            daily_pnl = current_balance - daily_start_balance
            
            if daily_pnl < -s.config.max_daily_loss
                emergency_stop!(s, "Daily loss limit exceeded: $(round(daily_pnl, digits=2))")
                break
            end
            
            sleep(60)  # Check every minute
        end
    end
    
    # Drawdown circuit breaker
    @async begin
        peak_balance = calculate_total_balance(s)
        
        while isrunning(s)
            current_balance = calculate_total_balance(s)
            
            if current_balance > peak_balance
                peak_balance = current_balance
            end
            
            drawdown = (peak_balance - current_balance) / peak_balance
            
            if drawdown > s.config.max_drawdown
                emergency_stop!(s, "Maximum drawdown exceeded: $(round(drawdown*100, digits=2))%")
                break
            end
            
            sleep(120)  # Check every 2 minutes
        end
    end
end
```

## Timeouts and API Management

If you don't want to wait for the order processing, you can pass a custom `waitfor` parameter which limits the amount of time we wait for API responses.

```julia
call!(s, ai, MarketOrder{Buy}; synced=false, waitfor=Second(0)) # don't wait
```
The `synced=true` flag is a last-ditch attempt that _force fetches_ updates from the exchange if no new events have been observed by the background tasks after the waiting period expires (default is `true`).

The local trades history might diverge from the data sourced from the exchange because not all exchanges support endpoints for fetching trades history or events, therefore trades are emulated from diffing order updates.

The local state is *not persisted*. Nothing is saved or loaded from storage. Instead, we sync the most recent history of orders with their respective trades when the strategy starts running. (This behavior might change in the future if need arises.)

### Advanced Timeout Configuration

```julia
# Configure different timeouts for different operations
s.config.timeouts = (
    order_placement = Second(30),    # Wait up to 30s for order placement
    order_cancellation = Second(10), # Wait up to 10s for cancellation
    balance_sync = Second(15),       # Wait up to 15s for balance updates
    position_sync = Second(20),      # Wait up to 20s for position updates
    market_data = Second(5)          # Wait up to 5s for market data
)

# Use custom timeouts for specific operations
trade = call!(s, GTCOrder{Buy}, ai; 
    price=50000.0, 
    amount=0.001, 
    date=now(),
    waitfor=s.config.timeouts.order_placement,
    synced=true
)
```

### API Rate Limiting and Management

```julia
# Configure API rate limiting
s.config.rate_limits = (
    orders_per_second = 10,
    requests_per_minute = 1200,
    weight_per_minute = 6000,
    burst_allowance = 5
)

# Implement intelligent request batching
function batch_order_operations(s, operations)
    batches = []
    current_batch = []
    current_weight = 0
    
    for op in operations
        op_weight = estimate_api_weight(op)
        
        if current_weight + op_weight > s.config.rate_limits.weight_per_minute / 10
            # Start new batch
            push!(batches, current_batch)
            current_batch = [op]
            current_weight = op_weight
        else
            push!(current_batch, op)
            current_weight += op_weight
        end
    end
    
    if !isempty(current_batch)
        push!(batches, current_batch)
    end
    
    # Execute batches with appropriate delays
    for (i, batch) in enumerate(batches)
        execute_batch(s, batch)
        
        if i < length(batches)
            sleep(6)  # Wait 6 seconds between batches
        end
    end
end
```

### Connection Management and Resilience

```julia
# Implement connection resilience
function setup_connection_management(s)
    @async begin
        while isrunning(s)
            try
                # Test connection health
                if !test_connection_health(s)
                    @warn "Connection health check failed, attempting reconnection"
                    reconnect_exchange!(s)
                end
                
                sleep(60)  # Check every minute
            catch e
                @error "Connection management error: $e"
                sleep(30)
            end
        end
    end
end

function reconnect_exchange!(s)
    max_retries = 5
    retry_delay = 10  # seconds
    
    for attempt in 1:max_retries
        try
            @info "Reconnection attempt $attempt/$max_retries"
            
            # Close existing connections
            close_connections!(s)
            
            # Wait before reconnecting
            sleep(retry_delay * attempt)
            
            # Establish new connections
            initialize_exchange_connection!(s)
            
            # Verify connection
            if test_connection_health(s)
                @info "Successfully reconnected to exchange"
                
                # Resync state
                sync_account_state!(s)
                return true
            end
            
        catch e
            @error "Reconnection attempt $attempt failed: $e"
        end
    end
    
    # If all retries failed, trigger emergency stop
    emergency_stop!(s, "Failed to reconnect to exchange after $max_retries attempts")
    return false
end

# Sync account state after reconnection
function sync_account_state!(s)
    @info "Syncing account state after reconnection"
    
    # Sync balances
    sync_balances!(s)
    
    # Sync open orders
    sync_open_orders!(s)
    
    # Sync positions (for margin strategies)
    if is_margin_strategy(s)
        sync_positions!(s)
    end
    
    # Sync recent trade history
    sync_trade_history!(s, hours=1)
    
    @info "Account state sync completed"
end
```

### Logging and Alerting

```julia
# Comprehensive logging setup
function setup_live_logging(s)
    # Create structured logger
    logger = create_structured_logger(
        file = "logs/live_trading_$(now()).log",
        level = s.config.log_level,
        format = :json  # Use JSON for structured logging
    )
    
    # Set up log rotation
    setup_log_rotation(logger, 
        max_size = "100MB",
        max_files = 10
    )
    
    return logger
end

# Alert system integration
function setup_alerting(s)
    # Telegram alerts
    if s.config.telegram_alerts
        telegram_bot = TelegramBot(ENV["TELEGRAM_BOT_TOKEN"])
        chat_id = ENV["TELEGRAM_CHAT_ID"]
        
        s.config.alert_handlers[:telegram] = (message) -> begin
            send_message(telegram_bot, chat_id, message)
        end
    end
    
    # Email alerts
    if s.config.email_alerts
        smtp_config = (
            server = ENV["SMTP_SERVER"],
            port = parse(Int, ENV["SMTP_PORT"]),
            username = ENV["SMTP_USERNAME"],
            password = ENV["SMTP_PASSWORD"]
        )
        
        s.config.alert_handlers[:email] = (message) -> begin
            send_email(smtp_config, 
                to = ENV["ALERT_EMAIL"],
                subject = "Planar Live Trading Alert",
                body = message
            )
        end
    end
    
    # Discord webhook alerts
    if haskey(ENV, "DISCORD_WEBHOOK_URL")
        webhook_url = ENV["DISCORD_WEBHOOK_URL"]
        
        s.config.alert_handlers[:discord] = (message) -> begin
            send_discord_webhook(webhook_url, message)
        end
    end
end

# Send alerts through all configured channels
function send_alert(s, message, level=:info)
    timestamp = now()
    formatted_message = "[$timestamp] [$level] $message"
    
    # Log the alert
    @info "ALERT: $formatted_message"
    
    # Send through all configured alert handlers
    for (channel, handler) in s.config.alert_handlers
        try
            handler(formatted_message)
        catch e
            @error "Failed to send alert via $channel: $e"
        end
    end
end
```

## Event Tracing

During live execution events are recorded and flushed to storage (based on the active `ZarrInstance`).
The `EventTrace` can be accessed from an `Exchange` object. When an `Exchange` object is initialized, it creates an `EventTrace` object to store events related to that exchange.

```julia
# Access the event trace from an exchange object
exc = getexchange!(:binance)
et = exc._trace
```

### Advanced Event Tracing

#### Comprehensive Event Logging

```julia
# Configure detailed event tracing
function setup_event_tracing(s)
    # Enable comprehensive event logging
    s.config.event_tracing = (
        enabled = true,
        trace_orders = true,
        trace_trades = true,
        trace_balance_changes = true,
        trace_position_changes = true,
        trace_market_data = false,  # Can be very verbose
        trace_api_calls = true,
        storage_backend = :zarr,
        flush_interval = 60  # Flush every 60 seconds
    )
    
    # Set up custom event handlers
    s.config.event_handlers = Dict(
        :order_placed => (event) -> log_order_event(s, event),
        :trade_executed => (event) -> log_trade_event(s, event),
        :balance_updated => (event) -> log_balance_event(s, event),
        :error_occurred => (event) -> handle_error_event(s, event)
    )
end

# Custom event logging functions
function log_order_event(s, event)
    @info "Order Event" event.type event.order_id event.symbol event.side event.amount event.price
    
    # Store in custom analytics
    push!(s.analytics.order_events, (
        timestamp = event.timestamp,
        type = event.type,
        order_id = event.order_id,
        symbol = event.symbol,
        side = event.side,
        amount = event.amount,
        price = event.price,
        status = event.status
    ))
end

function log_trade_event(s, event)
    @info "Trade Event" event.trade_id event.symbol event.side event.amount event.price event.fee
    
    # Calculate trade metrics
    trade_value = event.amount * event.price
    fee_percentage = event.fee / trade_value * 100
    
    # Update running statistics
    update_trade_statistics!(s, event, fee_percentage)
end
```

#### Replaying Events

To replay events in a local simulation, use the `replay_from_trace!` function:

```julia
replay_from_trace!(live_strategy)
```

This function will reconstruct the state of the strategy based on the events recorded in the trace.

#### Advanced Event Analysis

```julia
# Comprehensive event analysis
function analyze_trading_events(s, start_date=nothing, end_date=nothing)
    exc = getexchange!(s.config.exchange)
    et = exc._trace
    
    # Extract events for analysis
    events = if isnothing(start_date) && isnothing(end_date)
        trace_tail(et, n=10000; as_df=true)
    else
        extract_events_by_date(et, start_date, end_date)
    end
    
    # Analyze order patterns
    order_analysis = analyze_order_patterns(events)
    
    # Analyze execution quality
    execution_analysis = analyze_execution_quality(events)
    
    # Analyze timing patterns
    timing_analysis = analyze_timing_patterns(events)
    
    return (
        orders = order_analysis,
        execution = execution_analysis,
        timing = timing_analysis,
        raw_events = events
    )
end

function analyze_order_patterns(events)
    order_events = filter(e -> e.type in ["order_placed", "order_filled", "order_cancelled"], events)
    
    # Calculate order statistics
    total_orders = length(order_events)
    filled_orders = count(e -> e.type == "order_filled", order_events)
    cancelled_orders = count(e -> e.type == "order_cancelled", order_events)
    
    fill_rate = filled_orders / total_orders * 100
    cancel_rate = cancelled_orders / total_orders * 100
    
    # Analyze order sizes
    order_sizes = [e.amount for e in order_events if haskey(e, :amount)]
    avg_order_size = mean(order_sizes)
    median_order_size = median(order_sizes)
    
    return (
        total_orders = total_orders,
        fill_rate = fill_rate,
        cancel_rate = cancel_rate,
        avg_order_size = avg_order_size,
        median_order_size = median_order_size
    )
end

function analyze_execution_quality(events)
    trade_events = filter(e -> e.type == "trade_executed", events)
    
    # Calculate slippage statistics
    slippages = []
    for trade in trade_events
        if haskey(trade, :expected_price) && haskey(trade, :actual_price)
            slippage = (trade.actual_price - trade.expected_price) / trade.expected_price * 100
            push!(slippages, slippage)
        end
    end
    
    # Calculate execution speed
    execution_times = []
    order_to_trade = Dict()
    
    for event in events
        if event.type == "order_placed"
            order_to_trade[event.order_id] = event.timestamp
        elseif event.type == "trade_executed" && haskey(order_to_trade, event.order_id)
            execution_time = event.timestamp - order_to_trade[event.order_id]
            push!(execution_times, execution_time.value / 1000)  # Convert to seconds
        end
    end
    
    return (
        avg_slippage = isempty(slippages) ? 0.0 : mean(slippages),
        median_slippage = isempty(slippages) ? 0.0 : median(slippages),
        avg_execution_time = isempty(execution_times) ? 0.0 : mean(execution_times),
        median_execution_time = isempty(execution_times) ? 0.0 : median(execution_times)
    )
end
```

#### Extracting Events

To extract a subset of events or the last `n` events, use the `trace_tail` function:

```julia
events = trace_tail(et, n=10; as_df=false)
```

#### Event-Based Strategy Optimization

```julia
# Use event data to optimize strategy parameters
function optimize_from_events(s, optimization_period_days=30)
    # Extract recent events
    end_date = now()
    start_date = end_date - Day(optimization_period_days)
    
    analysis = analyze_trading_events(s, start_date, end_date)
    
    # Optimize based on execution quality
    if analysis.execution.avg_slippage > 0.1  # More than 0.1% slippage
        @info "High slippage detected, adjusting order strategy"
        s.config.prefer_limit_orders = true
        s.config.limit_order_offset = 0.05  # 0.05% offset from market price
    end
    
    # Optimize based on fill rates
    if analysis.orders.fill_rate < 80  # Less than 80% fill rate
        @info "Low fill rate detected, adjusting order parameters"
        s.config.order_timeout = s.config.order_timeout * 1.5  # Increase timeout
        s.config.price_improvement = s.config.price_improvement * 0.8  # Reduce price improvement
    end
    
    # Optimize based on execution speed
    if analysis.execution.avg_execution_time > 30  # More than 30 seconds
        @info "Slow execution detected, optimizing order placement"
        s.config.use_market_orders_threshold = 0.02  # Use market orders for urgent trades
    end
    
    return analysis
end

# Automated strategy tuning based on live performance
function setup_automated_tuning(s)
    @async begin
        while isrunning(s)
            try
                # Run optimization every 24 hours
                sleep(24 * 3600)
                
                @info "Running automated strategy optimization"
                optimization_results = optimize_from_events(s)
                
                # Log optimization results
                @info "Optimization completed" optimization_results
                
                # Send optimization report
                send_alert(s, "Strategy optimization completed: $(optimization_results)", :info)
                
            catch e
                @error "Automated tuning error: $e"
                sleep(3600)  # Wait 1 hour before retrying
            end
        end
    end
end
```
