# Troubleshooting Guide

This section provides solutions to common issues you might encounter while using Planar.

## Quick Links

- [Installation Issues](installation-issues.md) - Problems during setup and installation
- [Exchange Issues](exchange-issues.md) - API connectivity and exchange-related problems  
- [Performance Issues](performance-issues.md) - Optimization and performance troubleshooting

## Common Issues

### Configuration Problems

If you're having trouble with configuration:

1. Check your `user/planar.toml` file syntax
2. Verify API keys are correctly set in `user/secrets.toml`
3. Ensure exchange names match supported exchanges

### Data Issues

For data-related problems:

1. Verify exchange connectivity
2. Check timeframe availability for your exchange
3. Ensure sufficient historical data is available

### Strategy Issues

If your strategy isn't working as expected:

1. Test in simulation mode first
2. Check your strategy logic and parameters
3. Verify data availability for your instruments

## Getting Help

If you can't find a solution here:

1. Check the [GitHub Issues](https://github.com/defnlnotme/Planar.jl/issues)
2. Review the [documentation](../index.md)
3. Ask questions in the community forums

## Reporting Bugs

When reporting issues, please include:

- Planar version
- Julia version
- Operating system
- Complete error messages
- Minimal reproduction steps