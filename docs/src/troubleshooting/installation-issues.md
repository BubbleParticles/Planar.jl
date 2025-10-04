---
title: "Troubleshooting: Installation Issues"
description: "Solutions for installation and setup problems"
category: "troubleshooting"
difficulty: "beginner"
prerequisites: []
related_topics: ["getting-started", "configuration", "environment-setup"]
last_updated: "2025-10-04"
estimated_time: "15 minutes"
---

# Troubleshooting: Installation Issues

This guide covers common problems encountered during Planar installation and initial setup.

## Quick Diagnostics

Before diving into specific issues, try these steps:

1. **Check Julia Version** - Ensure you're using Julia 1.11+
   ```bash
   julia --version
   ```

2. **Verify Project Environment** - Make sure you're in the correct project
   ```bash
   julia --project=Planar  # or PlanarInteractive
   ```

3. **Check System Dependencies** - Verify required system libraries are installed

## Common Installation Issues

### Dependency Conflicts

**Symptoms:**
- Precompilation fails after repository updates
- Package version conflicts in error messages
- "Unsatisfiable requirements" errors

**Cause:**
Package version incompatibilities or outdated dependency resolution.

**Solution:**
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

**Prevention:**
- Regularly update dependencies with `recurse_projects(update=true)`
- Keep Julia version up to date
- Monitor package compatibility announcements

### REPL Startup Issues

**Symptoms:**
- Precompilation errors when activating project in existing REPL
- "Project not found" errors
- Module loading failures

**Cause:**
Incorrect project activation or environment variable conflicts.

**Solution:**
```bash
# Preferred: Start Julia with project directly
julia --project=./Planar

# Alternative: For interactive features
julia --project=./PlanarInteractive

# Check current project status
julia> using Pkg; Pkg.status()
```

**Advanced Diagnostics:**
```julia
# Check environment variables
julia> ENV["JULIA_PROJECT"]
julia> Base.active_project()

# Verify project file exists
julia> isfile("Project.toml")
```

### Python Integration Setup

**Symptoms:**
- `ModuleNotFoundError` for Python packages
- CondaPkg environment failures
- Segmentation faults during Python operations

**Cause:**
Missing Python dependencies or CondaPkg environment issues.

**Solution:**
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

**Platform-Specific Notes:**
- **Linux**: Install `python3-dev` package for development headers
- **macOS**: Ensure Xcode command line tools are installed
- **Windows**: Verify PATH includes Python installation

### LMDB Installation Issues

**Symptoms:**
- "LMDB not available" errors
- Compilation failures during Data module loading
- Database creation failures

**Cause:**
Missing LMDB system libraries or platform compatibility issues.

**Solution:**

**Option 1: Install System LMDB**
```bash
# Ubuntu/Debian
sudo apt-get install liblmdb-dev

# macOS
brew install lmdb

# Windows
# Use vcpkg or conda to install LMDB
```

**Option 2: Disable LMDB (Alternative Storage)**
```julia
# Add to your strategy Project.toml:
[preferences.Data]
data_store = "" # Disables lmdb (set it back to "lmdb" to enable lmdb)
```

**Verification:**
```julia
using Data
zi = zinstance()  # Should work without errors
```

## Platform-Specific Installation Issues

### Linux Issues

**Missing System Libraries:**
```bash
# Install required development packages
sudo apt-get update
sudo apt-get install build-essential libgl1-mesa-glx libxrandr2 libxss1

# For plotting backends
sudo apt-get install libgl1-mesa-dev libxrandr-dev libxinerama-dev libxcursor-dev libxi-dev
```

**Permission Issues:**
```bash
# Fix Docker permissions
sudo usermod -aG docker $USER
# Logout and login again

# Fix file permissions
chmod +x scripts/*.sh
```

### macOS Issues

**Xcode Command Line Tools:**
```bash
# Install if missing
xcode-select --install

# Verify installation
xcode-select -p
```

**Homebrew Dependencies:**
```bash
# Install required packages
brew install lmdb
brew install --cask xquartz  # For X11 support
```

### Windows Issues

**PowerShell Execution Policy:**
```powershell
# Enable script execution
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**Path Length Limitations:**
```powershell
# Enable long paths (requires admin)
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Value 1
```

**Visual C++ Redistributables:**
- Install Microsoft Visual C++ Redistributable packages
- Ensure Windows SDK is available for compilation

## Docker Installation Issues

### Container Startup Failures

**Symptoms:**
- "Permission denied" errors
- Volume mounting failures
- Container exits immediately

**Solution:**
```bash
# Test basic Docker functionality
docker run --rm hello-world

# Check Planar container
docker run --rm -it psydyllic/planar-sysimage-interactive julia --version

# Fix volume mounting (Linux/macOS)
docker run -v $(pwd)/user:/app/user psydyllic/planar-sysimage-interactive

# Windows volume mounting
docker run -v %cd%/user:/app/user psydyllic/planar-sysimage-interactive
```

### Image Pull Issues

**Symptoms:**
- Network timeouts during image pull
- "Image not found" errors
- Authentication failures

**Solution:**
```bash
# Use specific image tags
docker pull psydyllic/planar-sysimage:latest
docker pull psydyllic/planar-sysimage-interactive:latest

# Check available tags
docker search psydyllic/planar

# Alternative: Build locally
./scripts/build.sh
```

## Environment Configuration Issues

### direnv Problems

**Symptoms:**
- Environment variables not loading
- "direnv: error" messages
- Configuration not taking effect

**Solution:**
```bash
# Install direnv if missing
# Ubuntu/Debian: sudo apt-get install direnv
# macOS: brew install direnv
# Windows: Use manual environment variable setup

# Allow .envrc file
direnv allow

# Check direnv status
direnv status

# Reload configuration
direnv reload
```

### Julia Environment Variables

**Common Variables to Check:**
```bash
# Essential variables
export JULIA_PROJECT="./Planar"  # or ./PlanarInteractive
export JULIA_NUM_THREADS=4      # Adjust based on CPU cores

# Optional optimization variables
export JULIA_CONDAPKG_ENV="./user/.conda"
export PLANAR_LIQUIDATION_BUFFER="0.02"

# Debug variables (use sparingly)
export JULIA_DEBUG="MyModule"   # Enable debug logging
```

## Advanced Diagnostics

### Dependency Tree Analysis

```julia
# Check dependency conflicts
using Pkg
Pkg.status()
Pkg.resolve()

# Detailed dependency information
Pkg.dependencies()

# Check for outdated packages
Pkg.outdated()
```

### Precompilation Debugging

```julia
# Force precompilation with verbose output
using Pkg
Pkg.precompile(strict=true)

# Check precompilation cache
julia> Base.find_all_in_cache_path(:MyModule)

# Clear specific module cache
julia> Base.compilecache(Base.PkgId("MyModule"))
```

### System Information Collection

```julia
# Collect system information for bug reports
using InteractiveUtils
versioninfo()

# Julia configuration
Base.julia_cmd()

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

## When to Seek Help

Contact the community if:
- Installation fails after trying all platform-specific solutions
- You encounter system-specific errors not covered here
- Dependencies cannot be resolved after multiple attempts
- Docker containers fail to start with proper configuration

## Getting Help

- [Community Resources](../resources/community.md)
- [GitHub Issues](https://github.com/defnlnotme/Planar.jl/issues)
- [Installation Guide](../getting-started/installation.md)
- [Configuration Reference](../reference/configuration.md)

## See Also

- [Getting Started](../getting-started/) - Initial setup guide
- [Configuration](../config.md) - Environment configuration
- [Strategy Problems](strategy-problems.md) - Post-installation issues
- [Performance Issues](performance-issues.md) - Optimization after setup