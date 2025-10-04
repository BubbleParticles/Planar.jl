# What is Planar?

<!--
Keywords: trading bot, algorithmic trading, cryptocurrency, Julia, backtesting, live trading, strategies, CCXT, dispatch system, margin trading
Description: Planar is a sophisticated trading bot framework built in Julia for automated cryptocurrency trading with support for backtesting, paper trading, and live execution.
-->

Planar is a sophisticated trading bot framework for running automated trading strategies. It enables interactive experimentation of new strategies through the Julia REPL and their live deployment to trading exchanges with minimal code duplication.

## Core Concepts

The framework is built around the concept of **strategies**. A strategy requires a primary currency representing its balance and a primary exchange where all orders are forwarded and validated.

Writing a Planar strategy is equivalent to writing a Julia module that the bot loads (either dynamically or statically on deployments). Within the module, you import the Planar interface and specialize `call!` entry functions specific to your strategy.

## Architecture and Flexibility

The framework provides extensive convenience and utility functions to manipulate strategy and asset objects across different modules. Planar is highly modular, consisting of almost 30 packages, though most are required for full functionality.

From your strategy, you can manage orders through `call!` functions and expect them to be executed during simulation and live trading (through the CCXT library and other venues) while returning **the same data structures** regardless of execution mode.

### Dispatch System Advantage

Planar's key advantage over trading bots in other languages is its flexibility through Julia's parametric type system. This allows extending the bot by specializing functions for specific scenarios. For example, if an exchange behaves differently, you can specialize the `balance` function for that exchange:

```julia
# Specialize balance function for a specific exchange
balance(exc::Exchange{:MyQuirkyExchange}, args...) = ...
```

where `:MyQuirkyExchange` is the `ExchangeID` symbol of the target exchange.

This dispatch pattern enables:

- Strategy `call!` functions that dispatch based on strategy type parameters
- Zero code duplication between simulation and live trading modes
- Execution mode as a type parameter of the strategy

## Key Capabilities

Planar provides comprehensive tools for:

- **Data Management**: Download, clean, and store market data using popular Julia libraries ([Data](data.md))
- **Time Series Processing**: Resample and manipulate time series data ([Processing](./API/processing.md))
- **Live Data Tracking**: Monitor tickers, trades, and OHLCV data ([Watchers](watchers/watchers.md))
- **Performance Analysis**: Compute statistics about backtest runs ([Metrics](metrics.md))
- **Visualization**: Generate interactive plots for OHLCV data, indicators, and backtesting results ([Plotting](plotting.md))
- **Parameter Optimization**: Optimize strategy parameters ([Optimization](optimization.md))

## Installation

### Docker Installation (Recommended)

The recommended installation method is through Docker. Four images are available:

| Configuration | Precompiled 🧰 | Sysimage 📦 |
|---------------|----------------|-------------|
| Runtime Only 🖥️ | `planar-precomp` | `planar-sysimage` |
| With Plotting & Optimization 📊 | `planar-precomp-interactive` | `planar-sysimage-interactive` |

**Image Characteristics**:
- **Precompiled**: Smaller, more flexible, slower startup
- **Sysimage**: Larger, potential compatibility issues, faster startup

```bash
# Pull and run the precompiled image
docker pull docker.io/psydyllic/planar-precomp
docker run -it --rm docker.io/psydyllic/planar-precomp julia

# Load Planar in Julia
using Planar  # or PlanarInteractive for plotting and optimization
```

### Source Installation

**Requirements**: Julia 1.11+ (Planar is not in the Julia registry)

1. **Clone the repository**:
   ```bash
   git clone --recurse-submodules https://github.com/psydyllic/Planar.jl
   cd Planar.jl
   ```

2. **Set up environment**:
   ```bash
   # Review and enable environment variables
   direnv allow
   ```

3. **Start Julia and install dependencies**:
   ```bash
   julia  # Uses JULIA_PROJECT from .envrc
   ```
   
   ```julia
   # In Julia REPL
   ] instantiate
   using Planar  # or PlanarInteractive for plotting and optimization
   ```

## Getting Started

New to Planar? Start with our comprehensive getting started guides:

- **[Quick Start Guide](getting-started/quick-start.md)** - Get your first strategy running in 15 minutes
- **[Installation Guide](getting-started/installation.md)** - Complete setup instructions for all platforms  
- **[First Strategy Tutorial](getting-started/first-strategy.md)** - Build your own custom trading strategy

## Quick Example

For experienced users, here's the essential workflow to get started immediately:

### 1. Load Strategy

```julia
using Planar

@environment!  # Bring modules into scope

# Load default strategy (see ./user/strategies/SimpleStrategy/ or create your own)
s = strategy(:SimpleStrategy, exchange=:binance)
```

### 2. Download Data

```julia
# Download last 1000 candles from strategy exchange
fetch_ohlcv(s, from=-1000)
```

### 3. Load and Backtest

```julia
# Load data into strategy universe
load_ohlcv(s)

# Run backtest for available data period
start!(s)
```

### 4. Visualize Results

```julia
using Plotting
using WGLMakie  # or GLMakie

plots!()  # or Pkg.activate("PlanarInteractive"); using PlanarInteractive
balloons(s)  # Plot simulated trades
```

## Core Modules

The most relevant underlying Planar modules:

### Trading Engine
- **[Engine](./engine/engine.md)** - Core backtesting and execution engine
- **[Strategies](./strategy.md)** - Types and concepts for building trading strategies
- **[Exchanges](./exchanges.md)** - Exchange instances, markets, and pair lists (based on [CCXT](https://docs.ccxt.com/en/latest/manual.html))

### Data and Analysis
- **[Data](./data.md)** - Loading and saving OHLCV data and more (based on Zarr)
- **[Processing](./API/processing.md)** - Data cleanup, normalization, and resampling functions
- **[Watchers](./watchers/watchers.md)** - Services for data pipelines from sources to storage
- **[Metrics](./metrics.md)** - Statistics about backtests and live operations

### Visualization and Optimization
- **[Plotting](./plotting.md)** - Output plots for OHLCV data, indicators, and backtests (based on [Makie](https://github.com/MakieOrg/Makie.jl))
- **[Optimization](./optimization.md)** - Parameter optimization tools and algorithms

### Utilities and Extensions
- **[Remote](./remote.md)** - Remote bot control capabilities
- **[Misc](./API/misc.md)** - Configuration and UI utilities
- **[StrategyTools](./API/strategytools.md)** and **[StrategyStats](./API/strategystats.md)** - Strategy building utilities (additional dependencies required)

## Additional Resources

- **[Troubleshooting](./troubleshooting.md)** - Common issues and solutions
- **[Developer Documentation](./devdocs.md)** - Advanced development topics
- **[Contacts](./contacts.md)** - Community and support information

## Navigation Guide

### New Users
1. **[Getting Started](getting-started/index.md)** - Complete beginner's guide
2. **[Quick Start](getting-started/quick-start.md)** - 15-minute tutorial
3. **[First Strategy](getting-started/first-strategy.md)** - Build your first strategy

### Strategy Developers
1. **[Strategy Development](strategy.md)** - Comprehensive strategy guide
2. **[Data Management](data.md)** - Working with market data
3. **[Execution Modes](engine/mode-comparison.md)** - Backtesting vs live trading
4. **[Optimization](optimization.md)** - Parameter optimization techniques

### Advanced Users
1. **[Customization](customizations/customizations.md)** - Extending Planar
2. **[API Reference](API/api.md)** - Complete function documentation
3. **[Type System](types.md)** - Understanding Planar's types
  
