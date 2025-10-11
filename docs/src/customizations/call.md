---
category: "strategy-development"
difficulty: "advanced"
topics: [strategy-development]
last_updated: "2025-10-04"---
---

# Adding call! Functions

To introduce new `call!` functions, adhere to the following procedure:

1. **Traits Addition**: Go to the `Executors` module, specifically the `Executors/src/executors.jl` file, and add your new trait. Ensure that you export the trait.

2. **Function Implementation**: Define the necessary functions in the `{SimMode,PaperMode,LiveMode}/src/call.jl` files. If the behavior for paper and live mode is identical, use `RTStrategy` as a dispatch type and place the shared function definition in `PaperMode/src/call.jl`.

3. **Macro Modification**: In the `Planar/src/planar.jl` file, modify the `@strategyeng!` macro (or the `@contractsenv!` macro for functions dealing with derivatives). Import your new trait, for example, `using .pln.Engine.Executors: MyNewTrait`.

Conform to the established argument order convention for the [strategy](../guides/../guides/strategy-development.md) signature:


Follow these steps carefully to ensure the seamless integration of new `call!` functions into the system.

## See Also

- **[Strategy Development](../guides/../guides/strategy-development.md)** - Guide: Strategy development and implementation
- **[Optimization](../optimization.md)** - Strategy development and implementation
