---
title: "Troubleshooting Overview"
description: "Quick access to troubleshooting resources and common solutions"
category: "troubleshooting"
difficulty: "beginner"
prerequisites: []
related_topics: ["getting-started", "configuration", "strategy-development"]
last_updated: "2025-10-04"
estimated_time: "5 minutes"
---

# Troubleshooting Overview

This page provides quick access to troubleshooting resources. For detailed solutions, visit the specific troubleshooting guides in the [troubleshooting section](troubleshooting/).

## Quick Access to Solutions

### Most Common Issues

1. **Installation Problems** → [Installation Issues](troubleshooting/installation-issues.md)
2. **Strategy Not Working** → [Strategy Problems](troubleshooting/strategy-problems.md)  
3. **Slow Performance** → [Performance Issues](troubleshooting/performance-issues.md)
4. **Exchange Errors** → [Exchange Issues](troubleshooting/exchange-issues.md)

### Emergency Quick Fixes

**Complete Reset (Nuclear Option):**
```julia
# Clear all caches and restart fresh
rm(joinpath(first(DEPOT_PATH), "compiled"), recursive=true, force=true)
; find ./ -name .CondaPkg | xargs -I {} rm -r {}
julia --project=Planar -e "using Pkg; Pkg.instantiate()"
```

**Dependency Issues:**
```julia
include("resolve.jl")
recurse_projects(update=true)
```

**Python Problems:**
```julia
; find ./ -name .CondaPkg | xargs -I {} rm -r {}
using Python
import Pkg; Pkg.instantiate()
```

## Comprehensive Troubleshooting Guides

For detailed solutions with step-by-step instructions, platform-specific guidance, and advanced diagnostics, see:

- **[Troubleshooting Index](troubleshooting/)** - Complete troubleshooting guide with all categories
- **[Installation Issues](troubleshooting/installation-issues.md)** - Setup, dependencies, environment configuration
- **[Strategy Problems](troubleshooting/strategy-problems.md)** - Development, execution, debugging
- **[Performance Issues](troubleshooting/performance-issues.md)** - Optimization, memory, speed
- **[Exchange Issues](troubleshooting/exchange-issues.md)** - Connectivity, authentication, trading

## Legacy Content Notice

This page previously contained comprehensive troubleshooting information. That content has been reorganized into categorized guides for better navigation and maintenance. If you're looking for specific troubleshooting information, please check the appropriate category above.

## Quick Diagnostic Checklist

Before diving into specific issues, try these common solutions:

1. **Environment Check**: Ensure you're using the correct [Julia](https://julialang.org/) project
   ```bash
   julia --project=Planar  # or PlanarInteractive
   ```

2. **Dependency Resolution**: Update and resolve all dependencies
   ```julia
   include("resolve.jl")
   recurse_projects()  # Add update=true if needed
   ```

3. **Clean Restart**: Exit [Julia](https://julialang.org/) completely and restart with a fresh REPL

4. **Check Environment Variables**: Verify `JULIA_PROJECT`, `JULIA_NUM_THREADS`, and other relevant settings

## Precompilation Issues

### Dependency Conflicts

**Symptoms**: Precompilation fails after repository updates, package version conflicts

**Diagnostic Steps**:
1. Check for dependency conflicts in the output
2. Look for version incompatibilities in error messages
3. Verify all submodules are properly updated

**Solutions**:
```julia
# Step 1: Resolve all dependencies
include("resolve.jl")
recurse_projects() # Optionally set update=true

# Step 2: If conflicts persist, try manual resolution
using Pkg
Pkg.resolve()
Pkg.instantiate()

# Step 3: For persistent issues, clear package cache
rm(joinpath(first(DEPOT_PATH), "compiled"), recursive=true, force=true)
```

### REPL Startup Issues

**Symptoms**: Precompilation errors when activating project in existing REPL

**Diagnostic Steps**:
1. Check if [Julia](https://julialang.org/) was started with correct project
2. Verify environment variables are set correctly
3. Look for conflicting package environments

**Solutions**:
```bash
# Preferred: Start Julia with project directly
julia --project=./Planar

# Alternative: For interactive features
julia --project=./PlanarInteractive

# Check current project status
julia> using Pkg; Pkg.status()
```

### Python-Dependent Precompilation

**Symptoms**: Segmentation faults during precompilation, Python-related errors

**Diagnostic Steps**:
1. Check if error occurs during Python module loading
2. Look for `@py` macro usage in precompilable code
3. Verify global cache states

**Solutions**:
```julia
# Step 1: Clear global caches before precompilation
TICKERS_CACHE100 = Dict()  # Clear any global caches

# Step 2: Avoid Python objects in precompilable functions
# Bad: Using @py in precompilable code
# Good: Lazy initialization of Python objects

# Step 3: Force Python environment reset if needed
using Python.PythonCall.C.CondaPkg
CondaPkg.resolve(force=true)
```

**Prevention**:
- Keep global constants empty during precompilation
- Use lazy initialization for Python-dependent objects
- Avoid `@py` macros in precompilable functions

### Persistent Precompilation Skipping

**Symptoms**: Packages consistently skip precompilation, slow startup times

**Diagnostic Steps**:
1. Check `JULIA_NOPRECOMP` environment variable
2. Verify package dependencies are precompiled
3. Look for circular dependency issues

**Solutions**:
```bash
# Check environment variables
echo $JULIA_NOPRECOMP
echo $JULIA_PRECOMP

# Clear environment variables if needed
unset JULIA_NOPRECOMP

# Force precompilation
julia --project=Planar -e "using Pkg; Pkg.precompile()"
```

### Debug Symbol Issues

**Symptoms**: `_debug_` not found errors during [strategy](../guides/strategy-development.md) execution

**Diagnostic Steps**:
1. Check if `JULIA_DEBUG="all"` is set
2. Verify module precompilation status
3. Look for debug/release mode mismatches

**Solutions**:
```julia
# Option 1: Precompile with debug enabled
ENV["JULIA_DEBUG"] = "all"
using Pkg; Pkg.precompile()

# Option 2: Disable debug for problematic modules
ENV["JULIA_DEBUG"] = ""  # Clear debug setting

# Option 3: Selective debug enabling
ENV["JULIA_DEBUG"] = "MyStrategy"  # Debug specific modules only
```

## Python Integration Issues

### Missing Python Dependencies

**Symptoms**: `ModuleNotFoundError`, missing Python packages, import failures

**Diagnostic Steps**:
1. Check if CondaPkg environment is properly initialized
2. Verify Python package installation status
3. Look for environment path issues

**Solutions**:
```julia
# Step 1: Clean and rebuild Python environment
; find ./ -name .CondaPkg | xargs -I {} rm -r {} # Removes existing Conda environments
using Python # Activates our Python wrapper with CondaPkg environment variable fixes
import Pkg; Pkg.instantiate()

# Step 2: Verify Python environment
using PythonCall
pyimport("sys").path  # Check Python path

# Step 3: Manual package installation if needed
using CondaPkg
CondaPkg.add("package_name")  # Add specific packages
```

### CondaPkg Environment Issues

**Symptoms**: Persistent Python module resolution failures, environment conflicts

**Diagnostic Steps**:
1. Check CondaPkg status and [configuration](../config.md)
2. Verify environment variables are set correctly
3. Look for conflicting Python installations

**Solutions**:
```julia
# Step 1: Force environment resolution
using Python.PythonCall.C.CondaPkg
CondaPkg.resolve(force=true)

# Step 2: Check CondaPkg status
CondaPkg.status()

# Step 3: Reset environment if needed
CondaPkg.reset()
CondaPkg.resolve()
```

**Platform-Specific Notes**:
- **Linux**: Ensure system Python development headers are installed
- **macOS**: May require Xcode command line tools
- **Windows**: Verify PATH environment variable includes Python

### Python-Julia Interop Issues

**Symptoms**: Type conversion errors, async operation failures, memory issues

**Diagnostic Steps**:
1. Check for type conversion problems between Python and Julia
2. Verify async operation compatibility
3. Look for memory management issues

**Solutions**:
```julia
# Type conversion debugging
using PythonCall
py_obj = pyimport("some_module").some_function()
@show typeof(py_obj)
julia_obj = pyconvert(DesiredType, py_obj)

# Async operation handling
# Use pyimport_conda for better async support
ccxt = pyimport_conda("ccxt", "ccxt")

# Memory management
GC.gc()  # Force garbage collection if needed
```

## Exchange Connection Issues

### Unresponsive Exchange Instance

**Symptoms**: Timeout errors, connection refused, API calls hanging

**Diagnostic Steps**:
1. Check [exchange](../[exchanges](../exchanges.md).md) status and maintenance schedules
2. Verify API credentials and permissions
3. Test network connectivity to [exchange](../[exchanges](../exchanges.md).md) endpoints

**Solutions**:
```julia
# Step 1: Test basic connectivity
using Exchanges
[exchange](../[exchanges](../exchanges.md).md) = getexchange(:binance)  # or your exchange
try
    exchange.fetch_ticker("BTC/USDT")
    @info "Exchange connection working"
catch e
    @error "Connection failed" exception=e
end

# Step 2: Reset exchange instance
exchange = getexchange(:binance, reset=true)

# Step 3: Check and adjust timeout settings
exchange.timeout = 30000  # 30 seconds
exchange.rateLimit = 1200  # Adjust rate limiting
```

**Idle Connection Closure**: If an exchange instance remains idle for an extended period, the connection may close. It should time out according to the `ccxt` exchange timeout. Following a timeout error, the connection will re-establish, and API-dependent functions will resume normal operation.

### API Authentication Issues

**Symptoms**: Authentication errors, invalid API key messages, permission denied

**Diagnostic Steps**:
1. Verify API credentials in `[secrets.toml](../config.md#secrets-management)`
2. Check API key permissions on exchange
3. Verify IP whitelist settings if applicable

**Solutions**:
```julia
# Step 1: Verify credentials format
# Check user/[secrets.toml](../config.md#secrets-management) for correct format:
# [exchanges.binance]
# apiKey = "your_api_key"
# secret = "your_secret"
# sandbox = false  # Set to true for testnet

# Step 2: Test authentication
exchange = getexchange(:binance)
try
    balance = exchange.fetch_balance()
    @info "Authentication successful"
catch e
    @error "Authentication failed" exception=e
end

# Step 3: Check API permissions
# Ensure your API key has required permissions:
# - Spot trading (for spot [strategies](../guides/strategy-development.md))
# - Futures trading (for margin [strategies](../guides/strategy-development.md))
# - Read permissions for data fetching
```

### Rate Limiting Issues

**Symptoms**: Rate limit exceeded errors, temporary bans, slow API responses

**Diagnostic Steps**:
1. Check current rate limit settings
2. Monitor API call frequency
3. Verify exchange-specific limits

**Solutions**:
```julia
# Step 1: Adjust rate limiting
exchange = getexchange(:binance)
exchange.rateLimit = 2000  # Increase delay between requests

# Step 2: Implement request batching
# Use batch operations where available
tickers = exchange.fetch_tickers(["BTC/USDT", "ETH/USDT"])

# Step 3: Monitor and log API usage
using Logging
@info "API call" symbol="BTC/USDT" timestamp=now()
```

## Data Storage and Management Issues

### LMDB Size Limitations

**Symptoms**: "MDB_MAP_FULL" errors, data saving failures, database write errors

**Diagnostic Steps**:
1. Check current database size usage
2. Monitor available disk space
3. Verify LMDB [configuration](../config.md)

**Solutions**:
```julia
using Data
zi = zinstance()

# Step 1: Check current usage
current_size = Data.mapsize(zi)
@info "Current LMDB size: $(current_size)MB"

# Step 2: Increase database size
Data.mapsize!(zi, 1024) # Sets the DB size to 1GB
Data.mapsize!!(zi, 100) # Adds 100MB to the current mapsize (resulting in 1.1GB total)

# Step 3: Monitor usage and set appropriate size
# Increase the mapsize before reaching the limit to continue saving data
Data.mapsize!(zi, 4096) # 4GB for large datasets
```

**Prevention**:
- Monitor database growth regularly
- Set initial size based on expected data volume
- Implement automated size monitoring

### Data Corruption Issues

**Symptoms**: Segfaults when saving [OHLCV](../guides/data-management.md#ohlcv-data), corrupted data reads, database errors

**Diagnostic Steps**:
1. Check for incomplete write operations
2. Verify data integrity
3. Look for concurrent access issues

**Solutions**:
```julia
# Step 1: Recreate corrupted database
using Data
Data.zinstance(force=true)  # Forces recreation of database

# Step 2: Backup and restore if needed
# Manual deletion (default path is under Data.DATA_PATH)
data_path = Data.DATA_PATH
@info "Data path: $data_path"
# Manually delete corrupted files if needed

# Step 3: Verify data integrity after recreation
zi = zinstance()
try
    # Test basic operations
    Data.save_ohlcv!(zi, :binance, "BTC/USDT", sample_data)
    @info "Database recreation successful"
catch e
    @error "Database still corrupted" exception=e
end
```

### LMDB Platform Compatibility

**Symptoms**: "LMDB not available" errors, compilation failures

**Diagnostic Steps**:
1. Check if LMDB binary is available for your platform
2. Verify system dependencies
3. Look for compilation errors

**Solutions**:
```julia
# Option 1: Disable LMDB if not available
# Add to your [strategy](../guides/strategy-development.md) Project.toml:
[preferences.Data]
data_store = "" # Disables lmdb (set it back to "lmdb" to enable lmdb)

# Option 2: Use alternative storage
# Configure alternative data storage in [strategy](../guides/strategy-development.md)
using Data
# Use in-memory or file-based storage instead

# Option 3: Manual LMDB installation (Linux/macOS)
# Install system LMDB library
# Ubuntu/Debian: sudo apt-get install liblmdb-dev
# macOS: brew install lmdb
```

### Data Fetching and Pipeline Issues

**Symptoms**: Missing data, fetch timeouts, inconsistent data quality

**Diagnostic Steps**:
1. Check data source availability
2. Verify network connectivity
3. Monitor data quality metrics

**Solutions**:
```julia
using Fetch, Data

# Step 1: Test data fetching
try
    data = fetch_ohlcv(:binance, "BTC/USDT", "1h", limit=100)
    @info "Data fetch successful" size=size(data)
catch e
    @error "Data fetch failed" exception=e
end

# Step 2: Implement retry logic
function robust_fetch(exchange, symbol, [timeframe](../guides/data-management.md#timeframes); retries=3)
    for i in 1:retries
        try
            return fetch_ohlcv(exchange, symbol, [timeframe](../guides/data-management.md#timeframes))
        catch e
            @warn "Fetch attempt $i failed" exception=e
            sleep(2^i)  # Exponential backoff
        end
    end
    error("All fetch attempts failed")
end

# Step 3: Validate data quality
function validate_ohlcv(data)
    # Check for missing values
    any(ismissing, data) && @warn "Missing values detected"
    
    # Check for reasonable price ranges
    prices = data.close
    if any(p -> p <= 0, prices)
        @warn "Invalid price data detected"
    end
    
    return data
end
```

## Plotting and Visualization Issues

### Misaligned Plotting Tooltips

**Symptoms**: Tooltips appear in wrong positions, rendering artifacts, display issues

**Diagnostic Steps**:
1. Check which Makie backend is currently active
2. Verify graphics driver compatibility
3. Test with different backends

**Solutions**:
```julia
# Step 1: Switch to GLMakie for better rendering
using GLMakie
GLMakie.activate!()

# Step 2: If GLMakie has issues, try CairoMakie
using CairoMakie
CairoMakie.activate!()

# Step 3: Check current backend
using Makie
@info "Current backend: $(Makie.current_backend())"

# Step 4: Reset backend if needed
Makie.inline!(false)  # Disable inline plotting
Makie.inline!(true)   # Re-enable if needed
```

### Backend Installation and Configuration Issues

**Symptoms**: Backend not found, OpenGL errors, display server issues

**Diagnostic Steps**:
1. Check if required system libraries are installed
2. Verify display server [configuration](../config.md) (Linux)
3. Test graphics driver compatibility

**Solutions**:
```julia
# Step 1: Install and test backends
using Pkg

# For GLMakie (requires OpenGL)
Pkg.add("GLMakie")
using GLMakie
GLMakie.activate!()

# For WGLMakie (web-based)
Pkg.add("WGLMakie")
using WGLMakie
WGLMakie.activate!()

# For CairoMakie (software rendering)
Pkg.add("CairoMakie")
using CairoMakie
CairoMakie.activate!()

# Step 2: Test basic plotting
using Plotting
fig = plot_ohlcv(:binance, "BTC/USDT", "1h")
display(fig)
```

**Platform-Specific Solutions**:

**Linux**:
```bash
# Install required libraries
sudo apt-get install libgl1-mesa-glx libxrandr2 libxss1 libxcursor1 libxcomposite1 libasound2 libxi6 libxtst6

# For headless servers, use Xvfb
export DISPLAY=:99
Xvfb :99 -screen 0 1024x768x24 &
```

**macOS**:
```bash
# Install XQuartz if needed
brew install --cask xquartz
```

**Windows**:
- Ensure graphics drivers are up to date
- Try running Julia as administrator if permission issues occur

### Plot Performance Issues

**Symptoms**: Slow rendering, memory issues with large datasets, unresponsive plots

**Diagnostic Steps**:
1. Check data size and complexity
2. Monitor memory usage during plotting
3. Verify backend performance characteristics

**Solutions**:
```julia
# Step 1: Optimize data for plotting
function optimize_for_plotting(data, max_points=10000)
    if nrow(data) > max_points
        # Downsample data for plotting
        step = div(nrow(data), max_points)
        return data[1:step:end, :]
    end
    return data
end

# Step 2: Use appropriate backend for data size
# GLMakie: Best for interactive plots with moderate data
# CairoMakie: Best for high-quality static plots
# WGLMakie: Best for web deployment

# Step 3: Implement progressive loading
function plot_large_dataset(data; chunk_size=1000)
    fig = Figure()
    ax = Axis(fig[1, 1])
    
    for i in 1:chunk_size:nrow(data)
        chunk_end = min(i + chunk_size - 1, nrow(data))
        chunk = data[i:chunk_end, :]
        lines!(ax, chunk.timestamp, chunk.close)
    end
    
    return fig
end
```

### Interactive Features Not Working

**Symptoms**: Zoom/pan not responding, tooltips not appearing, selection not working

**Diagnostic Steps**:
1. Verify backend supports interactivity
2. Check if running in appropriate environment
3. Test with simple interactive examples

**Solutions**:
```julia
# Step 1: Ensure using interactive backend
using GLMakie  # or WGLMakie
GLMakie.activate!()

# Step 2: Enable interactivity explicitly
using Plotting
fig = plot_ohlcv(:binance, "BTC/USDT", "1h", interactive=true)

# Step 3: Test basic interactivity
using Makie
fig, ax, plt = scatter(1:10, rand(10))
display(fig)  # Should allow zoom/pan

# Step 4: For Jupyter/web environments
using WGLMakie
WGLMakie.activate!()
```

## Strategy Development and Execution Issues

### Strategy Loading and Compilation Issues

**Symptoms**: Strategy not found, compilation errors, module loading failures

**Diagnostic Steps**:
1. Check strategy file location and naming
2. Verify Project.toml configuration
3. Look for syntax errors in strategy code

**Solutions**:
```julia
# Step 1: Verify strategy configuration in user/[planar.toml](../config.md#configuration-file)
[strategies.MyStrategy]
path = "[strategies](../guides/strategy-development.md)/MyStrategy"  # Correct path
# or
package = "MyStrategy"  # If using package format

# Step 2: Test strategy loading
using Strategies
try
    strategy = load_strategy(:MyStrategy)
    @info "Strategy loaded successfully"
catch e
    @error "Strategy loading failed" exception=e
end

# Step 3: Check for common syntax issues
# - Missing module declaration
# - Incorrect function signatures
# - Missing dependencies in Project.toml
```

### Strategy Execution Errors

**Symptoms**: Runtime errors during strategy execution, unexpected behavior

**Diagnostic Steps**:
1. Check strategy logic and data dependencies
2. Verify [market data](../guides/data-management.md) availability
3. Look for timing or synchronization issues

**Solutions**:
```julia
# Step 1: Enable detailed logging
ENV["JULIA_DEBUG"] = "MyStrategy"
using Logging
global_logger(ConsoleLogger(stderr, Logging.Debug))

# Step 2: Test strategy components individually
strategy = load_strategy(:MyStrategy)
# Test data access
data = strategy.data_source()
# Test signal generation
signals = generate_signals(strategy, data)

# Step 3: Use [simulation](../guides/execution-modes.md#simulation-mode) mode for debugging
using SimMode
sim = SimMode.Simulator(strategy)
SimMode.run!(sim, start_date, end_date)
```

### Order Execution Issues

**Symptoms**: Orders not executing, incorrect order types, position management errors

**Diagnostic Steps**:
1. Check order parameters and validation
2. Verify exchange connectivity and permissions
3. Look for balance and margin issues

**Solutions**:
```julia
# Step 1: Validate order parameters
using OrderTypes
order = MarketOrder(:buy, "BTC/USDT", 0.001)
validate_order(order, exchange)

# Step 2: Check account balance and permissions
balance = exchange.fetch_balance()
@info "Available balance" balance

# Step 3: Test order execution in paper mode first
using PaperMode
paper_exchange = PaperMode.PaperExchange(:binance)
result = place_order(paper_exchange, order)
```

## Development and Debugging Issues

### VSCode Debugging Configuration

**Symptoms**: Breakpoints not triggering, debugging not working in strategy execution

**Diagnostic Steps**:
1. Check VSCode Julia extension configuration
2. Verify debugger settings for compiled modules
3. Test with simple debugging scenarios

**Solutions**:
```json
// In VSCode user settings.json
{
    "julia.debuggerDefaultCompiled": [
        "ALL_MODULES_EXCEPT_MAIN",
        "-Base.CoreLogging"
    ]
}
```

**Additional Debugging Tips**:
```julia
# Step 1: Use @infiltrate for interactive debugging
using Infiltrator
function my_strategy_function(data)
    # ... strategy logic ...
    @infiltrate  # Drops into interactive debugging
    # ... more logic ...
end

# Step 2: Add strategic logging points
@debug "Strategy state" current_position=pos balance=bal

# Step 3: Use try-catch for error isolation
try
    result = risky_operation()
catch e
    @error "Operation failed" exception=(e, catch_backtrace())
    rethrow()
end
```

### Performance Debugging

**Symptoms**: Slow strategy execution, high memory usage, CPU bottlenecks

**Diagnostic Steps**:
1. Profile strategy execution
2. Identify memory allocation hotspots
3. Check for inefficient data operations

**Solutions**:
```julia
# Step 1: Profile strategy execution
using Profile
@profile run_strategy(strategy, data)
Profile.print()

# Step 2: Check memory allocations
using BenchmarkTools
@benchmark run_strategy($strategy, $data)

# Step 3: Optimize data operations
# Use views instead of copies
data_view = @view data[1:1000, :]
# Pre-allocate arrays
results = Vector{Float64}(undef, length(data))
```

## Environment and Configuration Issues

### Docker and Container Issues

**Symptoms**: Container startup failures, permission errors, volume mounting issues

**Diagnostic Steps**:
1. Check Docker installation and permissions
2. Verify volume mounts and file permissions
3. Test container networking

**Solutions**:
```bash
# Step 1: Test basic Docker functionality
docker run --rm hello-world

# Step 2: Check Planar container
docker run --rm -it psydyllic/planar-sysimage-interactive julia --version

# Step 3: Fix permission issues (Linux)
sudo usermod -aG docker $USER
# Logout and login again

# Step 4: Mount user directory correctly
docker run -v $(pwd)/user:/app/user psydyllic/planar-sysimage-interactive
```

### Environment Variable Issues

**Symptoms**: Configuration not loading, unexpected behavior, missing settings

**Diagnostic Steps**:
1. Check environment variable values
2. Verify .envrc configuration
3. Test variable precedence

**Solutions**:
```bash
# Step 1: Check current environment
env | grep JULIA
env | grep PLANAR

# Step 2: Verify direnv configuration
cat .envrc
direnv allow

# Step 3: Test variable loading in Julia
julia -e 'println(ENV["JULIA_PROJECT"])'
```

## Platform-Specific Issues

### Linux-Specific Issues

**Common Issues**:
- Missing system libraries for plotting backends
- Permission issues with Docker
- Display server configuration for headless systems

**Solutions**:
```bash
# Install required system packages
sudo apt-get update
sudo apt-get install build-essential libgl1-mesa-glx libxrandr2 libxss1

# For headless systems
export DISPLAY=:99
Xvfb :99 -screen 0 1024x768x24 > /dev/null 2>&1 &
```

### macOS-Specific Issues

**Common Issues**:
- Xcode command line tools missing
- Permission issues with system directories
- Graphics driver compatibility

**Solutions**:
```bash
# Install Xcode command line tools
xcode-select --install

# Install required packages via Homebrew
brew install lmdb
brew install --cask xquartz
```

### Windows-Specific Issues

**Common Issues**:
- Path length limitations
- PowerShell execution policy
- Graphics driver issues

**Solutions**:
```powershell
# Enable long paths
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Value 1

# Set execution policy
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Update graphics drivers through Device Manager
```

## Performance Troubleshooting

### Strategy Execution Performance

**Symptoms**: Slow [backtesting](../guides/execution-modes.md#[simulation](../guides/execution-modes.md#simulation-mode)-mode), high CPU usage, long execution times

**Diagnostic Steps**:
1. Profile strategy execution to identify bottlenecks
2. Check data access patterns and frequency
3. Monitor memory allocation and garbage collection

**Performance Profiling**:
```julia
using Profile, ProfileView

# Profile strategy execution
@profile begin
    strategy = load_strategy(:MyStrategy)
    result = [backtest](../guides/execution-modes.md#[simulation](../guides/execution-modes.md#simulation-mode)-mode)(strategy, start_date, end_date)
end

# View results
Profile.print()
ProfileView.view()  # Interactive flame graph

# Focus on specific functions
Profile.print(format=:flat, sortedby=:count)
```

**Common Performance Issues and Solutions**:

```julia
# Issue 1: Inefficient data access
# Bad: Accessing data repeatedly
for i in 1:length(timestamps)
    price = get_price(data, timestamps[i])  # Repeated lookups
end

# Good: Vectorized operations or pre-computed access
prices = [data[t].close for t in timestamps]
# or use views for large datasets
price_view = @view data.close[start_idx:end_idx]

# Issue 2: Excessive memory allocations
# Bad: Creating new arrays in loops
function calculate_signals(data)
    signals = []
    for row in eachrow(data)
        push!(signals, compute_signal(row))  # Allocates memory
    end
    return signals
end

# Good: Pre-allocate arrays
function calculate_signals(data)
    signals = Vector{Float64}(undef, nrow(data))
    for (i, row) in enumerate(eachrow(data))
        signals[i] = compute_signal(row)
    end
    return signals
end

# Issue 3: Type instability
# Bad: Mixed types
function process_data(data)
    result = nothing  # Type unstable
    if condition
        result = 1.0
    else
        result = "error"
    end
    return result
end

# Good: Consistent types
function process_data(data)
    if condition
        return 1.0
    else
        throw(ErrorException("Processing failed"))
    end
end
```

### Memory Usage Optimization

**Symptoms**: High memory usage, out-of-memory errors, slow garbage collection

**Diagnostic Steps**:
1. Monitor memory usage during execution
2. Identify memory leaks and excessive allocations
3. Check for large object retention

**Memory Profiling**:
```julia
using BenchmarkTools

# Benchmark memory allocations
@benchmark [backtest](../guides/execution-modes.md#simulation-mode)($strategy, $start_date, $end_date)

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
result = monitor_memory([backtest](../guides/execution-modes.md#simulation-mode), strategy, start_date, end_date)
```

**Memory Optimization Techniques**:

```julia
# Technique 1: Use views instead of copies
# Bad: Creates copies
subset_data = data[1000:2000, :]

# Good: Uses views
subset_data = @view data[1000:2000, :]

# Technique 2: Manage large datasets with chunking
function process_large_dataset(data; chunk_size=10000)
    results = []
    for i in 1:chunk_size:nrow(data)
        chunk_end = min(i + chunk_size - 1, nrow(data))
        chunk = @view data[i:chunk_end, :]
        
        chunk_result = process_chunk(chunk)
        push!(results, chunk_result)
        
        # Force garbage collection periodically
        if i % (chunk_size * 10) == 1
            GC.gc()
        end
    end
    return vcat(results...)
end

# Technique 3: Reuse pre-allocated arrays
mutable struct StrategyState
    signals::Vector{Float64}
    positions::Vector{Float64}
    temp_array::Vector{Float64}
end

function update_strategy!(state::StrategyState, data)
    # Reuse pre-allocated arrays instead of creating new ones
    fill!(state.temp_array, 0.0)
    # ... computation using state.temp_array ...
end
```

### Data-Related Performance Issues

**Symptoms**: Slow data loading, high I/O wait times, database [performance issues](../[troubleshooting](../troubleshooting/)/performance-issues.md)

**Diagnostic Steps**:
1. Monitor I/O operations and disk usage
2. Check data access patterns and caching
3. Verify database configuration and indexing

**Data Performance Optimization**:

```julia
using Data

# Issue 1: Inefficient data loading
# Bad: Loading all data at once
all_data = load_ohlcv(:binance, "BTC/USDT", "1h", DateTime(2020,1,1), DateTime(2024,1,1))

# Good: Progressive loading with caching
function load_data_progressively(exchange, symbol, [timeframe](../guides/data-management.md#timeframes), start_date, end_date; chunk_days=30)
    cache = Dict()
    current_date = start_date
    
    while current_date < end_date
        chunk_end = min(current_date + Day(chunk_days), end_date)
        
        # Check cache first
        cache_key = (current_date, chunk_end)
        if !haskey(cache, cache_key)
            cache[cache_key] = load_ohlcv(exchange, symbol, timeframe, current_date, chunk_end)
        end
        
        current_date = chunk_end
    end
    
    return vcat(values(cache)...)
end

# Issue 2: Database performance
zi = zinstance()

# Optimize LMDB settings for performance
Data.mapsize!(zi, 4096)  # Increase map size
# Use batch operations when possible
Data.batch_save_ohlcv!(zi, exchange, symbol_data_pairs)

# Issue 3: Zarr array [optimization](../optimization.md)
# Configure chunk sizes for your access patterns
zarr_array = zarr_create(Float64, (1000000, 5), chunks=(10000, 5))  # Optimize chunk size
```

### Optimization and Backtesting Performance

**Symptoms**: Slow [parameter optimization](../[optimization](../optimization.md).md), long [backtesting](../guides/execution-modes.md#simulation-mode) times, inefficient search

**Diagnostic Steps**:
1. Profile [optimization](../optimization.md) algorithms
2. Check parameter space size and search efficiency
3. Monitor parallel execution utilization

**Optimization Performance**:

```julia
using Optim

# Issue 1: Inefficient parameter space exploration
# Bad: Too fine-grained grid search
param_ranges = Dict(
    :param1 => 0.01:0.001:0.1,  # 100 values
    :param2 => 1:0.1:10,        # 91 values
    # Total: 9,100 combinations
)

# Good: Coarse initial search, then refinement
initial_ranges = Dict(
    :param1 => 0.01:0.01:0.1,   # 10 values
    :param2 => 1:1:10,          # 10 values
    # Total: 100 combinations
)

# Then refine around best results
function optimize_hierarchical(strategy, param_ranges)
    # Coarse search
    coarse_results = grid_search(strategy, initial_ranges)
    best_params = get_best_params(coarse_results)
    
    # Fine search around best
    fine_ranges = refine_ranges(best_params, factor=0.1)
    fine_results = grid_search(strategy, fine_ranges)
    
    return fine_results
end

# Issue 2: Inefficient [backtesting](../guides/execution-modes.md#simulation-mode)
# Bad: Recalculating indicators for each parameter set
function backtest_strategy(params)
    data = load_data()  # Loads same data repeatedly
    indicators = calculate_indicators(data)  # Recalculates same indicators
    return run_backtest(params, data, indicators)
end

# Good: Pre-compute shared calculations
function optimize_strategy_efficient(param_sets)
    # Pre-compute shared data and indicators
    data = load_data()
    base_indicators = calculate_base_indicators(data)
    
    results = []
    for params in param_sets
        # Only compute parameter-specific indicators
        param_indicators = calculate_param_indicators(base_indicators, params)
        result = run_backtest(params, data, param_indicators)
        push!(results, result)
    end
    
    return results
end
```

### Parallel Processing and Threading

**Symptoms**: Poor multi-threading performance, race conditions, synchronization issues

**Diagnostic Steps**:
1. Check thread utilization and load balancing
2. Identify thread-safety issues
3. Monitor synchronization overhead

**Threading Optimization**:

```julia
# Check current threading setup
@info "Julia threads: $(Threads.nthreads())"

# Issue 1: Thread-unsafe operations
# Bad: Shared mutable state
global_cache = Dict()
Threads.@threads for i in 1:1000
    global_cache[i] = compute_result(i)  # Race condition
end

# Good: Thread-local storage or atomic operations
function parallel_compute_safe(inputs)
    results = Vector{Any}(undef, length(inputs))
    
    Threads.@threads for i in eachindex(inputs)
        results[i] = compute_result(inputs[i])  # No shared state
    end
    
    return results
end

# Issue 2: Load balancing
# Bad: Uneven work distribution
Threads.@threads for i in 1:100
    if i <= 10
        expensive_computation(i)  # Only first few threads do work
    else
        cheap_computation(i)
    end
end

# Good: Balanced work distribution
function balanced_parallel_work(work_items)
    # Sort by estimated work complexity
    sorted_items = sort(work_items, by=estimate_complexity, rev=true)
    
    results = Vector{Any}(undef, length(sorted_items))
    Threads.@threads for i in eachindex(sorted_items)
        results[i] = process_item(sorted_items[i])
    end
    
    return results
end
```

### Plotting and Visualization Performance

**Symptoms**: Slow plot rendering, high memory usage during plotting, unresponsive plots

**Diagnostic Steps**:
1. Check data size and plot complexity
2. Monitor GPU/graphics memory usage
3. Test different backends for performance

**Plotting Performance Optimization**:

```julia
using Plotting

# Issue 1: Plotting too much data
# Bad: Plotting millions of points
large_data = load_ohlcv(:binance, "BTC/USDT", "1m", DateTime(2020,1,1), DateTime(2024,1,1))
plot_ohlcv(large_data)  # Slow and memory-intensive

# Good: Downsample for visualization
function downsample_for_plot(data, target_points=10000)
    if nrow(data) <= target_points
        return data
    end
    
    step = div(nrow(data), target_points)
    return data[1:step:end, :]
end

optimized_data = downsample_for_plot(large_data)
plot_ohlcv(optimized_data)

# Issue 2: Backend selection for performance
# For large datasets, use appropriate backend
using GLMakie  # Good for interactive plots with moderate data
using CairoMakie  # Good for high-quality static plots
using WGLMakie  # Good for web deployment

# Choose based on use case
function plot_with_optimal_backend(data, interactive=true)
    if interactive && nrow(data) < 100000
        GLMakie.activate!()
    elseif !interactive
        CairoMakie.activate!()
    else
        # For very large datasets, downsample first
        data = downsample_for_plot(data, 50000)
        GLMakie.activate!()
    end
    
    return plot_ohlcv(data)
end
```

### System Resource Monitoring

**Tools and Techniques for Performance Monitoring**:

```julia
# System resource monitoring
function monitor_system_resources(f, args...)
    # CPU and memory before
    cpu_before = @elapsed sleep(0.001)  # Baseline timing
    mem_before = Base.Sys.maxrss()
    
    # Execute function
    start_time = time()
    result = f(args...)
    execution_time = time() - start_time
    
    # CPU and memory after
    mem_after = Base.Sys.maxrss()
    
    @info "Performance metrics" execution_time_s=execution_time memory_used_mb=(mem_after - mem_before) / 1024^2
    
    return result
end

# Disk I/O monitoring
function monitor_io(f, args...)
    io_before = Base.Sys.total_memory()  # Approximate
    
    result = f(args...)
    
    io_after = Base.Sys.total_memory()
    
    @info "I/O impact" estimated_io_mb=(io_after - io_before) / 1024^2
    
    return result
end

# Combined monitoring
function comprehensive_monitor(f, args...)
    @info "Starting performance monitoring..."
    
    # Profile execution
    @profile result = monitor_system_resources(f, args...)
    
    # Print profile results
    Profile.print(maxdepth=10)
    
    return result
end
```


## See Also

- **[Exchanges](../exchanges.md)** - Exchange integration and configuration
- **[Config](../config.md)** - Exchange integration and configuration
- **[Overview](../troubleshooting/index.md)** - Troubleshooting: Troubleshooting and problem resolution
- **[Optimization](../optimization.md)** - Performance optimization techniques
- **[Performance Issues](../troubleshooting/performance-issues.md)** - Troubleshooting: Performance optimization techniques
- **[Data Management](../guides/data-management.md)** - Guide: Data handling and management

## Getting Help

### Before Seeking Help

1. **Check this [troubleshooting](../troubleshooting/) guide** for your specific issue
2. **Search existing GitHub issues** for similar problems
3. **Try the diagnostic steps** provided for your issue category
4. **Gather relevant information**:
   - Julia version (`julia --version`)
   - Planar version/commit
   - Operating system and version
   - Complete error messages and stack traces
   - Minimal reproducible example

### Where to Get Help

1. **GitHub Issues**: For bugs and feature requests
2. **Discussions**: For general questions and community support
3. **Documentation**: Check the comprehensive guides and API reference

### Creating Effective Bug Reports

Include the following information:
- **Environment details**: OS, Julia version, Planar version
- **Steps to reproduce**: Minimal example that demonstrates the issue
- **Expected behavior**: What you expected to happen
- **Actual behavior**: What actually happened
- **Error messages**: Complete error output and stack traces
- **Configuration**: Relevant parts of your configuration files
