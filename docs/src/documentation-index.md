# Documentation Index

This comprehensive index helps you quickly find information across all Planar documentation.

## Topics by Category

### Getting Started
- **Installation** - [Docker](getting-started/installation.md#docker-installation), [Source](getting-started/installation.md#source-installation)
- **Quick Start** - [15-minute tutorial](getting-started/quick-start.md)
- **First Strategy** - [Tutorial](getting-started/first-strategy.md), [Examples](getting-started/first-strategy.md#strategy-examples)

### Strategy Development
- **Strategy Basics** - [Architecture](strategy.md#strategy-fundamentals), [Dispatch System](strategy.md#dispatch-system)
- **Strategy Creation** - [Interactive Generator](strategy.md#interactive-strategy-generator), [Manual Setup](strategy.md#manual-setup)
- **Strategy Loading** - [Runtime Loading](strategy.md#loading-a-strategy), [Configuration](strategy.md#strategy-configuration)
- **Advanced Patterns** - [Multi-timeframe](strategy.md#multi-timeframe-strategy), [Portfolio Rebalancing](strategy.md#portfolio-rebalancing-strategy)
- **Margin Trading** - [Concepts](strategy.md#margin-trading-concepts), [Position Management](strategy.md#position-management)

### Data Management
- **Storage** - [Zarr Backend](data.md#zarr-backend), [LMDB](data.md#storage-architecture), [Organization](data.md#data-organization)
- **Historical Data** - [Scrapers](data.md#historical-data-with-scrapers), [Binance Archives](data.md#basic-scraper-usage)
- **Real-time Data** - [Fetch Module](data.md#real-time-data-with-fetch), [Rate Limits](data.md#rate-limit-management)
- **Live Streaming** - [Watchers](data.md#live-data-streaming-with-watchers), [OHLCV Tickers](data.md#ohlcv-ticker-watcher)

### Execution Modes
- **Backtesting** - [Configuration](engine/backtesting.md#backtest-configuration), [Performance](engine/backtesting.md#performance-optimization-settings)
- **Paper Trading** - [Setup](engine/paper.md), [Real-time Simulation](engine/paper.md)
- **Live Trading** - [API Setup](engine/live.md), [Risk Management](engine/live.md), [Monitoring](engine/live.md)
- **Mode Comparison** - [Feature Matrix](engine/mode-comparison.md#feature-comparison-matrix), [Transition Guide](engine/mode-comparison.md)

### Optimization
- **Methods** - [Grid Search](optimization.md#grid-search), [Bayesian Optimization](optimization.md#bayesian-optimization)
- **Configuration** - [Parameter Definition](optimization.md#parameter-definition), [Objective Functions](optimization.md#objective-functions)
- **Results** - [Analysis](optimization.md#result-analysis), [Visualization](optimization.md#optimization-visualization)

### Visualization
- **Chart Types** - [OHLCV](plotting.md#ohlcv-charts), [Trade Visualization](plotting.md#trade-visualization)
- **Customization** - [Styling](plotting.md#chart-styling), [Interactivity](plotting.md#interactive-features)
- **Backends** - [GLMakie](plotting.md#glmakie-setup), [WGLMakie](plotting.md#wglmakie-setup)

### Customization
- **Dispatch System** - [Overview](customizations/customizations.md#dispatch-system), [Patterns](customizations/customizations.md#dispatch-patterns)
- **Custom Orders** - [Implementation](customizations/orders.md), [Examples](customizations/orders.md#examples)
- **Exchange Extensions** - [Adding Exchanges](customizations/exchanges.md), [Custom Behavior](customizations/exchanges.md)

## Function Index

### Core Functions
- `strategy()` - [Strategy Loading](strategy.md#loading-a-strategy)
- `start!()` - [Backtesting](engine/backtesting.md), [Strategy Execution](strategy.md)
- `call!()` - [Dispatch System](strategy.md#dispatch-system), [Strategy Interface](strategy.md#strategy-interface-details)
- `fetch_ohlcv()` - [Data Fetching](data.md#basic-fetch-usage)
- `load_ohlcv()` - [Data Loading](strategy.md#quick-example)

### Data Functions
- `fetch_candles()` - [Raw Data Fetching](data.md#data-validation-and-quality-checks)
- `binancedownload()` - [Historical Data](data.md#basic-scraper-usage)
- `binanceload()` - [Data Loading](data.md#basic-scraper-usage)

### Order Functions
- `MarketOrder()` - [Order Types](customizations/orders.md)
- `LimitOrder()` - [Order Types](customizations/orders.md)
- `StopOrder()` - [Order Types](customizations/orders.md)

### Analysis Functions
- `sharpe()` - [Performance Metrics](API/metrics.md)
- `sortino()` - [Performance Metrics](API/metrics.md)
- `maxdrawdown()` - [Risk Metrics](API/metrics.md)

### Plotting Functions
- `balloons()` - [Trade Visualization](plotting.md)
- `ohlcv()` - [OHLCV Charts](plotting.md)
- `plot_optimization()` - [Optimization Results](optimization.md)

## Configuration Topics

### Strategy Configuration
- **Constants** - [DESCRIPTION, EXC, MARGIN, TF](strategy.md#module-constants)
- **Environment Macros** - [@strategyenv!, @contractsenv!, @optenv!](strategy.md#environment-macros)
- **Parameters** - [Strategy Attributes](strategy.md#parameter-management)

### System Configuration
- **Environment Variables** - [JULIA_PROJECT, JULIA_NUM_THREADS](troubleshooting.md#environment-check)
- **Exchange APIs** - [API Keys](engine/live.md), [Sandbox Mode](engine/live.md)
- **Data Storage** - [LMDB Configuration](data.md#storage-architecture)

## Error Handling

### Common Issues
- **Installation Problems** - [Dependency Conflicts](troubleshooting.md#dependency-conflicts)
- **Strategy Loading** - [Module Not Found](troubleshooting.md#strategy-loading-problems)
- **Data Issues** - [Missing Data](troubleshooting.md#data-access-issues)
- **Order Execution** - [Insufficient Funds](troubleshooting.md#order-execution-problems)

### Debugging
- **Logging** - [Strategy Debugging](strategy.md#logging-and-monitoring)
- **State Inspection** - [Debug Methods](strategy.md#strategy-state-inspection)
- **Performance** - [Profiling](strategy.md#performance-profiling)

## File Locations

### User Files
- **Strategies** - `user/strategies/`
- **Configuration** - `user/planar.toml`
- **Secrets** - `user/secrets.toml`
- **Data** - `user/data.mdb`, `user/lock.mdb`

### Documentation
- **Source** - `docs/src/`
- **API Reference** - `docs/src/API/`
- **Examples** - `user/strategies/QuickStart/examples/`

## Search Keywords

### Trading Concepts
- OHLCV, Candlestick, Timeframe, Exchange, Pair, Symbol
- Long, Short, Position, Margin, Leverage, Isolated, Cross
- Buy, Sell, Order, Trade, Execution, Slippage, Fees
- Backtest, Paper Trading, Live Trading, Simulation

### Technical Concepts
- Dispatch, Multiple Dispatch, Type System, Parametric Types
- Strategy, Module, Function, Method, Interface
- Data, Storage, Zarr, LMDB, Fetch, Scraper, Watcher
- Optimization, Grid Search, Bayesian, Parameter Tuning

### Performance Concepts
- Sharpe Ratio, Sortino Ratio, Maximum Drawdown, Volatility
- Return, Profit, Loss, Risk, Portfolio, Allocation
- Benchmark, Alpha, Beta, Correlation, Statistics

## Quick Reference

### Essential Commands
```julia
# Load Planar
using Planar
@environment!

# Create strategy
s = strategy(:MyStrategy)

# Download data
fetch_ohlcv(s, from=-1000)

# Load data
load_ohlcv(s)

# Run backtest
start!(s)

# Plot results
using Plotting
balloons(s)
```

### Key File Paths
- Strategy files: `user/strategies/StrategyName.jl`
- Configuration: `user/planar.toml`
- Documentation: `docs/src/`
- Examples: `user/strategies/QuickStart/examples/`

### Important Links
- [Getting Started](getting-started/index.md) - Begin here
- [Strategy Guide](strategy.md) - Core development guide
- [API Reference](API/) - Complete function documentation
- [Troubleshooting](troubleshooting.md) - Problem solving
- [Community](contacts.md) - Get help and support