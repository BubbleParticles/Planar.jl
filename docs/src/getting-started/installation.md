---
title: "Installation Guide"
description: "Complete installation instructions for Planar on all supported platforms"
category: "getting-started"
difficulty: "beginner"
estimated_time: "10 minutes"
prerequisites: []
topics: [exchanges, data-management, optimization, getting-started, strategy-development, troubleshooting, visualization, configuration]
last_updated: "2025-10-04"
---

# Installation Guide

This guide provides comprehensive installation instructions for Planar on all supported platforms. Choose the method that best fits your needs and experience level.

## Installation Methods

| Method | Best For | Pros | Cons |
|--------|----------|------|------|
| **Docker** | Quick start, production | Fast setup, consistent environment | Larger download, requires Docker |
| **Git Source** | Development, customization | Full control, latest features | More setup steps, dependency management |
| **[Julia](https://julialang.org/) Package** | [Julia](https://julialang.org/) developers | Native [Julia](https://julialang.org/) workflow | Limited to released versions |

## Prerequisites

### System Requirements

- **Operating System**: Linux, macOS, or Windows
- **Memory**: 4GB RAM minimum, 8GB recommended
- **Storage**: 2GB free space for installation, additional space for data
- **Network**: Internet connection for downloading data and dependencies

### Required Software

- **Julia 1.11+**: [Download from julialang.org](https://julialang.org/downloads/)
- **Git**: For source installation ([git-scm.com](https://git-scm.com/))
- **Docker**: For Docker installation ([docker.com](https://www.docker.com/))

## Method 1: Docker Installation (Recommended)

Docker provides the fastest and most reliable way to get started with Planar.

### Step 1: Install Docker

Follow the official Docker installation guide for your platform:
- [Docker Desktop for Windows](https://docs.docker.com/desktop/windows/install/)
- [Docker Desktop for macOS](https://docs.docker.com/desktop/mac/install/)
- [Docker Engine for Linux](https://docs.docker.com/engine/install/)

### Step 2: Choose Your Image

Planar provides four Docker images:

```bash
# Runtime only (smaller, faster download)
docker pull docker.io/psydyllic/planar-sysimage

# With plotting and [optimization](../optimization.md) (recommended for learning)
docker pull docker.io/psydyllic/planar-sysimage-interactive

# Precompiled versions (more flexible, slower startup)
docker pull docker.io/psydyllic/planar-precomp
docker pull docker.io/psydyllic/planar-precomp-interactive
```

**Recommendation**: Use `planar-sysimage-interactive` for getting started.

### Step 3: Run Planar

```bash
# Run with interactive features
docker run -it --rm docker.io/psydyllic/planar-sysimage-interactive julia

# For persistent data storage, mount a volume
docker run -it --rm -v $(pwd)/planar-data:/app/user docker.io/psydyllic/planar-sysimage-interactive julia
```

### Step 4: Verify Installation

Test your Docker installation with this comprehensive verification:

```julia
# Test 1: Basic module loading
using PlanarInteractive
@environment!
println("✅ Modules loaded successfully")

# Test 2: Strategy creation
s = strategy(:QuickStart, exchange.md)=:binance)
println("✅ Strategy system working")

# Test 3: Data system
try
    # Test small data fetch (should work without API keys))
    fetch_ohlcv(s, from=-10)
    println("✅ Data fetching operational")
catch e
    println("⚠️  Data fetch test: $e (this is normal without exchange.md) API)")
end

# Test 4: Plotting capability (interactive image only)
try
    using WGLMakie
    println("✅ Plotting backend available")
catch e
    println("ℹ️  Plotting not available (use interactive image for plotting)")
end

println("🎉 Installation verification complete!")
```

**Expected output**: You should see all green checkmarks. Warnings about data fetching or plotting are normal depending on your setup.

**⚠️ Having issues?** See [Installation Troubleshooting](../troubleshooting/installation-issues.md) for detailed solutions to common problems.

## Method 2: Git Source Installation

Installing from source gives you the latest features and full customization control.

### Step 1: Install Julia

Download and install Julia 1.11+ from [julialang.org](https://julialang.org/downloads/).

Verify installation:
```bash
julia --version
# Should show: julia version 1.11.x
```

### Step 2: Install Git and direnv

**Git** (required):
- Windows: [Git for Windows](https://gitforwindows.org/)
- macOS: `brew install git` or Xcode Command Line Tools
- Linux: `sudo apt install git` (Ubuntu/Debian) or equivalent

**direnv** (recommended for environment management):
- macOS: `brew install direnv`
- Linux: `sudo apt install direnv` or [install from source](https://direnv.net/docs/installation.html)
- Windows: Use WSL or manually manage environment variables

### Step 3: Clone Repository

```bash
# Clone with all submodules
git clone --recurse-submodules https://github.com/psydyllic/Planar.jl
cd Planar.jl

# If you forgot --recurse-submodules
git submodule update --init --recursive
```

### Step 4: Set Up Environment

**With direnv (recommended)**:
```bash
# Allow direnv to load environment variables
direnv allow

# Environment variables are now automatically loaded
echo $JULIA_PROJECT  # Should show: PlanarInteractive
```

**Without direnv**:
```bash
# Manually set environment variables (Linux/macOS)
export JULIA_PROJECT=PlanarInteractive
export JULIA_NUM_THREADS=$(nproc --ignore=2)

# Windows PowerShell
$env:JULIA_PROJECT="PlanarInteractive"
$env:JULIA_NUM_THREADS=[Environment]::ProcessorCount - 2
```

### Step 5: Install Dependencies

```bash
# Start Julia with the correct project
julia --project=PlanarInteractive

# In Julia REPL
] instantiate  # Downloads and builds all dependencies
```

This step may take 10-20 minutes on first run as it compiles many packages.

### Step 6: Verify Installation

Run this comprehensive verification script:

```julia
# Test 1: Module loading
using PlanarInteractive
@environment!
println("✅ Modules loaded successfully")

# Test 2: Strategy system
s = strategy(:QuickStart, exchange.md)=:binance)
println("✅ Strategy creation working")

# Test 3: Configuration system
println("Config loaded: $(s.config.cash) initial balance")
println("✅ Configuration system working")

# Test 4: Data structures
ai = first(s.universe.assets)
println("Asset: $(ai.asset)")
println("✅ Asset system working")

# Test 5: Indicator system
try
    using OnlineTechnicalIndicators
    rsi = OnlineTechnicalIndicators.RSI-development.md#technical-indicators){Float64}(14)
    println("✅ Technical indicators available")
catch e
    println("⚠️  Technical indicators: $e")
end

println("🎉 Source installation verified!")
```

**⚠️ Tests failing?** Check [Installation Troubleshooting](../troubleshooting/installation-issues.md) for step-by-step solutions to common installation problems.

## Method 3: Julia Package Installation

*Note: This method is not yet available as Planar is not in the Julia registry.*

When available, you'll be able to install via:

```julia
using Pkg
Pkg.add("Planar")
```

## Post-Installation Setup

### Configure Your Environment

1. **Create user directory structure**:
```bash
mkdir -p user/strategies user/logs user/keys
```

2. **Copy example configuration**:
```bash
cp user/[planar.toml](../guides/strategy-development.md)-file).example user/[planar.toml](../config.md#configuration-file)
```

3. **Set up secrets file** (for live trading):
```bash
# Create secrets file (never commit this!)
touch user/[secrets.toml](../config.md#secrets-management)
echo "user/[secrets.toml](../config.md#secrets-management)" >> .gitignore
```

### Verify Core Components

Test each major component:

```julia
using PlanarInteractive
@environment!

# Test strategy loading
s = strategy(:QuickStart, exchange=:binance)
println("✅ Strategy system working")

# Test data fetching
try
    fetch_ohlcv(s, from=-10)  # Small test download
    println("✅ Data fetching working")
catch e
    println("⚠️  Data fetching failed: $e")
end

# Test plotting (if using interactive version)
try
    using WGLMakie
    println("✅ Plotting backend available")
catch e
    println("⚠️  Plotting not available: $e")
end
```

## Platform-Specific Notes

### Windows

- **Use PowerShell or WSL**: Command Prompt has limited functionality
- **Long path support**: Enable long path support in Windows if you encounter path length errors
- **Antivirus**: Some antivirus software may interfere with Julia compilation

### macOS

- **Xcode Command Line Tools**: Required for compiling native dependencies
- **Homebrew**: Recommended for installing Git and other tools
- **Apple Silicon**: Fully supported, but some dependencies may need Rosetta

### Linux

- **Package managers**: Use your distribution's package manager for system dependencies
- **Permissions**: Ensure your user has permission to install packages
- **Memory**: Compilation can be memory-intensive; ensure adequate RAM

## Development Environment Setup

For active development, consider these additional tools:

### Julia Development

```julia
# Add development packages
] add Revise, BenchmarkTools, ProfileView, JuliaFormatter

# Set up Revise for automatic code reloading
echo 'using Revise' >> ~/.julia/config/startup.jl
```

### Editor Integration

- **VS Code**: Install the Julia extension
- **Vim/Neovim**: Use julia-vim plugin
- **Emacs**: Use julia-mode

### Git Configuration

```bash
# Set up Julia formatter
cp .JuliaFormatter.toml ~/.JuliaFormatter.toml

# Configure git hooks (optional)
git config core.hooksPath .githooks
```

## Quick Troubleshooting

For comprehensive troubleshooting with detailed solutions, see [Installation Issues](../troubleshooting/installation-issues.md).

### Docker Issues

**Docker not starting**:
```bash
# Check Docker status
docker --version
docker info

# Restart Docker service (Linux)
sudo systemctl restart docker

# On Windows/macOS, restart Docker Desktop
```

**Image pull failures**:
```bash
# Try alternative registry
docker pull ghcr.io/psydyllic/planar-sysimage-interactive

# Check available space
docker system df
docker system prune  # Clean up if needed
```

**Container startup issues**:
```bash
# Check container logs
docker run --rm docker.io/psydyllic/planar-sysimage-interactive julia --version

# Test with minimal command
docker run --rm docker.io/psydyllic/planar-sysimage-interactive echo "Docker working"
```

### Source Installation Issues

**Julia not found**:
```bash
# Verify Julia installation
julia --version
which julia

# Add Julia to PATH (Linux/macOS)
export PATH="$PATH:/path/to/julia/bin"

# Windows: Add to system PATH through Control Panel
```

**Git clone failures**:
```bash
# Check Git configuration
git --version
git config --list

# Clone with HTTPS instead of SSH
git clone https://github.com/psydyllic/Planar.jl
cd Planar.jl
git submodule update --init --recursive
```

**Package compilation errors**:
```julia
# Clear package cache completely
using Pkg
Pkg.gc()
rm(joinpath(first(DEPOT_PATH), "compiled"), recursive=true, force=true)
Pkg.instantiate()
```

**Memory issues during compilation**:
```bash
# Reduce parallel compilation
export JULIA_NUM_THREADS=1

# Increase swap space (Linux)
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

**Permission errors**:
```bash
# Fix Julia depot permissions (Linux/macOS)
sudo chown -R $USER ~/.julia

# Windows: Run as administrator or check folder permissions
```

### Platform-Specific Issues

#### Windows

**PowerShell execution policy**:
```powershell
# Allow script execution
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**Long path issues**:
```powershell
# Enable long paths (requires admin)
New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Value 1 -PropertyType DWORD -Force
```

**Antivirus interference**:
- Add Julia installation directory to antivirus exclusions
- Add `~/.julia` directory to exclusions
- Temporarily disable real-time protection during installation

#### macOS

**Xcode Command Line Tools missing**:
```bash
# Install Xcode Command Line Tools
xcode-select --install

# Verify installation
xcode-select -p
```

**Homebrew issues**:
```bash
# Update Homebrew
brew update
brew doctor

# Reinstall problematic packages
brew reinstall git julia
```

**Apple Silicon compatibility**:
```bash
# Check architecture
uname -m

# Force x86_64 if needed (not recommended)
arch -x86_64 julia
```

#### Linux

**Missing system dependencies**:
```bash
# Ubuntu/Debian
sudo apt update
sudo apt install build-essential git curl

# CentOS/RHEL/Fedora
sudo yum groupinstall "Development Tools"
sudo yum install git curl

# Arch Linux
sudo pacman -S base-devel git curl
```

**Library compatibility issues**:
```bash
# Check system libraries
ldd --version
ldconfig -p | grep -i ssl

# Update system libraries
sudo apt update && sudo apt upgrade  # Ubuntu/Debian
sudo yum update                      # CentOS/RHEL
```

### Network and Connectivity Issues

**Firewall blocking downloads**:
```bash
# Test connectivity
curl -I https://github.com
curl -I https://pkg.julialang.org

# Configure proxy if needed
export https_proxy=http://proxy.company.com:8080
export http_proxy=http://proxy.company.com:8080
```

**DNS resolution issues**:
```bash
# Test DNS
nslookup github.com
nslookup pkg.julialang.org

# Try alternative DNS
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
```

### Performance Issues

**Slow compilation**:
```julia
# Check available resources
using Sys
println("CPU cores: $(Sys.CPU_THREADS)")
println("Memory: $(round(Sys.total_memory()/1024^3, digits=2)) GB")

# Optimize compilation
ENV["JULIA_NUM_THREADS"] = min(Sys.CPU_THREADS, 4)
```

**Disk space issues**:
```bash
# Check available space
df -h

# Clean Julia cache
julia -e 'using Pkg; Pkg.gc()'

# Clean Docker (if using Docker)
docker system prune -a
```

## Installation Verification Checklist

Use this checklist to ensure your installation is complete and working:

### ✅ Basic System Check
- [ ] Julia 1.11+ installed and accessible (`julia --version`)
- [ ] Git installed and working (`git --version`)
- [ ] Docker installed (if using Docker method) (`docker --version`)
- [ ] Sufficient disk space (2GB+ available)
- [ ] Stable internet connection

### ✅ Planar Installation Check
- [ ] Repository cloned successfully (source method)
- [ ] Docker image pulled successfully (Docker method)
- [ ] Environment variables configured (direnv or manual)
- [ ] Julia project activated correctly
- [ ] All dependencies installed without errors

### ✅ Functionality Verification
- [ ] `using PlanarInteractive` loads without errors
- [ ] `@environment!` executes successfully
- [ ] Strategy creation works (`strategy(:QuickStart, exchange=:binance)`)
- [ ] Basic configuration accessible
- [ ] Technical indicators available

### ✅ Optional Features Check
- [ ] Plotting backend loads (`using WGLMakie` or `using GLMakie`)
- [ ] Data fetching works (with internet connection)
- [ ] User directory structure created
- [ ] Configuration files copied

### Getting Help

If any checklist item fails:

1. **Review the error message**: Julia provides detailed error information
2. **Check the [troubleshooting](../troubleshooting/) section**: Most common issues are covered above
3. **Verify prerequisites**: Ensure all system requirements are met
4. **Search existing issues**: Check the [GitHub repository](https://github.com/psydyllic/Planar.jl) for similar problems
5. **Ask for help**: Use the community resources listed in [Contacts](../contacts.md)

### Performance Optimization

After installation, consider these optimizations:

```julia
# Precompile packages for faster startup
using Pkg
Pkg.precompile()

# Create system image for even faster startup (advanced)
# See scripts/build-sysimage.sh for details
```

## See Also

- **[Quick Start](quick-start.md)** - 15-minute getting started tutorial
- **[First Strategy](getting-started/first-strategy.md)** - Build your first trading strategy
- **[Installation Issues](troubleshooting/installation-issues.md)** - Related information

## Next Steps

With Planar installed, you're ready to:

1. **[Run the Quick Start](quick-start.md)** - If you haven't already
2. **[Build Your First Strategy](first-strategy.md)** - Learn strategy development
3. **[Explore the Documentation](../index.md)** - Dive deeper into Planar's capabilities

## Updating Planar

### Docker Images

```bash
# Pull latest image
docker pull docker.io/psydyllic/planar-sysimage-interactive
```

### Source Installation

```bash
# Update repository
git pull origin main
git submodule update --recursive

# Update dependencies
julia --project=PlanarInteractive -e 'using Pkg; Pkg.update()'
```

## Uninstalling Planar

### Docker

```bash
# Remove images
docker rmi docker.io/psydyllic/planar-sysimage-interactive
docker rmi docker.io/psydyllic/planar-sysimage
```

### Source Installation

```bash
# Remove repository
rm -rf Planar.jl

# Clean Julia packages (optional)
julia -e 'using Pkg; Pkg.gc()'
```

Your Planar installation is now complete! Continue with the [First Strategy Tutorial](first-strategy.md) to start building your own trading strategies.