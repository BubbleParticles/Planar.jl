# Common Code Patterns

Since we've reduced code blocks dramatically, here are common patterns explained:

## Basic Module Loading
Use: `using Planar` followed by `@environment!` to load the framework.

## Strategy Creation
Strategies are typically defined as modules with required functions like `setup!()` and `next!()`.

## Configuration
Configuration is handled through TOML files in the user directory, typically `user/planar.toml`.

## Error Handling
Most functions return results that should be checked. Use try-catch blocks for robust error handling.

## Data Access
Data is accessed through the Data module with functions for OHLCV retrieval and storage.

## Exchange Integration
Exchanges are configured in your TOML file and accessed through the exchange management system.
