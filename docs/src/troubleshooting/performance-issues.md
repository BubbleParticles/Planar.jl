---
title: "Troubleshooting: Performance Issues"
description: "Solutions for performance and optimization problems"
category: "troubleshooting"
difficulty: "advanced"
prerequisites: ["strategy-development", "basic-profiling"]
related_topics: ["optimization", "memory-management", "profiling"]
last_updated: "2025-10-04"
estimated_time: "25 minutes"
---

# Troubleshooting: Performance Issues

This guide covers performance problems and optimization techniques for Planar strategies and operations.

## Quick Diagnostics

1. **Profile Execution** - Identify performance bottlenecks
   ```julia
   using Profile
   @profile your_slow_function()
   Profile.print()
   ```

2. **Monitor Memory** - Check for memory leaks and excessive allocations
   ```julia
   using BenchmarkTools
   @benchmark your_function($args)
   ```

3. **Check System Resources** - Verify CPU, memory, and I/O utilization

## Strategy Execution Performance

### Slow Backtesting

**Symptoms:**
- Backtesting takes much longer than expected
- High CPU usage during strategy execution
- Unresponsive system during backtesting

**Cause:**
Inefficient algorithms, excessive data copying, or unoptimized calculations.

**Diagnostic Steps:**
```julia
using Profile, ProfileView

# Profile strategy execution
@profile begin
    strategy = load_strategy(:MyStrategy)
    result = backtest(strategy, start_date, end_date)
end

# View results
Profile.print()
ProfileView.view()  # Interactive flame graph

# Focus on specific functions
Profile.print(format=:flat, sortedby=:count)
```

**Solutions:**

**1. Optimize Data Access Patterns**
```julia
# Bad: Repeated data lookups
function slow_signal_generation(data)
    signals = []
    for i in 1:nrow(data)
        price = data[i, :close]  # Repeated DataFrame access
        ma = mean(data[max(1, i-20):i, :close])  # Recalculates every time
        signal = price > ma ? 1 : -1
        push!(signals, signal)  # Dynamic array growth
    end
    return signals
end

# Good: Vectorized operations and pre-allocation
function fast_signal_generation(data)
    prices = data.close  # Extract column once
    n = length(prices)
    signals = Vector{Int}(undef, n)  # Pre-allocate
    
    # Calculate moving average efficiently
    window = 20
    for i in window:n
        ma = mean(@view prices[i-window+1:i])  # Use view to avoid copying
        signals[i] = prices[i] > ma ? 1 : -1
    end
    
    return signals
end
```

**2. Use Efficient Data Structures**
```julia
# Bad: Using DataFrames for simple operations
function inefficient_processing(data::DataFrame)
    results = DataFrame()
    for row in eachrow(data)
        processed = DataFrame(
            timestamp = [row.timestamp],
            value = [process_value(row.close)]
        )
        results = vcat(results, processed)  # Expensive concatenation
    end
    return results
end

# Good: Use arrays and batch operations
function efficient_processing(data::DataFrame)
    n = nrow(data)
    timestamps = data.timestamp
    values = Vector{Float64}(undef, n)
    
    # Vectorized processing
    values .= process_value.(data.close)
    
    return DataFrame(timestamp=timestamps, value=values)
end
```

**3. Minimize Memory Allocations**
```julia
# Bad: Creates temporary objects in loops
function allocation_heavy(data)
    results = []
    for i in 1:length(data)
        temp = [data[i] * 2, data[i] * 3]  # New array each iteration
        push!(results, sum(temp))
    end
    return results
end

# Good: Reuse objects and avoid temporaries
function allocation_light(data)
    n = length(data)
    results = Vector{Float64}(undef, n)
    
    for i in 1:n
        # Direct calculation without temporary arrays
        results[i] = data[i] * 2 + data[i] * 3
    end
    
    return results
end
```

### Memory Usage Issues

**Symptoms:**
- High memory consumption during execution
- Out of memory errors
- Slow garbage collection pauses

**Cause:**
Memory leaks, large object retention, or inefficient data handling.

**Diagnostic Steps:**
```julia
# Monitor memory usage during execution
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

# Detailed allocation tracking
using BenchmarkTools
@benchmark backtest($strategy, $start_date, $end_date)
```

**Solutions:**

**1. Use Views Instead of Copies**
```julia
# Bad: Creates copies of data
function copy_heavy(data)
    subset = data[1000:2000, :]  # Creates new DataFrame
    return process_data(subset)
end

# Good: Uses views to avoid copying
function view_efficient(data)
    subset = @view data[1000:2000, :]  # No copying
    return process_data(subset)
end
```

**2. Implement Chunked Processing**
```julia
function process_large_dataset(data; chunk_size=10000)
    results = []
    n_chunks = div(nrow(data), chunk_size) + 1
    
    for i in 1:n_chunks
        start_idx = (i-1) * chunk_size + 1
        end_idx = min(i * chunk_size, nrow(data))
        
        if start_idx <= nrow(data)
            chunk = @view data[start_idx:end_idx, :]
            chunk_result = process_chunk(chunk)
            push!(results, chunk_result)
            
            # Force garbage collection periodically
            if i % 10 == 0
                GC.gc()
            end
        end
    end
    
    return vcat(results...)
end
```

**3. Manage Object Lifecycles**
```julia
# Use mutable structs to reuse objects
mutable struct StrategyState
    signals::Vector{Float64}
    positions::Vector{Float64}
    temp_buffer::Vector{Float64}
    
    function StrategyState(n::Int)
        new(
            Vector{Float64}(undef, n),
            Vector{Float64}(undef, n),
            Vector{Float64}(undef, 100)  # Reusable buffer
        )
    end
end

function update_strategy!(state::StrategyState, data, index)
    # Reuse pre-allocated arrays
    fill!(state.temp_buffer, 0.0)
    
    # Update in-place when possible
    state.signals[index] = calculate_signal(data, state.temp_buffer)
    state.positions[index] = calculate_position(state.signals[index])
end
```

## Data-Related Performance Issues

### Slow Data Loading

**Symptoms:**
- Long delays when loading historical data
- High I/O wait times
- Database query timeouts

**Cause:**
Inefficient data access patterns, large dataset sizes, or database configuration issues.

**Solutions:**

**1. Optimize Data Loading Patterns**
```julia
using Data

# Bad: Loading all data at once
function load_all_data(exchange, symbol, timeframe, start_date, end_date)
    return load_ohlcv(exchange, symbol, timeframe, start_date, end_date)
end

# Good: Progressive loading with caching
function load_data_progressively(exchange, symbol, timeframe, start_date, end_date; chunk_days=30)
    cache = Dict()
    results = []
    current_date = start_date
    
    while current_date < end_date
        chunk_end = min(current_date + Day(chunk_days), end_date)
        
        # Check cache first
        cache_key = (current_date, chunk_end)
        if haskey(cache, cache_key)
            chunk_data = cache[cache_key]
        else
            chunk_data = load_ohlcv(exchange, symbol, timeframe, current_date, chunk_end)
            cache[cache_key] = chunk_data
        end
        
        push!(results, chunk_data)
        current_date = chunk_end
    end
    
    return vcat(results...)
end
```

**2. Database Performance Optimization**
```julia
using Data

# Optimize LMDB settings
zi = zinstance()
Data.mapsize!(zi, 4096)  # Increase map size to 4GB

# Use batch operations for better performance
function batch_save_data(zi, exchange, symbol_data_pairs)
    # Group operations for better I/O efficiency
    Data.batch_save_ohlcv!(zi, exchange, symbol_data_pairs)
end

# Implement data compression for storage
function compress_and_save(zi, exchange, symbol, data)
    # Use Zarr for large datasets with compression
    compressed_data = compress_ohlcv(data)
    Data.save_compressed_ohlcv!(zi, exchange, symbol, compressed_data)
end
```

**3. Zarr Array Optimization**
```julia
# Configure optimal chunk sizes for your access patterns
function create_optimized_zarr(data_shape, access_pattern=:temporal)
    if access_pattern == :temporal
        # Optimize for time-series access
        chunk_size = (min(10000, data_shape[1]), data_shape[2])
    else
        # Optimize for cross-sectional access
        chunk_size = (1000, data_shape[2])
    end
    
    return zarr_create(Float64, data_shape, chunks=chunk_size, compressor="blosc")
end
```

### Database Performance Issues

**Symptoms:**
- Slow database queries
- High disk I/O usage
- Database lock contention

**Cause:**
Suboptimal database configuration, concurrent access issues, or inefficient queries.

**Solutions:**

**1. LMDB Configuration Optimization**
```julia
using Data

# Increase database size proactively
zi = zinstance()
current_size = Data.mapsize(zi)
@info "Current LMDB size: $(current_size)MB"

# Set appropriate size based on data volume
Data.mapsize!(zi, 8192)  # 8GB for large datasets

# Monitor and adjust as needed
function monitor_db_usage(zi)
    stats = Data.get_db_stats(zi)
    usage_percent = (stats.used_size / stats.total_size) * 100
    
    if usage_percent > 80
        @warn "Database approaching capacity" usage=usage_percent
        # Automatically increase size
        new_size = Int(stats.total_size * 1.5)
        Data.mapsize!(zi, new_size)
    end
end
```

**2. Batch Operations**
```julia
# Bad: Individual save operations
function save_data_individually(zi, exchange, symbols, data_dict)
    for symbol in symbols
        Data.save_ohlcv!(zi, exchange, symbol, data_dict[symbol])
    end
end

# Good: Batch operations
function save_data_batch(zi, exchange, symbols, data_dict)
    batch_data = [(symbol, data_dict[symbol]) for symbol in symbols]
    Data.batch_save_ohlcv!(zi, exchange, batch_data)
end
```

**3. Concurrent Access Management**
```julia
using Base.Threads

# Implement proper locking for concurrent access
const DB_LOCK = ReentrantLock()

function thread_safe_data_access(zi, operation, args...)
    lock(DB_LOCK) do
        return operation(zi, args...)
    end
end

# Use thread-safe operations
@threads for symbol in symbols
    data = thread_safe_data_access(zi, Data.load_ohlcv, exchange, symbol, timeframe)
    process_symbol_data(symbol, data)
end
```

## Optimization and Backtesting Performance

### Slow Parameter Optimization

**Symptoms:**
- Parameter optimization takes excessive time
- Poor convergence in optimization algorithms
- Inefficient parameter space exploration

**Cause:**
Large parameter spaces, inefficient optimization algorithms, or redundant calculations.

**Solutions:**

**1. Efficient Parameter Space Design**
```julia
using Optim

# Bad: Too fine-grained parameter space
param_ranges = Dict(
    :param1 => 0.01:0.001:0.1,  # 91 values
    :param2 => 1:0.1:10,        # 91 values
    :param3 => 0.1:0.01:1.0     # 91 values
)
# Total combinations: 91^3 = 753,571

# Good: Coarse-to-fine optimization
function coarse_to_fine_optimization(strategy, data)
    # Phase 1: Coarse grid
    coarse_ranges = Dict(
        :param1 => 0.01:0.02:0.1,  # 5 values
        :param2 => 1:2:10,         # 5 values
        :param3 => 0.1:0.2:1.0     # 5 values
    )
    
    coarse_best = grid_search(strategy, data, coarse_ranges)
    
    # Phase 2: Fine-tune around best
    fine_ranges = Dict(
        :param1 => (coarse_best.param1 - 0.02):0.005:(coarse_best.param1 + 0.02),
        :param2 => (coarse_best.param2 - 2):0.5:(coarse_best.param2 + 2),
        :param3 => (coarse_best.param3 - 0.2):0.05:(coarse_best.param3 + 0.2)
    )
    
    return grid_search(strategy, data, fine_ranges)
end
```

**2. Parallel Optimization**
```julia
using Distributed

# Add worker processes
addprocs(4)

@everywhere using Planar, Strategies

# Parallel parameter evaluation
function parallel_optimization(strategy, data, param_combinations)
    results = @distributed (vcat) for params in param_combinations
        try
            # Configure strategy with parameters
            configured_strategy = configure_strategy(strategy, params)
            
            # Run backtest
            result = backtest(configured_strategy, data)
            
            # Return parameter set and performance
            [(params, result.sharpe_ratio)]
        catch e
            @warn "Parameter evaluation failed" params=params exception=e
            [(params, -Inf)]
        end
    end
    
    # Find best parameters
    best_idx = argmax([r[2] for r in results])
    return results[best_idx]
end
```

**3. Smart Optimization Algorithms**
```julia
using Optim, BlackBoxOptim

# Use efficient optimization algorithms
function bayesian_optimization(strategy, data, param_bounds)
    function objective(params)
        try
            configured_strategy = configure_strategy(strategy, params)
            result = backtest(configured_strategy, data)
            return -result.sharpe_ratio  # Minimize negative Sharpe
        catch e
            return 1000.0  # Penalty for failed evaluations
        end
    end
    
    # Use Bayesian optimization for efficient search
    result = bboptimize(objective, param_bounds, 
                       MaxFuncEvals=100,  # Limit evaluations
                       Method=:adaptive_de_rand_1_bin)
    
    return best_candidate(result)
end

# Implement early stopping
function optimization_with_early_stopping(strategy, data, params; patience=10)
    best_score = -Inf
    no_improvement = 0
    
    for (i, param_set) in enumerate(params)
        score = evaluate_parameters(strategy, data, param_set)
        
        if score > best_score
            best_score = score
            no_improvement = 0
        else
            no_improvement += 1
        end
        
        # Early stopping if no improvement
        if no_improvement >= patience
            @info "Early stopping at iteration $i"
            break
        end
    end
    
    return best_score
end
```

## System-Level Performance Issues

### CPU Bottlenecks

**Symptoms:**
- High CPU usage during execution
- Single-threaded performance limitations
- CPU-bound operations

**Solutions:**

**1. Parallel Processing**
```julia
using Base.Threads

# Parallelize independent operations
function parallel_signal_generation(strategies, data)
    results = Vector{Any}(undef, length(strategies))
    
    @threads for i in 1:length(strategies)
        results[i] = generate_signals(strategies[i], data)
    end
    
    return results
end

# Use SIMD for vectorized operations
using SIMD

function simd_moving_average(prices::Vector{Float64}, window::Int)
    n = length(prices)
    result = Vector{Float64}(undef, n)
    
    @simd for i in window:n
        sum_val = 0.0
        @simd for j in (i-window+1):i
            sum_val += prices[j]
        end
        result[i] = sum_val / window
    end
    
    return result
end
```

**2. Algorithm Optimization**
```julia
# Use more efficient algorithms
function efficient_technical_indicators(prices)
    n = length(prices)
    
    # Exponential moving average (more efficient than simple MA)
    ema = Vector{Float64}(undef, n)
    alpha = 0.1
    ema[1] = prices[1]
    
    for i in 2:n
        ema[i] = alpha * prices[i] + (1 - alpha) * ema[i-1]
    end
    
    return ema
end

# Cache expensive calculations
const CALCULATION_CACHE = Dict()

function cached_expensive_calculation(key, data)
    if haskey(CALCULATION_CACHE, key)
        return CALCULATION_CACHE[key]
    end
    
    result = expensive_calculation(data)
    CALCULATION_CACHE[key] = result
    return result
end
```

### I/O Performance Issues

**Symptoms:**
- Slow file operations
- High disk usage
- Network latency issues

**Solutions:**

**1. Asynchronous I/O**
```julia
using Base.Threads

# Asynchronous data fetching
function async_data_fetch(symbols, exchange, timeframe)
    tasks = []
    
    for symbol in symbols
        task = @async begin
            try
                fetch_ohlcv(exchange, symbol, timeframe)
            catch e
                @warn "Failed to fetch data" symbol=symbol exception=e
                nothing
            end
        end
        push!(tasks, task)
    end
    
    # Wait for all tasks to complete
    results = []
    for task in tasks
        result = fetch(task)
        if result !== nothing
            push!(results, result)
        end
    end
    
    return results
end
```

**2. I/O Optimization**
```julia
# Batch file operations
function batch_file_operations(file_operations)
    # Group operations by directory
    grouped_ops = Dict()
    for (op_type, path, data) in file_operations
        dir = dirname(path)
        if !haskey(grouped_ops, dir)
            grouped_ops[dir] = []
        end
        push!(grouped_ops[dir], (op_type, path, data))
    end
    
    # Execute operations by directory
    for (dir, ops) in grouped_ops
        cd(dir) do
            for (op_type, path, data) in ops
                if op_type == :write
                    write(basename(path), data)
                elseif op_type == :read
                    read(basename(path))
                end
            end
        end
    end
end
```

## Advanced Performance Monitoring

### Comprehensive Performance Profiling

```julia
using Profile, ProfileView, BenchmarkTools

# Complete performance analysis
function comprehensive_performance_analysis(f, args...)
    println("=== Performance Analysis ===")
    
    # 1. Benchmark execution
    println("\n1. Benchmark Results:")
    benchmark_result = @benchmark $f($args...)
    display(benchmark_result)
    
    # 2. Memory allocation analysis
    println("\n2. Memory Allocation:")
    @time result = f(args...)
    
    # 3. Detailed profiling
    println("\n3. Profiling Results:")
    Profile.clear()
    @profile f(args...)
    Profile.print(maxdepth=10)
    
    # 4. Garbage collection analysis
    println("\n4. GC Analysis:")
    gc_before = Base.gc_num()
    f(args...)
    gc_after = Base.gc_num()
    
    println("GC time: $(gc_after.total_time - gc_before.total_time) ns")
    println("Allocations: $(gc_after.allocd - gc_before.allocd) bytes")
    
    return result
end

# Use for strategy analysis
result = comprehensive_performance_analysis(backtest, strategy, start_date, end_date)
```

### Performance Monitoring Dashboard

```julia
# Real-time performance monitoring
mutable struct PerformanceMonitor
    execution_times::Vector{Float64}
    memory_usage::Vector{Float64}
    timestamps::Vector{DateTime}
    
    PerformanceMonitor() = new(Float64[], Float64[], DateTime[])
end

function monitor_execution(monitor::PerformanceMonitor, f, args...)
    start_time = time()
    start_memory = Base.Sys.maxrss()
    
    result = f(args...)
    
    end_time = time()
    end_memory = Base.Sys.maxrss()
    
    # Record metrics
    push!(monitor.execution_times, end_time - start_time)
    push!(monitor.memory_usage, (end_memory - start_memory) / 1024^2)  # MB
    push!(monitor.timestamps, now())
    
    # Alert on performance degradation
    if length(monitor.execution_times) > 10
        recent_avg = mean(monitor.execution_times[end-9:end])
        historical_avg = mean(monitor.execution_times[1:end-10])
        
        if recent_avg > historical_avg * 1.5
            @warn "Performance degradation detected" recent=recent_avg historical=historical_avg
        end
    end
    
    return result
end

# Use with strategy execution
monitor = PerformanceMonitor()
result = monitor_execution(monitor, backtest, strategy, start_date, end_date)
```

## When to Seek Help

Contact the community if:
- Performance issues persist after applying optimization techniques
- System-level bottlenecks cannot be resolved
- Memory usage grows unbounded despite optimization efforts
- Profiling results are unclear or contradictory

## Getting Help

- [Community Resources](../resources/community.md)
- [GitHub Issues](https://github.com/defnlnotme/Planar.jl/issues)
- [Optimization Guide](../optimization.md)
- [Strategy Development](../guides/strategy-development.md)

## See Also

- [Optimization](../optimization.md) - Parameter optimization techniques
- [Strategy Development](../guides/strategy-development.md) - Efficient strategy patterns
- [Data Management](../guides/data-management.md) - Data handling best practices
- [Exchange Issues](exchange-issues.md) - Network and API performance