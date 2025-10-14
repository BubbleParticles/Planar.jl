# Troubleshooting Overview

This page provides quick access to troubleshooting resources. For detailed solutions, visit the specific troubleshooting guides in the [troubleshooting section](troubleshooting/index.md).

## Quick Access to Solutions

### Most Common Issues

1. **Installation Problems** → [Installation Issues](troubleshooting/installation-issues.md)
2. **Strategy Not Working** → [Strategy Problems](troubleshooting/strategy-problems.md)  
3. **Slow Performance** → [Performance Issues](troubleshooting/performance-issues.md)
4. **Exchange Errors** → [Exchange Issues](troubleshooting/exchange-issues.md)

### Emergency Quick Fixes

**Complete Reset (Nuclear Option):**

**Dependency Issues:**

**Python Problems:**

## Comprehensive Troubleshooting Guides

For detailed solutions with step-by-step instructions, platform-specific guidance, and advanced diagnostics, see:

- **[Troubleshooting Index](troubleshooting/index.md)** - Complete troubleshooting guide with all categories
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

**Symptoms**: `_debug_` not found errors during [strategy](guides/../guides/strategy-development.md) execution

**Diagnostic Steps**:
1. Check if `JULIA_DEBUG="all"` is set
2. Verify module precompilation status
3. Look for debug/release mode mismatches

**Solutions**:

## Python Integration Issues

### Missing Python Dependencies

**Symptoms**: `ModuleNotFoundError`, missing Python packages, import failures

**Diagnostic Steps**:
1. Check if CondaPkg environment is properly initialized
2. Verify Python package installation status
3. Look for environment path issues

**Solutions**:

### CondaPkg Environment Issues

**Symptoms**: Persistent Python module resolution failures, environment conflicts

**Diagnostic Steps**:
1. Check CondaPkg status and [configuration](config.md)
2. Verify environment variables are set correctly
3. Look for conflicting Python installations

**Solutions**:

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

## Exchange Connection Issues

### Unresponsive Exchange Instance

**Symptoms**: Timeout errors, connection refused, API calls hanging

**Diagnostic Steps**:
1. Check exchange status and maintenance schedules
2. Verify API credentials and permissions
3. Test network connectivity to exchange endpoints

**Solutions**:

**Idle Connection Closure**: If an exchange instance remains idle for an extended period, the connection may close. It should time out according to the `ccxt` exchange timeout. Following a timeout error, the connection will re-establish, and API-dependent functions will resume normal operation.

### API Authentication Issues

**Symptoms**: Authentication errors, invalid API key messages, permission denied

**Diagnostic Steps**:
1. Verify API credentials in `[secrets.toml](config.md#secrets-management)`
2. Check API key permissions on exchange
3. Verify IP whitelist settings if applicable

**Solutions**:

### Rate Limiting Issues

**Symptoms**: Rate limit exceeded errors, temporary bans, slow API responses

**Diagnostic Steps**:
1. Check current rate limit settings
2. Monitor API call frequency
3. Verify exchange-specific limits

**Solutions**:

## Data Storage and Management Issues

### LMDB Size Limitations

**Symptoms**: "MDB_MAP_FULL" errors, data saving failures, database write errors

**Diagnostic Steps**:
1. Check current database size usage
2. Monitor available disk space
3. Verify LMDB [configuration](config.md)

**Solutions**:

**Prevention**:
- Monitor database growth regularly
- Set initial size based on expected data volume
- Implement automated size monitoring

### Data Corruption Issues

**Symptoms**: Segfaults when saving [OHLCV](guides/../guides/data-management.md#ohlcv-data), corrupted data reads, database errors

**Diagnostic Steps**:
1. Check for incomplete write operations
2. Verify data integrity
3. Look for concurrent access issues

**Solutions**:

### LMDB Platform Compatibility

**Symptoms**: "LMDB not available" errors, compilation failures

**Diagnostic Steps**:
1. Check if LMDB binary is available for your platform
2. Verify system dependencies
3. Look for compilation errors

**Solutions**:

### Data Fetching and Pipeline Issues

**Symptoms**: Missing data, fetch timeouts, inconsistent data quality

**Diagnostic Steps**:
1. Check data source availability
2. Verify network connectivity
3. Monitor data quality metrics

**Solutions**:

## Plotting and Visualization Issues

### Misaligned Plotting Tooltips

**Symptoms**: Tooltips appear in wrong positions, rendering artifacts, display issues

**Diagnostic Steps**:
1. Check which Makie backend is currently active
2. Verify graphics driver compatibility
3. Test with different backends

**Solutions**:

### Backend Installation and Configuration Issues

**Symptoms**: Backend not found, OpenGL errors, display server issues

**Diagnostic Steps**:
1. Check if required system libraries are installed
2. Verify display server [configuration](config.md) (Linux)
3. Test graphics driver compatibility

**Solutions**:

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

### Interactive Features Not Working

**Symptoms**: Zoom/pan not responding, tooltips not appearing, selection not working

**Diagnostic Steps**:
1. Verify backend supports interactivity
2. Check if running in appropriate environment
3. Test with simple interactive examples

**Solutions**:

## Strategy Development and Execution Issues

### Strategy Loading and Compilation Issues

**Symptoms**: Strategy not found, compilation errors, module loading failures

**Diagnostic Steps**:
1. Check strategy file location and naming
2. Verify Project.toml configuration
3. Look for syntax errors in strategy code

**Solutions**:

### Strategy Execution Errors

**Symptoms**: Runtime errors during strategy execution, unexpected behavior

**Diagnostic Steps**:
1. Check strategy logic and data dependencies
2. Verify [market data](guides/../guides/data-management.md) availability
3. Look for timing or synchronization issues

**Solutions**:

### Order Execution Issues

**Symptoms**: Orders not executing, incorrect order types, position management errors

**Diagnostic Steps**:
1. Check order parameters and validation
2. Verify exchange connectivity and permissions
3. Look for balance and margin issues

**Solutions**:

## Development and Debugging Issues

### VSCode Debugging Configuration

**Symptoms**: Breakpoints not triggering, debugging not working in strategy execution

**Diagnostic Steps**:
1. Check VSCode Julia extension configuration
2. Verify debugger settings for compiled modules
3. Test with simple debugging scenarios

**Solutions**:
```json
/ In VSCode user settings.json
{
    "julia.debuggerDefaultCompiled": [
        "ALL_MODULES_EXCEPT_MAIN",
        "-Base.CoreLogging"
    ]
}
```

**Additional Debugging Tips**:

### Performance Debugging

**Symptoms**: Slow strategy execution, high memory usage, CPU bottlenecks

**Diagnostic Steps**:
1. Profile strategy execution
2. Identify memory allocation hotspots
3. Check for inefficient data operations

**Solutions**:

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

**Symptoms**: Slow [backtesting](guides/execution-modes.md#simulation)-mode), high CPU usage, long execution times

**Diagnostic Steps**:
1. Profile strategy execution to identify bottlenecks
2. Check data access patterns and frequency
3. Monitor memory allocation and garbage collection

**Performance Profiling**:

**Common Performance Issues and Solutions**:


### Memory Usage Optimization

**Symptoms**: High memory usage, out-of-memory errors, slow garbage collection

**Diagnostic Steps**:
1. Monitor memory usage during execution
2. Identify memory leaks and excessive allocations
3. Check for large object retention

**Memory Profiling**:

**Memory Optimization Techniques**:


### Data-Related Performance Issues

**Symptoms**: Slow data loading, high I/O wait times, database performance issues

**Diagnostic Steps**:
1. Monitor I/O operations and disk usage
2. Check data access patterns and caching
3. Verify database configuration and indexing

**Data Performance Optimization**:


### Optimization and Backtesting Performance

**Symptoms**: Slow parameter optimization, long backtesting times, inefficient search

**Diagnostic Steps**:
1. Profile [optimization](optimization.md) algorithms
2. Check parameter space size and search efficiency
3. Monitor parallel execution utilization

**Optimization Performance**:


### Parallel Processing and Threading

**Symptoms**: Poor multi-threading performance, race conditions, synchronization issues

**Diagnostic Steps**:
1. Check thread utilization and load balancing
2. Identify thread-safety issues
3. Monitor synchronization overhead

**Threading Optimization**:


### Plotting and Visualization Performance

**Symptoms**: Slow plot rendering, high memory usage during plotting, unresponsive plots

**Diagnostic Steps**:
1. Check data size and plot complexity
2. Monitor GPU/graphics memory usage
3. Test different backends for performance

**Plotting Performance Optimization**:


### System Resource Monitoring

**Tools and Techniques for Performance Monitoring**:



## See Also

- **[Exchanges](exchanges.md)** - Exchange integration and configuration
- **[Config](config.md)** - Exchange integration and configuration
- **[Overview](troubleshooting/index.md)** - Troubleshooting: Troubleshooting and problem resolution
- **[Optimization](optimization.md)** - Performance optimization techniques
- **[Performance Issues](troubleshooting/performance-issues.md)** - Troubleshooting: Performance optimization techniques
- **[Data Management](guides/../guides/data-management.md)** - Guide: Data handling and management

## Getting Help

### Before Seeking Help

1. **Check this [troubleshooting](troubleshooting/index.md) guide** for your specific issue
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
