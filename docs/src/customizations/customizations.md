---
category: "strategy-development"
difficulty: "advanced"
topics: [execution-modes, margin-trading, exchanges, data-management, optimization, strategy-development, troubleshooting]
last_updated: "2025-10-04"---
---

# Comprehensive Customization Guide

Planar's architecture is built around [Julia](https://julialang.org/)'s powerful [dispatch system](../guides/[strategy](../guides/strategy-development.md)-development.md#dispatch-system), enabling deep customization without modifying core framework code. This guide provides detailed instructions for extending Planar's functionality through custom implementations.

## Understanding Planar's Dispatch System

Planar leverages [Julia](https://julialang.org/)'s [multiple dispatch](../guides/[strategy](../guides/strategy-development.md)-development.md#dispatch-system) to provide customization points throughout the framework. The key insight is that behavior is determined by the combination of argument types, allowing you to specialize functionality for specific scenarios.

### Core Parametrized Types

The framework provides parametrized types for various elements:
- **Strategies**: `Strategy{Mode}` where `Mode` can be `Sim`, `Paper`, or `Live`
- **Assets**: `Asset`, `Derivative` and other `AbstractAsset` subtypes
- **Instances**: `AssetInstance{Asset, Exchange}` combining assets with [exchanges](../exchanges.md)
- **Orders and Trades**: `Order{OrderType}` and `Trade{OrderType}`
- **Exchanges**: `Exchange` subtypes with `ExchangeID` parameters

### Dispatch Patterns

Planar uses several dispatch patterns for customization:

```julia
# Strategy-specific behavior
function my_function(s::Strategy{Sim}, args...)
    # Simulation-specific implementation
end

function my_function(s::Strategy{Live}, args...)
    # Live trading-specific implementation
end

# Exchange-specific behavior
function my_function(ai::AssetInstance{A, ExchangeID{:binance}}, args...) where A
    # Binance-specific implementation
end

# Order type-specific behavior
function my_function(order::Order{MyCustomOrderType}, args...)
    # Custom order handling
end
```

## Custom Order Types Implementation

### Basic Order Type Definition

To implement a custom order type, create an abstract type inheriting from `OrderType`:

```julia
using OrderTypes

# Define the abstract order type
abstract type TrailingStopOrderType{S} <: OrderType{S} end

# Use the @deforders macro to generate concrete types
@deforders TrailingStop
```

This creates `TrailingStopOrder`, `TrailingStopBuy`, and `TrailingStopSell` types.

### Order State Management

Custom orders often require additional state. Define a state structure:

```julia
const _TrailingStopState = NamedTuple{
    (:committed, :filled, :trades, :trail_amount, :highest_price, :lowest_price),
    Tuple{Vector{Float64}, Vector{Float64}, Vector{Trade}, Float64, Float64, Float64}
}

function trailing_stop_state(
    committed::Vector{T},
    filled::Vector{Float64} = [0.0],
    trades::Vector{Trade} = Vector{Trade}(),
    trail_amount::Float64 = 0.0
) where T
    _TrailingStopState((
        committed, filled, trades, trail_amount,
        -Inf, Inf  # Initialize price tracking
    ))
end
```

### Order Constructor

Implement a constructor for your custom order:

```julia
function trailing_stop_order(
    ai::AssetInstance,
    ::SanitizeOff;
    amount::Float64,
    trail_amount::Float64,
    committed::Vector{Float64},
    date::DateTime,
    side::Type{<:OrderSide} = Sell
)
    # Validation
    trail_amount > 0 || return nothing
    iscost(ai, amount, trail_amount) || return nothing
    
    # Create order with custom state
    OrderTypes.Order(
        ai,
        TrailingStopOrderType{side};
        date,
        price = 0.0,  # Will be determined dynamically
        amount,
        committed,
        attrs = trailing_stop_state(committed, [0.0], Vector{Trade}(), trail_amount)
    )
end
```

### Order Execution Logic

Implement the execution logic for different modes:

```julia
# Simulation mode execution
function call!(
    s::Strategy{Sim},
    ::Type{Order{<:TrailingStopOrderType}},
    ai::AssetInstance;
    date::DateTime,
    amount::Float64,
    trail_amount::Float64,
    side::Type{<:OrderSide} = Sell,
    kwargs...
)
    order = trailing_stop_order(ai, SanitizeOff(); amount, trail_amount, [amount], date, side)
    isnothing(order) && return nothing
    
    # Check if order can be committed
    iscommittable(s, order, ai) || return nothing
    
    # Update trailing stop logic
    current_price = closeat(ai, date)
    if side == Sell
        # Update highest price for sell trailing stop
        order.attrs = merge(order.attrs, (highest_price = max(order.attrs.highest_price, current_price),))
        trigger_price = order.attrs.highest_price - trail_amount
        
        if current_price <= trigger_price
            # Execute as market order
            return execute_market_order(s, ai, order, date)
        end
    else
        # Update lowest price for buy trailing stop
        order.attrs = merge(order.attrs, (lowest_price = min(order.attrs.lowest_price, current_price),))
        trigger_price = order.attrs.lowest_price + trail_amount
        
        if current_price >= trigger_price
            # Execute as market order
            return execute_market_order(s, ai, order, date)
        end
    end
    
    # Order not triggered, store for next iteration
    store_pending_order(s, order)
    return nothing
end

# Live mode execution
function call!(
    s::Strategy{Live},
    ::Type{Order{<:TrailingStopOrderType}},
    ai::AssetInstance{A, ExchangeID{:binance}};
    kwargs...
) where A
    # Use Binance's native trailing stop functionality
    [exchange](../[exchanges](../exchanges.md).md) = get_exchange(ai)
    return [exchange](../[exchanges](../exchanges.md).md).create_trailing_stop_order(
        symbol = string(ai.asset),
        amount = kwargs[:amount],
        trail_amount = kwargs[:trail_amount],
        side = lowercase(string(kwargs[:side]))
    )
end
```

## Custom Exchange Implementation

### Exchange Interface Requirements

To implement a custom [exchange](../exchanges.md), you need to satisfy the interface defined by the `check` function in the `Exchanges` module. Here's a comprehensive example:

```julia
using Exchanges
using HTTP, JSON3

struct MyBrokerExchange <: Exchange
    api_key::String
    secret_key::String
    base_url::String
    rate_limiter::RateLimiter
    
    function MyBrokerExchange(api_key::String, secret_key::String)
        new(api_key, secret_key, "https://api.mybroker.com", RateLimiter(10, 1.0))
    end
end

# Implement required interface methods
function Exchanges.fetch_ticker(exchange::MyBrokerExchange, symbol::String)
    url = "$(exchange.base_url)/ticker/$(symbol)"
    response = HTTP.get(url, headers = auth_headers(exchange))
    data = JSON3.read(response.body)
    
    return Dict(
        "symbol" => symbol,
        "bid" => data.bid,
        "ask" => data.ask,
        "last" => data.last,
        "timestamp" => data.timestamp
    )
end

function Exchanges.fetch_ohlcv(
    exchange::MyBrokerExchange,
    symbol::String,
    [timeframe](../guides/data-management.md#timeframes)::String,
    since::Union{Int, Nothing} = nothing,
    limit::Union{Int, Nothing} = nothing
)
    params = Dict("symbol" => symbol, "interval" => [timeframe](../guides/data-management.md#timeframes))
    since !== nothing && (params["startTime"] = since)
    limit !== nothing && (params["limit"] = limit)
    
    url = "$(exchange.base_url)/klines"
    response = HTTP.get(url, query = params, headers = auth_headers(exchange))
    data = JSON3.read(response.body)
    
    return [
        [row.timestamp, row.open, row.high, row.low, row.close, row.volume]
        for row in data
    ]
end

function Exchanges.create_order(
    exchange::MyBrokerExchange,
    symbol::String,
    type::String,
    side::String,
    amount::Float64,
    price::Union{Float64, Nothing} = nothing;
    kwargs...
)
    rate_limit!(exchange.rate_limiter)
    
    params = Dict(
        "symbol" => symbol,
        "side" => uppercase(side),
        "type" => uppercase(type),
        "quantity" => string(amount)
    )
    
    if type == "limit" && price !== nothing
        params["price"] = string(price)
    end
    
    # Add any additional parameters
    for (key, value) in kwargs
        params[string(key)] = string(value)
    end
    
    url = "$(exchange.base_url)/order"
    response = HTTP.post(
        url,
        headers = auth_headers(exchange),
        body = JSON3.write(params)
    )
    
    return JSON3.read(response.body)
end

# Helper functions
function auth_headers(exchange::MyBrokerExchange)
    timestamp = string(Int(time() * 1000))
    signature = generate_signature(exchange.secret_key, timestamp)
    
    return [
        "X-API-KEY" => exchange.api_key,
        "X-TIMESTAMP" => timestamp,
        "X-SIGNATURE" => signature,
        "Content-Type" => "application/json"
    ]
end

function generate_signature(secret::String, timestamp::String)
    # Implement your broker's signature algorithm
    # This is typically HMAC-SHA256
    import SHA
    return bytes2hex(SHA.hmac_sha256(secret, timestamp))
end
```

### Exchange-Specific Customizations

You can customize behavior for specific exchanges using dispatch:

```julia
# Custom order handling for your broker
function call!(
    s::Strategy{Live},
    ::Type{Order{LimitOrderType}},
    ai::AssetInstance{A, MyBrokerExchange};
    kwargs...
) where A
    # Custom limit order logic for MyBroker
    exchange = get_exchange(ai)
    
    # MyBroker requires special handling for limit orders
    result = create_order(
        exchange,
        string(ai.asset),
        "limit",
        lowercase(string(kwargs[:side])),
        kwargs[:amount],
        kwargs[:price];
        time_in_force = "GTC",  # MyBroker-specific parameter
        post_only = true        # MyBroker-specific parameter
    )
    
    return convert_to_planar_trade(result)
end

# Custom fee calculation
function calculate_fees(
    ai::AssetInstance{A, MyBrokerExchange},
    amount::Float64,
    price::Float64
) where A
    # MyBroker has tiered fee structure
    volume_30d = get_30day_volume(ai)
    
    if volume_30d > 1_000_000
        return amount * price * 0.001  # 0.1% for high volume
    else
        return amount * price * 0.002  # 0.2% for regular users
    end
end
```

## Advanced Customization Patterns

### Strategy-Specific Functions

Create "snowflake" functions for specific [strategies](../guides/strategy-development.md):

```julia
# General implementation
function calculate_position_size(s::Strategy, ai::AssetInstance, signal_strength::Float64)
    # Default position sizing logic
    return s.base_position_size * signal_strength
end

# Strategy-specific implementation
function calculate_position_size(
    s::Strategy{Mode, MyAggressiveStrategy},
    ai::AssetInstance,
    signal_strength::Float64
) where Mode
    # Aggressive [strategy](../guides/strategy-development.md) uses higher [leverage](../guides/strategy-development.md#margin-modes)
    return s.base_position_size * signal_strength * 2.0
end

# Mode and strategy-specific implementation
function calculate_position_size(
    s::Strategy{Live, MyAggressiveStrategy},
    ai::AssetInstance,
    signal_strength::Float64
)
    # Even more conservative in live mode
    base_size = s.base_position_size * signal_strength * 2.0
    return min(base_size, s.max_live_position)
end
```

### Custom Indicators and Signals

Extend the framework with custom [technical indicators](../guides/strategy-development.md#technical-indicators):

```julia
using Statistics

# Define custom indicator
struct CustomMomentumIndicator
    period::Int
    threshold::Float64
end

function calculate_indicator(
    indicator::CustomMomentumIndicator,
    prices::Vector{Float64}
)
    length(prices) < indicator.period && return nothing
    
    recent_prices = prices[end-indicator.period+1:end]
    momentum = (recent_prices[end] - recent_prices[1]) / recent_prices[1]
    
    return momentum > indicator.threshold ? 1.0 : 
           momentum < -indicator.threshold ? -1.0 : 0.0
end

# Integrate with strategy
function generate_signals(
    s::Strategy,
    ai::AssetInstance,
    date::DateTime
)
    prices = get_price_history(ai, date, 50)  # Get last 50 prices
    indicator = CustomMomentumIndicator(20, 0.05)  # 20-period, 5% threshold
    
    signal = calculate_indicator(indicator, prices)
    return signal
end
```

### Custom Risk Management

Implement sophisticated risk management:

```julia
abstract type RiskManager end

struct AdvancedRiskManager <: RiskManager
    max_portfolio_risk::Float64
    max_position_risk::Float64
    correlation_threshold::Float64
    drawdown_limit::Float64
end

function check_risk_limits(
    rm::AdvancedRiskManager,
    s::Strategy,
    proposed_trade::Order
)
    # Check individual position risk
    position_risk = calculate_position_risk(s, proposed_trade)
    if position_risk > rm.max_position_risk
        @warn "Position risk too high: $position_risk > $(rm.max_position_risk)"
        return false
    end
    
    # Check portfolio risk
    portfolio_risk = calculate_portfolio_risk(s, proposed_trade)
    if portfolio_risk > rm.max_portfolio_risk
        @warn "Portfolio risk too high: $portfolio_risk > $(rm.max_portfolio_risk)"
        return false
    end
    
    # Check correlation limits
    if violates_correlation_limits(s, proposed_trade, rm.correlation_threshold)
        @warn "Trade violates correlation limits"
        return false
    end
    
    # Check drawdown limits
    current_drawdown = calculate_current_drawdown(s)
    if current_drawdown > rm.drawdown_limit
        @warn "Current drawdown exceeds limit: $current_drawdown > $(rm.drawdown_limit)"
        return false
    end
    
    return true
end

# Integrate risk management into order execution
function call!(
    s::Strategy{Mode, MyRiskManagedStrategy},
    order_type::Type{<:Order},
    ai::AssetInstance;
    kwargs...
) where Mode
    # Create proposed order
    proposed_order = create_order(order_type, ai; kwargs...)
    
    # Check risk limits
    risk_manager = s.risk_manager
    if !check_risk_limits(risk_manager, s, proposed_order)
        @info "Order rejected by risk management"
        return nothing
    end
    
    # Proceed with normal execution
    return call_original(s, order_type, ai; kwargs...)
end
```

## Best Practices for Customization

### 1. Minimal Invasive Changes

Only override the specific functions that need customization. Leverage existing functionality wherever possible:

```julia
# Good: Override only the specific behavior
function calculate_slippage(
    ai::AssetInstance{A, MyExchange},
    order::Order{MarketOrderType},
    volume::Float64
) where A
    # Custom slippage calculation for MyExchange
    base_slippage = calculate_slippage_default(ai, order, volume)
    return base_slippage * 1.2  # MyExchange has higher slippage
end

# Avoid: Reimplementing entire order execution
```

### 2. Type Stability

Ensure your customizations maintain type stability:

```julia
# Good: Type-stable implementation
function my_custom_function(x::Float64)::Float64
    return x * 2.0
end

# Avoid: Type-unstable implementation
function my_custom_function(x)
    if x > 0
        return x * 2.0
    else
        return "negative"  # Type instability
    end
end
```

### 3. Error Handling

Implement robust error handling in custom functions:

```julia
function custom_order_execution(
    s::Strategy,
    ai::AssetInstance,
    order::Order;
    kwargs...
)
    try
        # Attempt custom execution
        result = execute_custom_logic(s, ai, order; kwargs...)
        return result
    catch e
        @error "Custom order execution failed" exception=e
        
        # Fallback to default behavior
        @info "Falling back to default execution"
        return call_default(s, ai, order; kwargs...)
    end
end
```

### 4. Documentation and Testing

Document your customizations thoroughly:

```julia
"""
    custom_momentum_strategy(s::Strategy, ai::AssetInstance, date::DateTime)

Custom momentum strategy implementation that uses a combination of [RSI](../guides/strategy-development.md#technical-indicators) and MACD
indicators to generate trading signals.

# Arguments
- `s::Strategy`: The strategy instance
- `ai::AssetInstance`: The asset instance to trade
- `date::DateTime`: Current timestamp

# Returns
- `Float64`: Signal strength between -1.0 (strong sell) and 1.0 (strong buy)

# Example
```julia
signal = custom_momentum_strategy(strategy, btc_usdt, DateTime(2023, 1, 1))
if signal > 0.5
    # Execute buy order
    call!(strategy, Order{MarketBuy}, btc_usdt; amount=100.0)
end
```
"""
function custom_momentum_strategy(s::Strategy, ai::AssetInstance, date::DateTime)
    # Implementation here
end
```

### 5. Performance Considerations

Be mindful of performance in hot paths:

```julia
# Use @inbounds for performance-critical loops (when bounds are guaranteed)
function fast_calculation(data::Vector{Float64})
    result = 0.0
    @inbounds for i in 1:length(data)
        result += data[i] * 0.5
    end
    return result
end

# Pre-allocate arrays to avoid allocations
function efficient_processing(input::Vector{Float64})
    output = Vector{Float64}(undef, length(input))
    @inbounds for i in eachindex(input, output)
        output[i] = process_element(input[i])
    end
    return output
end
```


## See Also

- **[Exchanges](../exchanges.md)** - Exchange integration and configuration
- **[Config](../config.md)** - Exchange integration and configuration
- **[Overview](../troubleshooting/index.md)** - Troubleshooting: Troubleshooting and problem resolution
- **[Optimization](../optimization.md)** - Performance optimization techniques
- **[Performance Issues](../troubleshooting/performance-issues.md)** - Troubleshooting: Performance optimization techniques
- **[Data Management](../guides/data-management.md)** - Guide: Data handling and management

## Troubleshooting Customizations

### Common Issues

1. **Method Ambiguity**: When [multiple dispatch](../guides/strategy-development.md#dispatch-system) signatures could match
```julia
# Problem: Ambiguous methods
function my_function(::Strategy{Sim}, ::AssetInstance) end
function my_function(::Strategy, ::AssetInstance{Asset}) end

# Solution: Make signatures more specific
function my_function(::Strategy{Sim}, ::AssetInstance{Asset}) end
function my_function(::Strategy{Sim}, ::AssetInstance{Derivative}) end
```

2. **Type Piracy**: Extending methods you don't own on types you don't own
```julia
# Avoid: Type piracy
Base.+(::String, ::Int) = error("Don't do this")

# Better: Create wrapper types or use your own functions
struct MyString
    value::String
end
Base.+(s::MyString, i::Int) = MyString(s.value * string(i))
```

3. **Performance Issues**: Customizations that hurt performance
```julia
# Problem: Type instability
function slow_function(x)
    if rand() > 0.5
        return x
    else
        return string(x)  # Type instability
    end
end

# Solution: Maintain type stability
function fast_function(x::T)::T where T
    # Always return the same type
    return x * (rand() > 0.5 ? 1 : -1)
end
```

### Debugging Tips

1. Use `@code_warntype` to check for type instabilities
2. Use `@benchmark` to measure performance impact
3. Use `methodswith` to find all methods for a type
4. Use `@which` to determine which method will be called

Remember to [leverage](../guides/strategy-development.md#margin-modes) this flexibility to enhance functionality without overcomplicating the system, thus avoiding "complexity bankruptcy."
