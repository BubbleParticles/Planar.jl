---
title: "Performance Issues"
description: "Solutions for performance optimization and speed problems"
category: "troubleshooting"
---

# Performance Issues

This guide helps optimize Planar performance and resolve speed-related problems.

## Compilation and Startup Issues

### Slow First Run

**Problem**: Initial startup takes several minutes.

**Solution**:
```julia
# Use precompiled sysimage
julia --sysimage=planar.so --project=Planar

# Or use Docker with pre-built sysimage
docker run docker.io/psydyllic/planar-sysimage
```

### Repeated Compilation

**Problem**: Code recompiles on every run.

**Solution**:
```julia
# Enable precompilation
ENV["JULIA_PRECOMP"] = "1"

# Use Revise.jl for development
using Revise
using Planar
```

## Memory Issues

### High Memory Usage

**Problem**: Planar consumes excessive memory.

**Solution**:
```julia
# Reduce data cache size
config.data.max_cache_size = 1000  # MB

# Use progressive data loading
config.data.progressive_loading = true

# Limit concurrent operations
config.engine.max_concurrent_backtests = 2
```

### Memory Leaks

**Problem**: Memory usage grows over time.

**Solution**:
```julia
# Force garbage collection
GC.gc()

# Clear data caches periodically
clear_data_cache()

# Restart long-running processes periodically
```

### Out of Memory Errors

**Problem**: System runs out of memory during large operations.

**Solution**:
```julia
# Reduce backtest data range
config.backtest.start_date = "2023-01-01"
config.backtest.end_date = "2023-06-01"

# Use smaller timeframes
config.data.primary_timeframe = "1h"  # instead of "1m"

# Enable data streaming
config.data.streaming_mode = true
```

## Backtesting Performance

### Slow Backtests

**Problem**: Backtests take too long to complete.

**Solution**:
```julia
# Use parallel processing
config.engine.parallel_backtests = true
config.engine.num_workers = 4

# Optimize data access
config.data.preload_data = true
config.data.use_zarr_cache = true

# Reduce indicator calculations
config.strategy.cache_indicators = true
```

### CPU Bottlenecks

**Problem**: High CPU usage during backtests.

**Solution**:
```julia
# Limit thread usage
ENV["JULIA_NUM_THREADS"] = "4"

# Use efficient algorithms
config.engine.fast_mode = true
config.engine.skip_detailed_logs = true

# Optimize strategy logic
# - Avoid unnecessary calculations in hot loops
# - Cache expensive computations
# - Use vectorized operations
```

## Data Performance

### Slow Data Loading

**Problem**: Historical data takes long to load.

**Solution**:
```julia
# Use Zarr format for large datasets
config.data.storage_format = "zarr"

# Enable data compression
config.data.compression = "lz4"

# Parallel data fetching
config.data.parallel_fetch = true
config.data.fetch_workers = 4
```

### Database Performance

**Problem**: LMDB operations are slow.

**Solution**:
```julia
# Increase LMDB map size
config.data.lmdb_map_size = 10_000_000_000  # 10GB

# Use SSD storage for data directory
# Move data directory to faster storage

# Optimize batch operations
config.data.batch_size = 10000
```

## Network Performance

### Slow API Calls

**Problem**: Exchange API calls are slow.

**Solution**:
```julia
# Use connection pooling
config.exchange.connection_pool_size = 10

# Enable HTTP/2 if supported
config.exchange.http_version = "2.0"

# Optimize request batching
config.exchange.batch_requests = true
```

### Rate Limiting Impact

**Problem**: Rate limits slow down operations.

**Solution**:
```julia
# Optimize request patterns
config.exchange.intelligent_rate_limiting = true

# Use WebSocket for real-time data
config.data.use_websocket = true

# Cache frequently accessed data
config.data.cache_market_data = true
```

## Strategy Performance

### Slow Strategy Execution

**Problem**: Strategy logic is slow during backtests.

**Solution**:
```julia
# Profile strategy performance
using Profile
@profile run_backtest(strategy, config)
Profile.print()

# Optimize hot paths
# - Use @inbounds for array access
# - Avoid allocations in loops
# - Pre-allocate arrays
```

### Indicator Calculation Bottlenecks

**Problem**: Technical indicators slow down strategy.

**Solution**:
```julia
# Cache indicator results
config.indicators.cache_results = true

# Use efficient indicator libraries
# - Prefer vectorized implementations
# - Avoid recalculating unchanged periods

# Limit indicator lookback
config.indicators.max_lookback = 200
```

## Optimization Strategies

### Parameter Optimization Performance

**Problem**: Parameter optimization takes too long.

**Solution**:
```julia
# Use parallel optimization
config.optimization.parallel = true
config.optimization.workers = 8

# Reduce search space
config.optimization.max_iterations = 100
config.optimization.early_stopping = true

# Use efficient algorithms
config.optimization.algorithm = "bayesian"  # instead of grid search
```

### Multi-Strategy Performance

**Problem**: Running multiple strategies is slow.

**Solution**:
```julia
# Use strategy isolation
config.engine.isolate_strategies = true

# Shared data access
config.data.shared_cache = true

# Load balancing
config.engine.strategy_load_balancing = true
```

## System Optimization

### Julia Configuration

```julia
# Optimize Julia startup
ENV["JULIA_NUM_THREADS"] = string(Sys.CPU_THREADS - 2)
ENV["JULIA_PRECOMP"] = "1"

# Use faster BLAS
using MKL  # if available
```

### Operating System Tuning

```bash
# Increase file descriptor limits
ulimit -n 65536

# Optimize memory settings
echo 'vm.swappiness=10' >> /etc/sysctl.conf

# Use performance CPU governor
echo performance > /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
```

## Monitoring Performance

### Built-in Profiling

```julia
# Enable performance monitoring
config.monitoring.performance_tracking = true

# Profile specific operations
@time run_backtest(strategy, config)
@benchmark calculate_indicators(data)
```

### External Monitoring

```julia
# System resource monitoring
using Sys
println("Memory usage: $(Sys.total_memory() - Sys.free_memory()) bytes")
println("CPU usage: $(Sys.cpu_info())")

# Custom performance metrics
config.monitoring.custom_metrics = true
```

## Hardware Recommendations

### Minimum Requirements
- CPU: 4+ cores, 2.5+ GHz
- RAM: 8GB+ (16GB+ recommended)
- Storage: SSD recommended for data directory
- Network: Stable internet connection

### Optimal Configuration
- CPU: 8+ cores, 3.0+ GHz (Intel/AMD)
- RAM: 32GB+ for large backtests
- Storage: NVMe SSD for data and temp files
- Network: Low-latency connection for live trading

## Getting Help

For performance issues:

1. Check [system requirements](../getting-started/installation.md)
2. Review [configuration guide](../config.md)
3. Profile your specific use case
4. Ask for help with performance data
5. Consider hardware upgrades

## Related Documentation

- [Configuration Guide](../config.md)
- [Installation Guide](../getting-started/installation.md)
- [Optimization Guide](../optimization.md)