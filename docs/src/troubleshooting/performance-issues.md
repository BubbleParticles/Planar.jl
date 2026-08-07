# Performance Issues

This guide helps optimize Planar performance and resolve speed-related problems.

## Compilation and Startup Issues

### Slow First Run

**Problem**: Initial startup takes several minutes.

**Solution**:
```bash
# Use precompiled sysimage
julia --sysimage=planar.so --project=Planar

# Or use Docker with pre-built sysimage
docker run docker.io/bubbleparticles/planar-sysimage
```

### Repeated Compilation

**Problem**: Code recompiles on every run.


## Memory Issues

### High Memory Usage

**Problem**: Planar consumes excessive memory.


### Memory Leaks

**Problem**: Memory usage grows over time.


### Out of Memory Errors

**Problem**: System runs out of memory during large operations.


## Backtesting Performance

### Slow Backtests

**Problem**: Backtests take too long to complete.


### CPU Bottlenecks

**Problem**: High CPU usage during backtests.


## Data Performance

### Slow Data Loading

**Problem**: Historical data takes long to load.


### Database Performance

**Problem**: LMDB operations are slow.


## Network Performance

### Slow API Calls

**Problem**: Exchange API calls are slow.


### Rate Limiting Impact

**Problem**: Rate limits slow down operations.


## Strategy Performance

### Slow Strategy Execution

**Problem**: Strategy logic is slow during backtests.


### Indicator Calculation Bottlenecks

**Problem**: Technical indicators slow down strategy.


## Optimization Strategies

### Parameter Optimization Performance

**Problem**: Parameter optimization takes too long.


### Multi-Strategy Performance

**Problem**: Running multiple strategies is slow.


## System Optimization

### Operating System Tuning

```bash
# Increase file descriptor limits
ulimit -n 65536

# Optimize memory settings
echo 'vm.swappiness=10' >> /etc/sysctl.conf

# Use performance CPU governor
echo performance > /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
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
