---
title: "Installation Issues"
description: "Solutions for common installation and setup problems"
category: "troubleshooting"
---

# Installation Issues

This guide helps resolve common problems during Planar installation and setup.

## Julia Installation Issues

### Julia Version Compatibility

**Problem**: Planar requires Julia 1.11 or later.

**Solution**:
```bash
# Check your Julia version
julia --version

# If version is too old, install Julia 1.11+
# Visit https://julialang.org/downloads/
```

### Package Installation Failures

**Problem**: `Pkg.instantiate()` fails with dependency errors.

**Solution**:
```julia
# Clear package cache and retry
using Pkg
Pkg.gc()
Pkg.resolve()
Pkg.instantiate()
```

## Environment Setup Issues

### Directory Permissions

**Problem**: Permission denied when creating user directory.

**Solution**:
```bash
# Ensure proper permissions
chmod 755 user/
mkdir -p user/logs user/keys
```

### Environment Variables

**Problem**: `JULIA_PROJECT` not set correctly.

**Solution**:
```bash
# Set project environment
export JULIA_PROJECT=Planar
# or for interactive features
export JULIA_PROJECT=PlanarInteractive
```

## Configuration Issues

### Missing Configuration Files

**Problem**: `user/planar.toml` not found.

**Solution**:
```bash
# Copy example configuration
cp examples/planar.toml user/planar.toml
# Edit with your settings
```

### API Key Configuration

**Problem**: Exchange API authentication fails.

**Solution**:
1. Create `user/secrets.toml`:
```toml
[exchanges.binance]
api_key = "your_api_key"
secret = "your_secret_key"
sandbox = true  # for testing
```

2. Verify API key permissions on exchange
3. Test connectivity in paper mode first

## Dependency Issues

### Python Integration Problems

**Problem**: PythonCall.jl fails to initialize.

**Solution**:
```julia
# Rebuild Python environment
using Pkg
Pkg.build("PythonCall")
```

### CCXT Installation Issues

**Problem**: Ccxt.jl fails to load.

**Solution**:
```julia
# Reinstall CCXT
using Pkg
Pkg.rm("Ccxt")
Pkg.add("Ccxt")
```

## Docker Issues

### Container Build Failures

**Problem**: Docker build fails with compilation errors.

**Solution**:
```bash
# Clean build with no cache
docker build --no-cache -t planar .

# Or use pre-built image
docker pull docker.io/psydyllic/planar-sysimage
```

### Volume Mount Issues

**Problem**: User directory not accessible in container.

**Solution**:
```bash
# Ensure proper volume mounting
docker run -v $(pwd)/user:/app/user planar
```

## Performance Issues

### Slow Compilation

**Problem**: First run takes very long to compile.

**Solution**:
- Use sysimage for faster startup
- Enable precompilation: `JULIA_PRECOMP=1`
- Consider using Docker image with pre-compiled sysimage

### Memory Issues

**Problem**: Out of memory during large backtests.

**Solution**:
- Reduce data range or timeframe
- Use progressive data loading
- Increase system memory or use swap

## Network Issues

### Proxy Configuration

**Problem**: Cannot connect through corporate proxy.

**Solution**:
```bash
# Set proxy environment variables
export HTTP_PROXY=http://proxy.company.com:8080
export HTTPS_PROXY=https://proxy.company.com:8080
```

### Firewall Issues

**Problem**: Exchange API calls blocked by firewall.

**Solution**:
- Whitelist exchange API endpoints
- Use VPN if necessary
- Test with `curl` to verify connectivity

## Getting Additional Help

If these solutions don't resolve your issue:

1. Check the [main troubleshooting guide](index.md)
2. Review [exchange-specific issues](exchange-issues.md)
3. Search [GitHub Issues](https://github.com/defnlnotme/Planar.jl/issues)
4. Create a new issue with detailed error information