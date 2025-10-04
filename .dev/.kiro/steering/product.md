# Product Overview

Planar is an advanced trading bot framework built in Julia, designed for demanding practitioners who need sophisticated cryptocurrency trading capabilities.

## Core Value Propositions

- **Customizable**: Julia's dispatch mechanism enables easy customization without monkey patching
- **Margin/Leverage Support**: Full type hierarchy for isolated and cross margin trading with hedged/unhedged positions
- **Large Dataset Handling**: Uses Zarr.jl for progressive chunk-by-chunk data access and storage
- **Data Consistency**: Ensures OHLCV data integrity with contiguous date checking
- **Lookahead Bias Prevention**: Full-featured date/timeframe handling to prevent common backtesting errors
- **By-Simulation**: Unique ability to run simulation during live trading for tuning and validation
- **Low Code Duplication**: Same strategy code works across backtesting, paper, and live trading modes

## Key Features

- Built around CCXT API with extensibility for custom exchanges
- Fast synchronous backtester (not event-driven)
- Paper mode with real order book simulation
- Live trading with Telegram bot control
- Parameter optimization (grid search, evolution, Bayesian)
- Data feeds pipeline for real-time trading
- Plotting capabilities for OHLCV, indicators, trades, and balances
- Python interop with async support

## Target Users

Sophisticated traders and developers who need:
- Advanced margin trading capabilities
- High-performance backtesting
- Customizable trading logic
- Professional-grade data management
- Multi-exchange support