# Technology Stack

## Core Language & Runtime
- **Julia 1.11+**: Primary language with focus on performance and dispatch system
- **Python Integration**: Via PythonCall.jl with async support for external libraries

## Build System & Environment
- **Julia Package Manager**: Standard Pkg.jl for dependency management
- **Docker**: Multi-stage builds with precompilation and sysimage support
- **direnv**: Environment variable management via `.envrc`
- **CondaPkg**: Python environment management integrated with Julia

## Key Dependencies
- **CCXT**: Cryptocurrency exchange API unification (via Ccxt.jl)
- **Zarr.jl**: Large dataset storage and progressive data access
- **DataFrames.jl**: Tabular data manipulation
- **HTTP.jl**: REST API communication
- **JSON3.jl**: Fast JSON parsing
- **LMDB.jl**: High-performance key-value storage

## Architecture Components
- **Engine**: Core trading engine and data management
- **Exchanges**: Exchange-specific implementations and abstractions
- **Strategies**: Trading strategy framework and implementations
- **Executors**: Order execution and management
- **SimMode/PaperMode/LiveMode**: Different execution environments
- **Instruments**: Financial instrument definitions and derivatives
- **Metrics**: Performance measurement and analysis

## Common Commands

### Development Setup
```bash
# Clone with submodules
git clone --recurse-submodules https://github.com/defnlnotme/Planar.jl
cd Planar.jl
direnv allow

# Start Julia with project
julia --project=Planar
# or for interactive features
julia --project=PlanarInteractive
```

### Package Management
```julia
# Instantiate dependencies
] instantiate

# Load main module
using Planar
# or with plotting/optimization
using PlanarInteractive
```

### Docker Usage
```bash
# Development with interactive features
docker pull docker.io/bubbleparticles/planar-sysimage-interactive

# Production deployment
docker pull docker.io/bubbleparticles/planar-sysimage

# Build custom image
scripts/build.sh
```

### Environment Variables
- `JULIA_PROJECT`: Set to Planar or PlanarInteractive
- `JULIA_NUM_THREADS`: CPU thread count (default: nproc-2)
- `JULIA_CONDAPKG_ENV`: Python environment path
- `PLANAR_LIQUIDATION_BUFFER`: Risk management buffer (default: 0.02)

## Code Style
- **JuliaFormatter**: Blue style with 92 character margin
- **Precompilation**: Selective via JULIA_PRECOMP/JULIA_NOPRECOMP env vars
- **Module Structure**: Hierarchical with clear separation of concerns