# Documentation Index

This comprehensive index helps you quickly find information across all Planar documentation.

## Topics by Category

### Getting Started
- **Installation** - [Docker](getting-started/installation.md#Method-2-Docker), [Source](getting-started/installation.md#Method-1-Git-Clone-Recommended)
- **Quick Start** - [15-minute tutorial](getting-started/quick-start.md)
- **First Strategy** - [Tutorial](getting-started/first-strategy.md), [Examples](getting-started/first-strategy.md)

### Strategy Development
- **Strategy Basics** - [Architecture](strategy.md#Strategy-Fundamentals), [Dispatch System](strategy.md#Dispatch-System)
- **Strategy Creation** - [Interactive Generator](strategy.md#Interactive-Strategy-Generator), [Manual Setup](strategy.md#Manual-setup)
- **Strategy Loading** - [Runtime Loading](strategy.md#Loading-a-Strategy), [Configuration](strategy.md#Strategy-Configuration)
- **Advanced Patterns** - [Timeframe Management](guides/data-management.md#Timeframe-Management), [Optimization](optimization.md)
- **Margin Trading** - [Concepts](strategy.md#Margin-Trading-Concepts), [Position Management](advanced/risk-management.md)

### Data Management
- **Storage** - [Zarr Backend](data.md#Zarr-Backend), [LMDB](data.md#Storage-Architecture), [Organization](data.md#Data-Organization)
- **Historical Data** - [DownloadTool](data.md#Historical-Data-with-DownloadTool), [Binance Archives](data.md#Historical-Data-with-DownloadTool)
- **Real-time Data** - [Fetch Module](data.md#Real-Time-Data-with-Fetch), [Rate Limits](data.md#Rate-Limit-Management)
- **Live Streaming** - [Watchers](data.md#Live-Data-Streaming-with-Watchers), [OHLCV Tickers](data.md#OHLCV-Ticker-Watcher)

### Execution Modes
- **Backtesting** - [Configuration](engine/backtesting.md#Backtest-Configuration), [Performance](engine/backtesting.md#Performance-Optimization-Settings)
- **Paper Trading** - [Setup](engine/paper.md), [Real-time Simulation](engine/paper.md)
- **Live Trading** - [API Setup](engine/live.md), [Risk Management](engine/live.md), [Monitoring](engine/live.md)
- **Mode Comparison** - [Feature Matrix](engine/mode-comparison.md#Feature-Comparison-Matrix), [Transition Guide](engine/mode-comparison.md)

### Optimization
- **Methods** - [Grid Search](optimization.md#Grid-Search), [Bayesian Optimization](optimization.md#Bayesian-Optimization)
- **Configuration** - [Parameter Definition](optimization.md#Parameter-Definition), [Objective Functions](optimization.md#Objective-Functions)
- **Results** - [Analysis](optimization.md), [Visualization](plotting.md#Optimization-Result-Visualization)

### Visualization
- **Chart Types** - [OHLCV](plotting.md#OHLCV-Charts), [Trade Visualization](plotting.md#Basic-Trade-Visualization)
- **Customization** - [Styling](plotting.md), [Interactivity](plotting.md#Interactive-Features)
- **Backends** - [GLMakie](plotting.md#GLMakie-Desktop-Applications), [WGLMakie](plotting.md#WGLMakie-Web-Applications)

### Customization
- **Dispatch System** - [Overview](customizations/customizations.md#Dispatch-Patterns), [Patterns](customizations/customizations.md#Dispatch-Patterns)
- **Custom Orders** - [Implementation](customizations/orders.md), [Examples](customizations/orders.md)
- **Exchange Extensions** - [Adding Exchanges](customizations/exchanges.md), [Custom Behavior](customizations/exchanges.md)

## Function Index

### Core Functions
- `strategy()` - [Strategy Loading](strategy.md#Loading-a-Strategy)
- `start!()` - [Backtesting](engine/backtesting.md), [Strategy Execution](strategy.md)
- `call!()` - [Dispatch System](strategy.md#Dispatch-System), [Strategy Interface](strategy.md#Strategy-Interface-Details)
- `fetch_ohlcv()` - [Data Fetching](data.md#Real-Time-Data-with-Fetch)
- `load_ohlcv()` - [Data Loading](data.md#Progressive-Data-Loading)

### Data Functions
- `fetch_candles()` - [Raw Data Fetching](data.md#Error-Handling-and-Data-Validation)
- `binancedownload()` - [Historical Data](data.md#Historical-Data-with-DownloadTool)
- `binanceload()` - [Data Loading](data.md#Historical-Data-with-DownloadTool)

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
- **Constants** - [DESCRIPTION, EXC, MARGIN, TF](strategy.md#Best-Practices)
- **Environment Macros** - [@strategyenv!, @contractsenv!, @optenv!](strategy.md#Best-Practices)
- **Parameters** - [Strategy Attributes](strategy.md#Best-Practices)

### System Configuration
- **Environment Variables** - [JULIA_PROJECT, JULIA_NUM_THREADS](troubleshooting/index.md)
- **Exchange APIs** - [API Keys](engine/live.md), [Sandbox Mode](engine/live.md)
- **Data Storage** - [LMDB Configuration](data.md#Storage-Architecture)

## Error Handling

### Common Issues
- **Installation Problems** - [Dependency Conflicts](troubleshooting/index.md)
- **Strategy Loading** - [Module Not Found](troubleshooting/index.md)
- **Data Issues** - [Missing Data](troubleshooting.md#Data-Storage-and-Management-Issues)
- **Order Execution** - [Insufficient Funds](troubleshooting.md#Order-Execution-Issues)

### Debugging
- **Logging** - [Strategy Debugging](troubleshooting/strategy-problems.md#Debugging-Strategies)
- **State Inspection** - [Debug Methods](troubleshooting/strategy-problems.md#Debugging-Strategies)
- **Performance** - [Profiling](troubleshooting/performance-issues.md#Strategy-Performance)

## File Locations

### User Files
- **Strategies** - `user/[strategies](guides/../guides/strategy-development.md)/`
- **Configuration** - `user/[planar.toml](config.md)-file)`
- **Secrets** - `user/[secrets.toml](config.md#Secrets-Management)`
- **Data** - `user/data.mdb`, `user/lock.mdb`

### Documentation
- **Source** - `docs/src/`
- **API Reference** - `docs/src/API/`
- **Examples** - `user/[strategies](guides/../guides/strategy-development.md)/QuickStart/examples/`

## Search Keywords

### Trading Concepts
- [OHLCV](guides/data-management.md#Data-Collection-Methods), Candlestick, Timeframe, Exchange, Pair, Symbol
- Long, Short, Position, Margin, Leverage, Isolated, Cross
- Buy, Sell, Order, Trade, Execution, Slippage, Fees
- Backtest, Paper Trading, Live Trading, Simulation

### Technical Concepts
- Dispatch, Multiple Dispatch, Type System, Parametric Types
- Strategy, Module, Function, Method, Interface
- Data, Storage, Zarr, LMDB, Fetch, DownloadTool, Watcher
- Optimization, Grid Search, Bayesian, Parameter Tuning

### Performance Concepts
- Sharpe Ratio, Sortino Ratio, Maximum Drawdown, Volatility
- Return, Profit, Loss, Risk, Portfolio, Allocation
- Benchmark, Alpha, Beta, Correlation, Statistics


## See Also

- **[Exchanges](exchanges.md)** - Exchange integration and configuration
- **[Config](config.md)** - Exchange integration and configuration
- **[Overview](troubleshooting/index.md)** - Troubleshooting: Troubleshooting and problem resolution
- **[Optimization](optimization.md)** - Performance optimization techniques
- **[Performance Issues](troubleshooting/performance-issues.md)** - Troubleshooting: Performance optimization techniques
- **[Data Management](guides/../guides/data-management.md)** - Guide: Data handling and management

## Quick Reference

### Key File Paths
- Strategy files: `user/[strategies](guides/../guides/strategy-development.md)/StrategyName.jl`
- Configuration: `user/[planar.toml](config.md#Configuration-File)`
- Documentation: `docs/src/`
- Examples: `user/strategies/QuickStart/examples/`

### Important Links
- [Getting Started](getting-started/index.md) - Begin here
- [Strategy Guide](strategy.md) - Core development guide
- [API Reference](API/api.md) - Complete function documentation
- [Troubleshooting](troubleshooting.md) - Problem solving
- [Community](contacts.md) - Get help and support
