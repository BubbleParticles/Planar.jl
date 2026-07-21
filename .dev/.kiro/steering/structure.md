# Project Structure

## Root Level Organization

The project follows a modular Julia package structure with each major component as a separate package:

### Core Modules
- **`Planar/`**: Main entry point and core module integration
- **`PlanarInteractive/`**: Interactive features (plotting, optimization)
- **`PlanarDev/`**: Development utilities and tools
- **`Engine/`**: Core trading engine and fundamental abstractions

### Trading Components
- **`Strategies/`**: Trading strategy framework and base implementations
- **`Executors/`**: Order execution and management logic
- **`SimMode/`**, **`PaperMode/`**, **`LiveMode/`**: Execution environment modes
- **`Exchanges/`**: Exchange-specific implementations and CCXT integration
- **`ExchangeTypes/`**: Type definitions for exchange data structures
- **`OrderTypes/`**: Order type definitions and abstractions

### Data & Analysis
- **`Data/`**: Data management, storage, and retrieval systems
- **`Fetch/`**: Data fetching and pipeline management
- **`Processing/`**: Data processing and transformation utilities
- **`Metrics/`**: Performance measurement and analysis tools
- **`StrategyStats/`**: Strategy-specific statistics and reporting

### Utilities & Support
- **`Instruments/`**: Financial instrument definitions
- **`Collections/`**: Custom data structures and utilities
- **`Misc/`**: Miscellaneous utilities and helpers
- **`Lang/`**: Language extensions and macros
- **`TimeTicks/`**: Time and timeframe handling
- **`Pbar/`**: Progress bar utilities

### Specialized Features
- **`Optim/`**: Parameter optimization algorithms
- **`Plotting/`**: Visualization and charting capabilities
- **`Watchers/`**: Market monitoring and alerting
- **`Remote/`**: Remote control and communication (Telegram bot)
- **`Scrapers/`**: Web scraping utilities for data collection

## Configuration & User Files

### User Directory (`user/`)
- **`planar.toml`**: Main configuration file defining strategies and exchange settings
- **`secrets.toml`**: API keys and sensitive configuration (gitignored)
- **`strategies/`**: User-defined trading strategies
- **`scripts/`**: User utility scripts
- **`logs/`**: Application logs
- **`keys/`**: Cryptographic keys storage
- **`.envrc`**: User-specific environment variables

### Build & Development
- **`scripts/`**: Build scripts, compilation utilities, and deployment tools
- **`docs/`**: Documentation source files
- **`test/`**: Test suites (mostly empty, tests are within individual modules)
- **`vendor/`**: Third-party dependencies and submodules
- **`deps/`**: Build dependencies and compilation tools

## Module Structure Conventions

Each module follows a consistent internal structure:
- **`Project.toml`**: Package definition and dependencies
- **`Manifest.toml`**: Locked dependency versions
- **`src/`**: Source code with main module file
- **`test/`**: Module-specific tests
- **`ext/`**: Package extensions (where applicable)

## Key Files
- **`Project.toml`**: Root project definition
- **`Dockerfile`**: Multi-stage container build definition
- **`.envrc`**: Environment configuration with direnv
- **`.JuliaFormatter.toml`**: Code formatting rules (Blue style, 92 char margin)
- **`resolve.jl`**: Dependency resolution utilities

## Development Patterns

### Module Loading
- Use `@environment!` macro to bring modules into scope
- Conditional precompilation via environment variables
- Lazy loading for optional dependencies

### Strategy Organization
- Strategies defined in `user/strategies/` or as separate packages
- Configuration via `user/planar.toml` with include_file or Project.toml references
- Support for both simple file-based and full package strategies

### Data Storage
- LMDB for high-performance key-value storage
- Zarr format for large timeseries datasets
- User data stored in `user/` directory with proper permissions