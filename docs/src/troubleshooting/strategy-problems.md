---
title: "Troubleshooting: Strategy Development Issues"
description: "Solutions for strategy development and execution problems"
category: "troubleshooting"
difficulty: "intermediate"
prerequisites: ["installation", "basic-strategy-concepts"]
related_topics: ["strategy-development", "execution-modes", "debugging"]
last_updated: "2025-10-04"
estimated_time: "20 minutes"
---

# Troubleshooting: Strategy Development Issues

This guide covers common problems encountered during strategy development, testing, and execution.

## Quick Diagnostics

1. **Check Strategy Loading** - Verify strategy can be loaded without errors
   ```julia
   using Strategies
   strategy = load_strategy(:MyStrategy)
   ```

2. **Validate Configuration** - Ensure strategy is properly configured in `user/planar.toml`

3. **Test Data Access** - Verify market data is available and accessible

## Strategy Loading and Compilation Issues

### Strategy Not Found

**Symptoms:**
- "Strategy not found" errors
- Module loading failures
- Path resolution issues

**Cause:**
Incorrect strategy configuration or file structure.

**Solution:**
```julia
# Check strategy configuration in user/planar.toml
[strategies.MyStrategy]
path = "strategies/MyStrategy"  # Correct path
# or
package = "MyStrategy"  # If using package format

# Verify file structure
# For path-based strategies:
user/strategies/MyStrategy/
├── Project.toml
├── src/
│   └── MyStrategy.jl
└── ...

# For package-based strategies:
MyStrategy/
├── Project.toml
├── src/
│   └── MyStrategy.jl
└── ...
```

**Verification:**
```julia
# Test strategy loading
using Strategies
try
    strategy = load_strategy(:MyStrategy)
    @info "Strategy loaded successfully"
catch e
    @error "Strategy loading failed" exception=e
end
```

### Compilation Errors

**Symptoms:**
- Syntax errors during strategy loading
- Missing function definitions
- Type-related compilation failures

**Cause:**
Syntax errors, missing dependencies, or incorrect function signatures.

**Solution:**
```julia
# Check for common syntax issues:

# 1. Missing module declaration
module MyStrategy
using Planar
# ... strategy code ...
end

# 2. Incorrect function signatures
# Bad: Missing required parameters
function generate_signals(data)
    # ...
end

# Good: Proper signature matching interface
function generate_signals(strategy, data, timestamp)
    # ...
end

# 3. Missing dependencies in Project.toml
[deps]
Planar = "..."
DataFrames = "..."
# Add all required packages
```

**Advanced Debugging:**
```julia
# Enable detailed compilation logging
ENV["JULIA_DEBUG"] = "MyStrategy"
using Logging
global_logger(ConsoleLogger(stderr, Logging.Debug))

# Test individual components
include("user/strategies/MyStrategy/src/MyStrategy.jl")
```

### Module Interface Issues

**Symptoms:**
- "Method not defined" errors
- Interface compliance failures
- Missing required functions

**Cause:**
Strategy doesn't implement required interface methods.

**Solution:**
```julia
# Ensure your strategy implements required interface:

module MyStrategy
using Planar

# Required: Strategy initialization
function initialize_strategy(config)
    # Initialize strategy state
    return strategy_state
end

# Required: Signal generation
function generate_signals(strategy, data, timestamp)
    # Generate trading signals
    return signals
end

# Required: Position sizing
function calculate_position_size(strategy, signal, balance)
    # Calculate position size
    return size
end

# Optional: Custom risk management
function apply_risk_management(strategy, position, market_data)
    # Apply risk rules
    return adjusted_position
end

end
```

## Strategy Execution Issues

### Runtime Errors During Execution

**Symptoms:**
- Errors during backtesting or live execution
- Unexpected behavior or results
- Data access failures

**Cause:**
Logic errors, data dependencies, or timing issues.

**Solution:**
```julia
# Step 1: Enable detailed logging
ENV["JULIA_DEBUG"] = "MyStrategy"
using Logging
global_logger(ConsoleLogger(stderr, Logging.Debug))

# Step 2: Test strategy components individually
strategy = load_strategy(:MyStrategy)

# Test data access
try
    data = get_market_data(strategy)
    @info "Data access successful" size=size(data)
catch e
    @error "Data access failed" exception=e
end

# Test signal generation
try
    signals = generate_signals(strategy, data, now())
    @info "Signal generation successful" signals
catch e
    @error "Signal generation failed" exception=e
end

# Step 3: Use simulation mode for debugging
using SimMode
sim = SimMode.Simulator(strategy)
try
    result = SimMode.run!(sim, start_date, end_date)
    @info "Simulation successful"
catch e
    @error "Simulation failed" exception=e
end
```

### Data Access Issues

**Symptoms:**
- "No data available" errors
- Inconsistent data quality
- Missing timeframes or symbols

**Cause:**
Data not fetched, incorrect timeframes, or exchange connectivity issues.

**Solution:**
```julia
using Data, Fetch

# Step 1: Verify data availability
zi = zinstance()
available_data = Data.list_available_data(zi, :binance)
@info "Available data" available_data

# Step 2: Fetch missing data
try
    data = fetch_ohlcv(:binance, "BTC/USDT", "1h", limit=1000)
    @info "Data fetch successful" size=size(data)
    
    # Save to database
    Data.save_ohlcv!(zi, :binance, "BTC/USDT", data)
catch e
    @error "Data fetch failed" exception=e
end

# Step 3: Validate data quality
function validate_ohlcv(data)
    # Check for missing values
    if any(ismissing, data)
        @warn "Missing values detected in data"
    end
    
    # Check for reasonable price ranges
    prices = data.close
    if any(p -> p <= 0, prices)
        @warn "Invalid price data detected"
    end
    
    # Check for proper time ordering
    if !issorted(data.timestamp)
        @warn "Data is not properly time-ordered"
    end
    
    return data
end

validated_data = validate_ohlcv(data)
```

### Signal Generation Problems

**Symptoms:**
- No signals generated
- Incorrect signal timing
- Signal validation failures

**Cause:**
Logic errors in signal generation, incorrect data handling, or parameter issues.

**Solution:**
```julia
# Debug signal generation step by step
function debug_signal_generation(strategy, data)
    @debug "Starting signal generation" data_size=nrow(data)
    
    # Check input data
    if nrow(data) == 0
        @error "No data provided for signal generation"
        return nothing
    end
    
    # Check for required columns
    required_cols = [:timestamp, :open, :high, :low, :close, :volume]
    missing_cols = setdiff(required_cols, names(data))
    if !isempty(missing_cols)
        @error "Missing required columns" missing=missing_cols
        return nothing
    end
    
    # Generate signals with error handling
    try
        signals = []
        for (i, row) in enumerate(eachrow(data))
            @debug "Processing row $i" timestamp=row.timestamp
            
            signal = compute_signal_for_row(strategy, row, data[1:i, :])
            push!(signals, signal)
            
            @debug "Generated signal" signal=signal
        end
        
        return signals
    catch e
        @error "Signal generation failed at processing" exception=e
        return nothing
    end
end

# Test with your strategy
signals = debug_signal_generation(strategy, sample_data)
```

## Order Execution Issues

### Orders Not Executing

**Symptoms:**
- Orders placed but not filled
- "Insufficient balance" errors
- Order rejection messages

**Cause:**
Balance issues, incorrect order parameters, or exchange connectivity problems.

**Solution:**
```julia
using OrderTypes

# Step 1: Check account balance
exchange = getexchange(:binance)
try
    balance = exchange.fetch_balance()
    @info "Account balance" balance
    
    # Check specific asset balance
    btc_balance = get(balance, "BTC", Dict("free" => 0.0))["free"]
    @info "BTC balance" balance=btc_balance
catch e
    @error "Balance check failed" exception=e
end

# Step 2: Validate order parameters
function validate_order(order, exchange)
    # Check order size against minimum requirements
    market = exchange.fetch_market(order.symbol)
    min_amount = get(market["limits"]["amount"], "min", 0.0)
    
    if order.amount < min_amount
        @error "Order amount below minimum" amount=order.amount min=min_amount
        return false
    end
    
    # Check order value against minimum notional
    if haskey(market["limits"], "cost")
        min_cost = get(market["limits"]["cost"], "min", 0.0)
        estimated_cost = order.amount * order.price  # For limit orders
        
        if estimated_cost < min_cost
            @error "Order value below minimum" cost=estimated_cost min=min_cost
            return false
        end
    end
    
    return true
end

# Step 3: Test order execution in paper mode first
using PaperMode
paper_exchange = PaperMode.PaperExchange(:binance)

order = MarketOrder(:buy, "BTC/USDT", 0.001)
if validate_order(order, paper_exchange)
    try
        result = place_order(paper_exchange, order)
        @info "Paper order successful" result
    catch e
        @error "Paper order failed" exception=e
    end
end
```

### Position Management Errors

**Symptoms:**
- Incorrect position sizes
- Position tracking inconsistencies
- Margin calculation errors

**Cause:**
Position sizing logic errors, margin miscalculations, or state management issues.

**Solution:**
```julia
# Debug position management
mutable struct PositionTracker
    positions::Dict{String, Float64}
    balances::Dict{String, Float64}
    margin_used::Float64
    
    PositionTracker() = new(Dict(), Dict(), 0.0)
end

function debug_position_management(tracker::PositionTracker, order)
    @debug "Position management" current_positions=tracker.positions
    
    # Calculate position change
    symbol = order.symbol
    side_multiplier = order.side == :buy ? 1.0 : -1.0
    position_change = order.amount * side_multiplier
    
    # Update position
    current_position = get(tracker.positions, symbol, 0.0)
    new_position = current_position + position_change
    
    @debug "Position update" symbol=symbol old=current_position new=new_position change=position_change
    
    # Validate position limits
    if abs(new_position) > get_max_position_size(symbol)
        @error "Position exceeds maximum allowed size" position=new_position max=get_max_position_size(symbol)
        return false
    end
    
    # Update tracker
    tracker.positions[symbol] = new_position
    
    return true
end

# Test position management
tracker = PositionTracker()
order = MarketOrder(:buy, "BTC/USDT", 0.1)
success = debug_position_management(tracker, order)
```

## Performance and Optimization Issues

### Slow Strategy Execution

**Symptoms:**
- Long backtesting times
- High CPU usage during execution
- Memory consumption issues

**Cause:**
Inefficient algorithms, excessive data copying, or unoptimized calculations.

**Solution:**
```julia
using Profile, BenchmarkTools

# Step 1: Profile strategy execution
@profile begin
    strategy = load_strategy(:MyStrategy)
    result = backtest(strategy, start_date, end_date)
end

Profile.print()

# Step 2: Benchmark specific functions
strategy = load_strategy(:MyStrategy)
sample_data = get_sample_data()

@benchmark generate_signals($strategy, $sample_data, $(now()))

# Step 3: Optimize common bottlenecks

# Bad: Inefficient data access
function slow_signal_generation(data)
    signals = []
    for i in 1:nrow(data)
        # Repeated data access
        price = data[i, :close]
        ma = mean(data[max(1, i-20):i, :close])  # Recalculates every time
        signal = price > ma ? 1 : -1
        push!(signals, signal)
    end
    return signals
end

# Good: Optimized version
function fast_signal_generation(data)
    prices = data.close
    n = length(prices)
    signals = Vector{Int}(undef, n)
    
    # Pre-calculate moving average
    window = 20
    ma = similar(prices)
    for i in 1:n
        start_idx = max(1, i - window + 1)
        ma[i] = mean(@view prices[start_idx:i])
    end
    
    # Vectorized signal generation
    signals .= ifelse.(prices .> ma, 1, -1)
    
    return signals
end
```

### Memory Usage Issues

**Symptoms:**
- Out of memory errors
- Slow garbage collection
- Excessive memory allocation

**Cause:**
Memory leaks, large object retention, or inefficient data structures.

**Solution:**
```julia
# Monitor memory usage
function monitor_memory(f, args...)
    gc_before = Base.gc_num()
    mem_before = Base.Sys.maxrss()
    
    result = f(args...)
    
    gc_after = Base.gc_num()
    mem_after = Base.Sys.maxrss()
    
    @info "Memory usage" allocated_mb=(mem_after - mem_before) / 1024^2 gc_time=(gc_after.total_time - gc_before.total_time) / 1e9
    
    return result
end

# Use with strategy execution
result = monitor_memory(backtest, strategy, start_date, end_date)

# Optimize memory usage
# Bad: Creates many temporary objects
function memory_heavy_strategy(data)
    results = []
    for row in eachrow(data)
        temp_data = DataFrame(row)  # Creates new DataFrame
        processed = process_row(temp_data)
        push!(results, processed)
    end
    return results
end

# Good: Reuse objects and use views
function memory_efficient_strategy(data)
    n = nrow(data)
    results = Vector{Float64}(undef, n)  # Pre-allocate
    
    for (i, row) in enumerate(eachrow(data))
        # Process row directly without creating temporary objects
        results[i] = process_row_values(row.open, row.high, row.low, row.close)
    end
    
    return results
end
```

## Debugging Strategies

### VSCode Debugging Setup

**Configuration for strategy debugging:**

```json
// In VSCode settings.json
{
    "julia.debuggerDefaultCompiled": [
        "ALL_MODULES_EXCEPT_MAIN",
        "-Base.CoreLogging"
    ]
}
```

**Using Infiltrator for interactive debugging:**
```julia
using Infiltrator

function my_strategy_function(data)
    # Strategy logic
    signals = calculate_signals(data)
    
    @infiltrate  # Drops into interactive debugging session
    
    # More logic after debugging
    return process_signals(signals)
end
```

### Logging and Diagnostics

**Comprehensive logging setup:**
```julia
using Logging

# Create custom logger with different levels
function setup_strategy_logging(level=Logging.Info)
    logger = ConsoleLogger(stderr, level)
    global_logger(logger)
    
    @info "Strategy logging enabled" level=level
end

# Use in strategy
function logged_strategy_function(data)
    @debug "Function entry" data_size=nrow(data)
    
    try
        result = risky_operation(data)
        @info "Operation successful" result_type=typeof(result)
        return result
    catch e
        @error "Operation failed" exception=(e, catch_backtrace())
        rethrow()
    end
end

# Enable debug logging for specific modules
ENV["JULIA_DEBUG"] = "MyStrategy,Strategies"
setup_strategy_logging(Logging.Debug)
```

## When to Seek Help

Contact the community if:
- Strategy logic is correct but execution fails consistently
- Performance issues persist after optimization attempts
- Errors occur that are not covered in this guide
- Integration with Planar framework components fails

## Getting Help

- [Community Resources](../resources/community.md)
- [GitHub Issues](https://github.com/defnlnotme/Planar.jl/issues)
- [Strategy Development Guide](../guides/strategy-development.md)
- [API Reference](../reference/) for function details

## See Also

- [Strategy Development](../guides/strategy-development.md) - Comprehensive development guide
- [Execution Modes](../guides/execution-modes.md) - Testing and deployment
- [Performance Issues](performance-issues.md) - Optimization techniques
- [Installation Issues](installation-issues.md) - Setup problems