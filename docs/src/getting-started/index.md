# Getting Started with Planar

Welcome to Planar! This section will help you get up and running quickly with the Planar trading framework. Whether you're new to algorithmic trading or experienced with other platforms, these guides will help you understand Planar's unique approach and get your first strategy running.

## What You'll Learn

This getting started section covers everything you need to begin trading with Planar:

1. **[Quick Start Guide](quick-start.md)** - Get your first strategy running in 15 minutes
2. **[Installation Guide](installation.md)** - Comprehensive setup for all platforms
3. **[First Strategy Tutorial](first-strategy.md)** - Build and understand your first custom strategy

## Why Planar?

Planar is an advanced trading bot framework built in Julia, designed for demanding practitioners who need sophisticated cryptocurrency trading capabilities. Here's what makes it special:

- **Customizable**: Julia's dispatch mechanism enables easy customization without monkey patching
- **Margin/Leverage Support**: Full type hierarchy for isolated and cross margin trading with hedged/unhedged positions
- **Large Dataset Handling**: Uses Zarr.jl for progressive chunk-by-chunk data access and storage
- **Data Consistency**: Ensures OHLCV data integrity with contiguous date checking
- **Lookahead Bias Prevention**: Full-featured date/timeframe handling to prevent common backtesting errors
- **By-Simulation**: Unique ability to run simulation during live trading for tuning and validation
- **Low Code Duplication**: Same strategy code works across backtesting, paper, and live trading modes

## Prerequisites

Before starting, you should have:

- Basic understanding of trading concepts (OHLCV data, orders, exchanges)
- Familiarity with command line interfaces
- Julia 1.11+ installed (we'll cover this in the installation guide)
- A cryptocurrency exchange account for live trading (optional for getting started)

## Learning Path

We recommend following this path:

1. **Start with Quick Start** - Get familiar with Planar's basic concepts
2. **Follow the Installation Guide** - Set up your development environment properly
3. **Build Your First Strategy** - Learn Planar's strategy development patterns
4. **Explore Advanced Features** - Dive into optimization, plotting, and customization

## Getting Help

If you run into issues:

- Check the [Troubleshooting Guide](../troubleshooting.md) for common problems
- Review the [API Documentation](../API/api.md) for detailed function references
- Visit our [Contacts](../contacts.md) page for community resources

Let's get started! 🚀

## Next Steps

Ready to begin? Choose your path:

- **[Quick Start →](quick-start.md)** - Jump right in with a 15-minute tutorial
- **[Installation →](installation.md)** - Set up your development environment first
- **[Strategy Development →](../strategy.md)** - Learn about Planar's strategy system

## Related Topics

- **[Data Management](../data.md)** - Understanding Planar's data system
- **[Execution Modes](../engine/mode-comparison.md)** - Sim, Paper, and Live trading modes
- **[Customization](../customizations/customizations.md)** - Extending Planar's functionality