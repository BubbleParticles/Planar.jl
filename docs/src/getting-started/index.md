# Getting Started with Planar

Welcome to Planar! This section will help you get up and running quickly with the Planar trading framework. Whether you're new to algorithmic trading or experienced with other platforms, these guides will help you understand Planar's unique approach and get your first [strategy](../guides/strategy-development.md) running.

## Learning Objectives

By completing this getting started section, you will:

- **Understand Planar's core concepts** and unique advantages
- **Successfully install and configure** Planar on your system
- **Run your first [backtest](../guides/execution-modes.md#simulation-mode)** and interpret the results
- **Build a custom [strategy](../guides/strategy-development.md)** from scratch using [technical indicators](../guides/strategy-development.md)-development.md#technical-indicators)
- **Analyze performance metrics** and debug strategy issues
- **Know the next steps** for advanced strategy development

## Section Overview

This getting started section is organized in a logical progression:

1. **[Installation Guide](installation.md)** - Set up your development environment *(10 minutes)*
2. **[Quick Start Guide](quick-start.md)** - Run your first strategy and see results *(15 minutes)*
3. **[First Strategy Tutorial](../getting-started/first-strategy.md)** - Build a custom [RSI](../guides/strategy-development.md#technical-indicators) strategy from scratch *(20 minutes)*

**Total estimated time**: 45 minutes

## Why Planar?

Planar is an advanced trading bot framework built in [Julia](https://julialang.org/), designed for demanding practitioners who need sophisticated cryptocurrency trading capabilities. Here's what makes it special:

- **Customizable**: [Julia](https://julialang.org/)'s dispatch mechanism enables easy customization without monkey patching
- **Margin/Leverage Support**: Full type hierarchy for isolated and [cross margin](../guides/strategy-development.md#margin-modes) trading with hedged/unhedged positions
- **Large Dataset Handling**: Uses Zarr.jl for progressive chunk-by-chunk data access and storage
- **Data Consistency**: Ensures [OHLCV data](../guides/data-management.md#ohlcv-data) integrity with contiguous date checking
- **Lookahead Bias Prevention**: Full-featured date/[timeframe](../guides/data-management.md#timeframes) handling to prevent common backtesting errors
- **By-Simulation**: Unique ability to run simulation during live trading for tuning and validation
- **Low Code Duplication**: Same strategy code works across backtesting, paper, and live trading modes

## Prerequisites

### Required Knowledge
- **Basic trading concepts**: Understanding of [OHLCV data](../guides/data-management.md#ohlcv-data), buy/sell orders, and cryptocurrency [exchanges](../exchanges.md)
- **Command line comfort**: Ability to run commands in terminal/command prompt
- **Basic programming concepts**: Variables, functions, and modules ([Julia](https://julialang.org/) experience helpful but not required)

### System Requirements
- **Operating System**: Linux, macOS, or Windows
- **Memory**: 4GB RAM minimum, 8GB recommended for smooth operation
- **Storage**: 2GB free space for installation, additional space for historical data
- **Network**: Stable internet connection for data downloads

### Optional for Getting Started
- Julia 1.11+ (we'll install this together in the installation guide)
- Cryptocurrency [exchange](../guides/strategy-development.md)) account (only needed for live trading, not for learning)

## Recommended Learning Paths

Choose the path that best matches your experience level:

### 🆕 Complete Beginner Path
**Best for**: New to algorithmic trading or Planar  
**Time**: 45 minutes | **Difficulty**: ⭐☆☆

1. [📥 Installation Guide](installation.md) *(10 min)* - Set up your environment
2. [⚡ Quick Start](quick-start.md) *(15 min)* - Run your first [backtest](../guides/execution-modes.md#simulation-mode)  
3. [🎯 First Strategy](../getting-started/first-strategy.md) *(20 min)* - Build from scratch

### 🚀 Experienced Trader Path
**Best for**: Know trading, new to Planar  
**Time**: 25 minutes | **Difficulty**: ⭐⭐☆

1. [⚡ Quick Start](quick-start.md) *(15 min)* - See Planar in action
2. [🎯 First Strategy](../getting-started/first-strategy.md) *(10 min)* - Focus on architecture
3. [🏗️ Strategy Development](../guides/strategy-development.md) - Jump to advanced concepts

### 💻 Developer/Programmer Path  
**Best for**: Comfortable with Julia or similar languages  
**Time**: 15 minutes | **Difficulty**: ⭐⭐⭐

1. [📥 Installation](installation.md) *(5 min)* - Quick setup
2. [🎯 First Strategy](../getting-started/first-strategy.md) *(10 min)* - Understand the patterns
3. [📚 API Reference](../reference/api/index.md) - Dive into the details

## Getting Help

If you run into issues:

- Check the [Troubleshooting Guide](../troubleshooting/index.md)) for common problems
- Review the [API Documentation](../API/api.md) for detailed function references
- Visit our [Contacts](../contacts.md) page for community resources

Let's get started! 🚀

## After Getting Started

Once you complete this section, you'll be ready to:

### Immediate Next Steps
- **[Strategy Development Guide](../guides/strategy-development.md)** - Learn advanced patterns and best practices
- **[Data Management](../data.md)** - Understand Planar's powerful data system  
- **[Execution Modes](../engine/mode-comparison.md)** - Progress from simulation to live trading

### Advanced Topics
- **[Parameter Optimization](../guides/strategy-development.md))** - Systematically improve your [strategies](../guides/strategy-development.md)
- **[Multi-Exchange Trading](../guides/strategy-development.md)).md)** - Scale across multiple exchanges
- **Custom Indicators** - Build your own technical analysis tools

## Related Topics

- **[Data Management](../data.md)** - Understanding Planar's data system
- **[Execution Modes](../engine/mode-comparison.md)** - Sim, Paper, and Live trading modes
- **[Customization](../customizations/customizations.md)** - Extending Planar's functionality
