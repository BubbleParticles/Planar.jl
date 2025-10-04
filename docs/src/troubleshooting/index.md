---
title: "Troubleshooting Guide"
description: "Comprehensive solutions to common Planar issues"
category: "troubleshooting"
difficulty: "beginner"
prerequisites: []
related_topics: ["getting-started", "configuration", "strategy-development"]
last_updated: "2025-10-04"
estimated_time: "5 minutes"
---

# Troubleshooting Guide

This guide provides comprehensive solutions to common issues encountered when using Planar. Issues are organized by category with step-by-step diagnostic procedures and platform-specific solutions.

## Quick Diagnostic Checklist

Before diving into specific issues, try these common solutions:

1. **Environment Check**: Ensure you're using the correct Julia project
   ```bash
   julia --project=Planar  # or PlanarInteractive
   ```

2. **Dependency Resolution**: Update and resolve all dependencies
   ```julia
   include("resolve.jl")
   recurse_projects()  # Add update=true if needed
   ```

3. **Clean Restart**: Exit Julia completely and restart with a fresh REPL

4. **Check Environment Variables**: Verify `JULIA_PROJECT`, `JULIA_NUM_THREADS`, and other relevant settings

## Problem Categories

### [Installation Issues](installation-issues.md)
Setup and dependency problems, environment configuration, platform-specific installation issues.

**Common symptoms:**
- Dependency conflicts during installation
- Python integration setup failures
- LMDB installation problems
- Docker container issues

**Quick fixes:**
- Run `include("resolve.jl"); recurse_projects()`
- Clear package cache: `rm(joinpath(first(DEPOT_PATH), "compiled"), recursive=true, force=true)`
- Reset Python environment: Remove `.CondaPkg` directories and reinstantiate

**Quick Diagnostic Checklist:**
- [ ] Julia 1.11+ installed (`julia --version`)
- [ ] Correct project activated (`julia --project=Planar`)
- [ ] Dependencies resolved (`] instantiate`)
- [ ] Environment variables set (`echo $JULIA_PROJECT`)

### [Strategy Problems](strategy-problems.md)
Strategy development and execution issues, debugging techniques.

**Common symptoms:**
- Strategy loading failures
- Runtime errors during execution
- Signal generation problems
- Order execution issues

**Quick fixes:**
- Enable debug logging: `ENV["JULIA_DEBUG"] = "MyStrategy"`
- Test in simulation mode first
- Validate data availability and quality
- Check strategy configuration in `user/planar.toml`

**Quick Diagnostic Checklist:**
- [ ] Strategy file exists in `user/strategies/`
- [ ] Module name matches file name
- [ ] Required constants defined (`EXC`, `MARGIN`, `TF`)
- [ ] `@strategyenv!` macro included
- [ ] Market data available for timeframe

### [Performance Issues](performance-issues.md)
Speed optimization, memory management, and system resource problems.

**Common symptoms:**
- Slow backtesting or strategy execution
- High memory usage or out-of-memory errors
- Database performance problems
- Inefficient parameter optimization

**Quick fixes:**
- Profile execution: `@profile your_function(); Profile.print()`
- Use views instead of copies: `@view data[1:1000, :]`
- Increase LMDB size: `Data.mapsize!(zi, 4096)`
- Implement chunked processing for large datasets

### [Exchange Issues](exchange-issues.md)
Exchange connectivity, API authentication, and trading operation problems.

**Common symptoms:**
- Connection timeouts or API failures
- Authentication errors
- Rate limiting issues
- Order execution failures

**Quick fixes:**
- Reset exchange connection: `getexchange(:binance, reset=true)`
- Check API credentials in `user/secrets.toml`
- Adjust rate limiting: `exchange.rateLimit = 2000`
- Verify account balance and permissions

**Quick Diagnostic Checklist:**
- [ ] Internet connectivity working
- [ ] Exchange API status normal
- [ ] API credentials configured correctly
- [ ] API key permissions sufficient
- [ ] Rate limits not exceeded

## Platform-Specific Quick Fixes

### Linux
```bash
# Install required system libraries
sudo apt-get install build-essential libgl1-mesa-glx libxrandr2 libxss1 liblmdb-dev

# Fix Docker permissions
sudo usermod -aG docker $USER
```

### macOS
```bash
# Install Xcode command line tools
xcode-select --install

# Install required packages
brew install lmdb
brew install --cask xquartz
```

### Windows
```powershell
# Enable long paths (requires admin)
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Value 1

# Set execution policy
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

## Emergency Troubleshooting

If Planar is completely broken:

1. **Nuclear Reset**: Clear all caches and restart
   ```julia
   # Clear package cache
   rm(joinpath(first(DEPOT_PATH), "compiled"), recursive=true, force=true)
   
   # Clear Python environments
   ; find ./ -name .CondaPkg | xargs -I {} rm -r {}
   
   # Restart Julia and reinstantiate
   julia --project=Planar -e "using Pkg; Pkg.instantiate()"
   ```

2. **Fresh Installation**: Start from scratch
   ```bash
   # Backup user data
   cp -r user user_backup
   
   # Fresh clone
   git clone --recurse-submodules https://github.com/defnlnotme/Planar.jl
   cd Planar.jl
   
   # Restore user data
   cp -r ../user_backup/* user/
   ```

## Error-Specific Quick Solutions

### Common Error Messages

**"ArgumentError: Module MyStrategy not found"**
→ [Strategy Problems: Loading Issues](strategy-problems.md#strategy-not-found)

**"MethodError: no method matching call!"**
→ [Strategy Problems: Interface Issues](strategy-problems.md#module-interface-issues)

**"MDB_MAP_FULL" (LMDB errors)**
→ [Performance Issues: Database](performance-issues.md#database-performance-issues)

**"Rate limit exceeded" / 429 errors**
→ [Exchange Issues: Rate Limiting](exchange-issues.md#rate-limiting-issues)

**"Invalid API key" / 401 errors**
→ [Exchange Issues: Authentication](exchange-issues.md#api-authentication-issues)

**"Connection refused" / timeout errors**
→ [Exchange Issues: Connectivity](exchange-issues.md#network-connectivity-problems)

**"Package not found" / precompilation errors**
→ [Installation Issues: Dependencies](installation-issues.md#dependency-conflicts)

**"Insufficient balance" errors**
→ [Strategy Problems: Order Execution](strategy-problems.md#order-execution-failures)

## Getting Help

If you can't find a solution in the troubleshooting guides:

### Community Resources
- [Community Resources](../resources/community.md) - Forums and chat channels
- [GitHub Issues](https://github.com/defnlnotme/Planar.jl/issues) - Bug reports and feature requests

### Documentation
- [Getting Started](../getting-started/) - Initial setup and basic usage
- [Configuration Guide](../config.md) - Environment and API configuration
- [Strategy Development](../guides/strategy-development.md) - Strategy creation and debugging
- [API Reference](../reference/) - Function documentation and examples

### When Reporting Issues
Include this information when seeking help:

```julia
# System information
using InteractiveUtils
versioninfo()

# Package status
using Pkg
Pkg.status()

# Environment variables
for (k, v) in ENV
    if startswith(k, "JULIA") || startswith(k, "PLANAR")
        println("$k = $v")
    end
end
```

## See Also

- **[Installation Issues](installation-issues.md)** - Setup and environment problems
- **[Strategy Problems](strategy-problems.md)** - Development and execution issues  
- **[Performance Issues](performance-issues.md)** - Optimization and resource management
- **[Exchange Issues](exchange-issues.md)** - Connectivity and trading problems
- **[Configuration Guide](../config.md)** - Settings and API setup
- **[Getting Started](../getting-started/)** - Initial setup guide