---
title: "Installation Guide"
description: "Complete installation guide for Planar trading bot"
category: "getting-started"
---

# Installation Guide

This guide walks you through installing and setting up Planar on your system.

## Prerequisites

### System Requirements

- **Operating System**: Linux, macOS, or Windows
- **Julia**: Version 1.11 or later
- **Memory**: 8GB RAM minimum (16GB+ recommended)
- **Storage**: 10GB+ free space for data and dependencies
- **Network**: Stable internet connection for exchange APIs

### Julia Installation

1. Download Julia 1.11+ from [julialang.org](https://julialang.org/downloads/)
2. Follow the platform-specific installation instructions
3. Verify installation:
```bash
julia --version
```

## Installation Methods

### Method 1: Git Clone (Recommended)

```bash
# Clone the repository with submodules
git clone --recurse-submodules https://github.com/defnlnotme/Planar.jl
cd Planar.jl

# Allow direnv (if using)
direnv allow

# Start Julia with the project
julia --project=Planar
```

### Method 2: Docker

```bash
# Pull pre-built image
docker pull docker.io/psydyllic/planar-sysimage

# Or build locally
scripts/build.sh
```

## Project Setup

### 1. Install Dependencies

```julia
# In Julia REPL with --project=Planar
using Pkg
Pkg.instantiate()
```

### 2. Create User Directory

```bash
# Create user configuration directory
mkdir -p user/logs user/keys
```

### 3. Configuration Files

Create `user/planar.toml`:
```toml
[general]
name = "My Trading Bot"
log_level = "INFO"

[exchanges]
default = "binance"

[exchanges.binance]
enabled = true
sandbox = true  # Start with testnet

[strategies]
# Add your strategies here
```

Create `user/secrets.toml`:
```toml
[exchanges.binance]
api_key = "your_api_key_here"
secret = "your_secret_key_here"
```

## API Configuration

### Exchange API Keys

1. **Binance**:
   - Go to [Binance API Management](https://www.binance.com/en/my/settings/api-management)
   - Create new API key
   - Enable "Enable Reading" and "Enable Spot & Margin Trading"
   - Add IP restrictions for security

2. **Coinbase Pro**:
   - Go to [Coinbase Pro API](https://pro.coinbase.com/profile/api)
   - Create new API key with trading permissions
   - Note the passphrase requirement

3. **Other Exchanges**:
   - Follow exchange-specific API documentation
   - Ensure proper permissions for trading

### API Security

- **Never commit API keys to version control**
- Use IP restrictions when possible
- Start with sandbox/testnet environments
- Use separate API keys for different bots
- Regularly rotate API keys

## Environment Configuration

### Environment Variables

```bash
# Set Julia project
export JULIA_PROJECT=Planar

# Set thread count (recommended: CPU cores - 2)
export JULIA_NUM_THREADS=6

# Enable precompilation
export JULIA_PRECOMP=1

# Set data directory (optional)
export PLANAR_DATA_DIR=/path/to/data
```

### Using direnv (Optional)

Create `.envrc`:
```bash
export JULIA_PROJECT=Planar
export JULIA_NUM_THREADS=6
export JULIA_PRECOMP=1
```

## Verification

### Test Installation

```julia
# Load Planar
using Planar

# Test basic functionality
@info "Planar loaded successfully"

# Test exchange connectivity (sandbox)
# Note: Replace with your actual exchange setup
try
    exchange = getexchange!(:binance, sandbox=true)
    @info "Exchange connection successful"
catch e
    @warn "Exchange connection failed (this is normal without API keys): $e"
end
```

### Run Example Strategy

```julia
# Load example strategy (using built-in example)
# Note: This requires PlanarInteractive for full functionality
try
    import Pkg
    Pkg.activate("PlanarInteractive")
    using PlanarInteractive
    
    # Create a simple test strategy
    s = strategy(:QuickStart, exchange=:binance)
    @info "Example strategy created successfully"
catch e
    @warn "Interactive features not available: $e"
    @info "Basic Planar installation verified"
end
```

## Docker Setup

### Using Pre-built Image

```bash
# Run with interactive features
docker run -it \
  -v $(pwd)/user:/app/user \
  docker.io/psydyllic/planar-sysimage-interactive

# Run production image
docker run -d \
  -v $(pwd)/user:/app/user \
  docker.io/psydyllic/planar-sysimage
```

### Building Custom Image

```bash
# Build development image
scripts/build.sh

# Build with custom Julia version
JULIA_VERSION=1.11.1 scripts/build.sh
```

## Performance Optimization

### Precompilation

```julia
# Create sysimage for faster startup
using PackageCompiler
create_sysimage(["Planar"], sysimage_path="planar.so")

# Use sysimage
julia --sysimage=planar.so --project=Planar
```

### Memory Settings

```bash
# Increase Julia heap size if needed
export JULIA_HEAP_SIZE_HINT=8G

# Optimize garbage collection
export JULIA_GC_THREADS=2
```

## Troubleshooting

### Common Issues

1. **Package Installation Fails**:
   ```julia
   # Clear package cache
   import Pkg
   Pkg.activate("Planar")  # Ensure correct project
   Pkg.gc()
   Pkg.resolve()
   ```

2. **Permission Errors**:
   ```bash
   # Fix directory permissions
   chmod -R 755 user/
   ```

3. **API Connection Issues**:
   - Verify API keys and permissions
   - Check network connectivity
   - Test with sandbox environment first

4. **Memory Issues**:
   - Increase system RAM
   - Use swap file if necessary
   - Reduce data cache size

### Getting Help

- Check [troubleshooting guide](../troubleshooting/index.md)
- Review [installation issues](../troubleshooting/installation-issues.md)
- Search [GitHub Issues](https://github.com/defnlnotme/Planar.jl/issues)

## Next Steps

After successful installation:

1. [Configure your first strategy](../guides/strategy-development.md)
2. [Set up exchange connections](../exchanges.md)
3. [Run your first backtest](../guides/execution-modes.md)
4. [Explore optimization features](../optimization.md)

## Security Considerations

- Store API keys securely in `user/secrets.toml`
- Use IP restrictions on exchange APIs
- Start with sandbox/testnet environments
- Regular security audits of API permissions
- Monitor for unusual trading activity

## Updates and Maintenance

```bash
# Update Planar
git pull origin main
git submodule update --recursive

# Update Julia packages
julia --project=Planar -e "using Pkg; Pkg.update()"

# Rebuild if needed
julia --project=Planar -e "using Pkg; Pkg.build()"
```