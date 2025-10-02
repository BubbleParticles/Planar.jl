# Installation Guide

This guide provides comprehensive installation instructions for Planar on all supported platforms. Choose the method that best fits your needs and experience level.

## Installation Methods

| Method | Best For | Pros | Cons |
|--------|----------|------|------|
| **Docker** | Quick start, production | Fast setup, consistent environment | Larger download, requires Docker |
| **Git Source** | Development, customization | Full control, latest features | More setup steps, dependency management |
| **Julia Package** | Julia developers | Native Julia workflow | Limited to released versions |

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

# With plotting and optimization (recommended for learning)
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

In the Julia REPL:

```julia
using PlanarInteractive
@environment!

# Test basic functionality
s = strategy(:QuickStart, exchange=:binance)
println("✅ Planar installed successfully!")
```

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

```julia
using PlanarInteractive
@environment!

# Test basic functionality
s = strategy(:QuickStart, exchange=:binance)
println("✅ Planar installed successfully!")
```

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
cp user/planar.toml.example user/planar.toml
```

3. **Set up secrets file** (for live trading):
```bash
# Create secrets file (never commit this!)
touch user/secrets.toml
echo "user/secrets.toml" >> .gitignore
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

## Troubleshooting Installation

### Common Issues

**"Package not found" errors**:
```julia
# Ensure correct project is active
using Pkg
Pkg.activate("PlanarInteractive")
Pkg.instantiate()
```

**Compilation failures**:
```bash
# Clear package cache and retry
julia -e 'using Pkg; Pkg.gc(); Pkg.precompile()'
```

**Permission errors**:
```bash
# Fix Julia depot permissions (Linux/macOS)
sudo chown -R $USER ~/.julia
```

**Memory issues during compilation**:
```bash
# Reduce parallel compilation
export JULIA_NUM_THREADS=1
julia --project=PlanarInteractive -e 'using Pkg; Pkg.instantiate()'
```

### Getting Help

If you encounter issues:

1. **Check the logs**: Julia compilation errors are usually detailed
2. **Search existing issues**: Check the GitHub repository for similar problems
3. **Ask for help**: Use the community resources listed in [Contacts](../contacts.md)

### Performance Optimization

After installation, consider these optimizations:

```julia
# Precompile packages for faster startup
using Pkg
Pkg.precompile()

# Create system image for even faster startup (advanced)
# See scripts/build-sysimage.sh for details
```

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