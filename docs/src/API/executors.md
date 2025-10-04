---
title: "Executors API"
description: "Order execution and trade management"
category: "api-reference"
difficulty: "advanced"
prerequisites: ["getting-started", "strategy-development"]
topics: ["api-reference", "orders", "execution", "trading"]
last_updated: "2025-10-04"
estimated_time: "Reference material"
---

# Executors API

The Executors module handles order execution and trade management in Planar. It provides the interface between strategy logic and actual order placement, managing the execution lifecycle across different trading modes.

## Overview

The Executors module is responsible for:
- Order creation and validation
- Trade execution across different modes (sim, paper, live)
- Order lifecycle management
- Position tracking and updates
- Risk management and validation

## Core Execution Events

### Event Types

```julia
# Core execution events
struct OptSetup <: ExecAction end      # Optimization setup
struct OptRun <: ExecAction end        # Optimization run
struct OptScore <: ExecAction end      # Optimization scoring

struct NewTrade <: ExecAction end      # New trade execution

# Data events
struct WatchOHLCV <: ExecAction end    # OHLCV data monitoring
struct UpdateData <: ExecAction end    # Data update
struct InitData <: ExecAction end      # Data initialization

# Order events
struct UpdateOrders <: ExecAction end  # Order updates
struct CancelOrders <: ExecAction end  # Order cancellation

# Position events (for margin trading)
struct UpdateLeverage <: ExecAction end  # Leverage updates
struct UpdateMargin <: ExecAction end    # Margin updates
struct UpdatePositions <: ExecAction end # Position updates
```

### Event Handling

```julia
# Handle new trade execution
function call!(s::Strategy, ::NewTrade, order::Order, ai::AssetInstance; kwargs...)
    # Custom trade handling logic
    @info "New trade executed" order=order asset=raw(ai)
    
    # Update strategy state
    # Record trade for analysis
    # Trigger notifications
end

# Handle order updates
function call!(s::Strategy, ::UpdateOrders, ai::AssetInstance; kwargs...)
    # Process order status changes
    active_orders = orders(ai)
    @info "Processing $(length(active_orders)) active orders"
end
```

## Order Management

### Order Access and Manipulation

```julia
# Get active orders for an asset
active_orders = orders(asset_instance)

# Get orders by type
buy_orders = filter(o -> isa(o, AnyBuyOrder), active_orders)
sell_orders = filter(o -> isa(o, AnySellOrder), active_orders)

# Order information
for order in active_orders
    println("Order: $(order.amount) $(raw(order.asset)) at $(order.price)")
    println("Status: $(order.status)")
    println("Created: $(order.timestamp)")
end
```

#### Order Creation Example

```julia
using Planar
@strategyenv!

function place_buy_order_example(s::Strategy, ai::AssetInstance, amount::Float64)
    try
        # Get current price
        current_price = lastprice(ai)
        
        # Calculate order price (e.g., 1% below market)
        order_price = current_price * 0.99
        
        # Check available cash
        available = freecash(s)
        order_value = amount * order_price
        
        if available >= order_value
            # Create buy order
            order = BuyOrder(
                asset=ai.asset,
                amount=amount,
                price=order_price,
                exchange=exchangeid(s)
            )
            
            # Submit order (implementation depends on execution mode)
            submit_order!(s, order, ai)
            
            @info "Buy order placed" amount=amount price=order_price
        else
            @warn "Insufficient funds" available=available required=order_value
        end
    catch e
        @error "Order placement failed" exception=e
    end
end
```

### Order Lifecycle Management

```julia
# Monitor order status
function monitor_orders(s::Strategy)
    for ai in assets(s)
        active_orders = orders(ai)
        
        for order in active_orders
            # Check order age
            age = now() - order.timestamp
            
            if age > Hour(1)  # Cancel orders older than 1 hour
                cancel_order!(s, order, ai)
                @info "Cancelled stale order" order_id=order.id age=age
            end
            
            # Check if order is filled
            if order.status == :filled
                handle_filled_order(s, order, ai)
            elseif order.status == :cancelled
                handle_cancelled_order(s, order, ai)
            end
        end
    end
end

function handle_filled_order(s::Strategy, order::Order, ai::AssetInstance)
    @info "Order filled" order=order
    
    # Update position tracking
    if isa(order, AnyBuyOrder)
        # Handle buy order fill
        @info "Buy order filled - position increased"
    else
        # Handle sell order fill
        @info "Sell order filled - position decreased"
    end
    
    # Trigger any post-trade logic
    call!(s, NewTrade(), order, ai)
end
```

## Optimization Integration

### Optimization Setup

```julia
# Setup optimization parameters
function call!(s::Strategy, ::OptSetup, params::Dict; kwargs...)
    # Configure strategy parameters for optimization
    for (param_name, param_value) in params
        setattr!(s, param_name, param_value)
    end
    
    # Initialize optimization-specific state
    setattr!(s, :opt_start_time, now())
    setattr!(s, :opt_trades, [])
end

# Run optimization iteration
function call!(s::Strategy, ::OptRun, context; kwargs...)
    # Execute strategy with current parameters
    # This is called during backtesting for each parameter set
    
    # Reset strategy state
    reset!(s)
    
    # Run strategy logic
    # (handled by the optimization framework)
end

# Score optimization results
function call!(s::Strategy, ::OptScore; kwargs...)
    # Calculate performance metrics for current parameter set
    trades = attr(s, :opt_trades, [])
    
    if isempty(trades)
        return -Inf  # No trades = poor performance
    end
    
    # Calculate returns
    total_return = calculate_total_return(trades)
    sharpe_ratio = calculate_sharpe_ratio(trades)
    max_drawdown = calculate_max_drawdown(trades)
    
    # Composite score (customize as needed)
    score = sharpe_ratio - max_drawdown * 0.5
    
    @info "Optimization score" score=score return=total_return sharpe=sharpe_ratio drawdown=max_drawdown
    
    return score
end
```

### Optimization Example

```julia
module OptimizableStrategy
    @strategyenv!
    
    # Parameters to optimize
    const SMA_FAST = Ref(10)
    const SMA_SLOW = Ref(30)
    const STOP_LOSS = Ref(0.02)
    
    function call!(s::S, ::OptSetup, params::Dict; kwargs...) where {S<:Strategy}
        # Update parameters
        SMA_FAST[] = get(params, :sma_fast, SMA_FAST[])
        SMA_SLOW[] = get(params, :sma_slow, SMA_SLOW[])
        STOP_LOSS[] = get(params, :stop_loss, STOP_LOSS[])
        
        @info "Optimization setup" fast=SMA_FAST[] slow=SMA_SLOW[] stop=STOP_LOSS[]
    end
    
    function call!(s::S, current_time::DateTime, ctx) where {S<:Strategy}
        # Strategy logic using optimizable parameters
        for ai in assets(s)
            data = ohlcv(ai)
            
            if length(data.close) >= SMA_SLOW[]
                sma_fast = mean(data.close[end-SMA_FAST[]+1:end])
                sma_slow = mean(data.close[end-SMA_SLOW[]+1:end])
                
                # Trading logic with current parameters
                if sma_fast > sma_slow * 1.01  # Fast SMA above slow SMA
                    # Consider buying
                    place_buy_order_example(s, ai, 0.1)
                end
            end
        end
    end
    
    function call!(s::S, ::OptScore; kwargs...) where {S<:Strategy}
        # Calculate performance score
        # (implementation depends on your metrics)
        return calculate_strategy_score(s)
    end
end
```

## Position Management (Margin Trading)

### Position Updates

```julia
# Handle position updates for margin strategies
function call!(s::MarginStrategy, ::UpdatePositions, ai::AssetInstance; kwargs...)
    current_position = position(ai)
    
    if !isnothing(current_position)
        @info "Position update" asset=raw(ai) size=current_position.size side=current_position.side
        
        # Check margin requirements
        margin_ratio = maintenance(current_position)
        if margin_ratio < 0.1  # 10% maintenance margin
            @warn "Low margin ratio" ratio=margin_ratio
            # Consider reducing position or adding margin
        end
    end
end

# Handle leverage updates
function call!(s::MarginStrategy, ::UpdateLeverage, ai::AssetInstance, new_leverage::Float64; kwargs...)
    @info "Leverage update" asset=raw(ai) leverage=new_leverage
    
    # Validate leverage limits
    max_leverage = 10.0  # Example limit
    if new_leverage > max_leverage
        @error "Leverage too high" requested=new_leverage max=max_leverage
        return false
    end
    
    # Apply leverage change
    # (implementation depends on exchange API)
    return true
end
```

## Risk Management

### Order Validation

```julia
function validate_order(s::Strategy, order::Order, ai::AssetInstance)
    # Check available funds
    if isa(order, AnyBuyOrder)
        required_cash = order.amount * order.price
        available_cash = freecash(s)
        
        if required_cash > available_cash
            @error "Insufficient funds" required=required_cash available=available_cash
            return false
        end
    end
    
    # Check position limits
    current_position = get_position_size(ai)
    max_position = 1000.0  # Example limit
    
    if isa(order, AnyBuyOrder) && (current_position + order.amount) > max_position
        @error "Position limit exceeded" current=current_position order=order.amount max=max_position
        return false
    end
    
    # Check price reasonableness
    current_price = lastprice(ai)
    price_deviation = abs(order.price - current_price) / current_price
    
    if price_deviation > 0.1  # 10% deviation limit
        @warn "Large price deviation" order_price=order.price market_price=current_price deviation=price_deviation
    end
    
    return true
end
```

### Risk Monitoring

```julia
function monitor_risk(s::Strategy)
    total_exposure = 0.0
    
    for ai in assets(s)
        # Calculate exposure for each asset
        position_value = get_position_value(ai)
        total_exposure += abs(position_value)
        
        # Check individual asset limits
        max_asset_exposure = cash(s) * 0.2  # 20% per asset
        if abs(position_value) > max_asset_exposure
            @warn "Asset exposure limit exceeded" asset=raw(ai) exposure=position_value limit=max_asset_exposure
        end
    end
    
    # Check total exposure
    max_total_exposure = cash(s) * 0.8  # 80% total exposure
    if total_exposure > max_total_exposure
        @error "Total exposure limit exceeded" exposure=total_exposure limit=max_total_exposure
    end
end
```

## Performance Patterns

### Efficient Order Processing

```julia
# Batch order processing
function process_orders_batch(s::Strategy)
    all_orders = []
    
    # Collect all orders
    for ai in assets(s)
        append!(all_orders, orders(ai))
    end
    
    # Process in batches
    batch_size = 10
    for i in 1:batch_size:length(all_orders)
        batch = all_orders[i:min(i+batch_size-1, end)]
        process_order_batch(s, batch)
    end
end

# Async order monitoring
function monitor_orders_async(s::Strategy)
    @sync for ai in assets(s)
        @async begin
            orders_list = orders(ai)
            for order in orders_list
                monitor_single_order(s, order, ai)
            end
        end
    end
end
```

## Complete API Reference

```@autodocs
Modules = [Planar.Engine.Executors]
```

## See Also

- **[Strategies API](strategies.md)** - Strategy base classes and interfaces
- **[OrderTypes API](../reference/ordertypes.md)** - Order types and structures
- **[Engine API](engine.md)** - Core execution engine functions
- **[Instances API](instances.md)** - Asset instance management
- **[Strategy Development Guide](../guides/strategy-development.md)** - Building trading strategies
- **[Execution Modes Guide](../guides/execution-modes.md)** - Understanding different execution modes
