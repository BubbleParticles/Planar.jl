---
category: "strategy-development"
difficulty: "advanced"
topics: [execution-modes, margin-trading, exchanges, strategy-development]
last_updated: "2025-10-04"---
---

## Custom Orders

This section demonstrates how to implement an OCO (One-Cancels-the-Other) order type for [simulation](../guides/execution-modes.md#simulation-mode) purposes:


We can base our implementation on the existing constructor for limit orders and modify it to meet the requirements of an OCO order:


Next, we introduce two `call!` functions to handle creating and updating simulated OCO orders:


## Custom Instruments

We can extend instruments to create new types such as `Asset` and `Derivative`, which are subtypes of `AbstractAsset`. They are named using the CCXT convention (`QUOTE/BASE:SETTLE`), and it's expected that all instruments define a base and a quote currency.


## See Also

- **[Exchanges](../exchanges.md)** - Exchange integration and configuration
- **[Config](../config.md)** - Exchange integration and configuration
- **[Strategy Development](../guides/strategy-development.md)** - Guide: Strategy development and implementation
- **[Optimization](../optimization.md)** - Strategy development and implementation

## Instances and Exchanges

Asset instances are parameterized by the type of the asset (e.g., asset, derivative) and the exchange they are associated with. By using `ExchangeID` as a parameter, we can fine-tune the behavior for specific exchanges.

For example, if we want to handle OCO orders differently across exchanges in live mode, we can define `call!` functions that are specialized based on the [exchange](../exchanges.md) parameter of the asset instance.


The function above is designed to handle asset instances that are specifically tied to the `bybit` exchange.