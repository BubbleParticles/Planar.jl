# PlanarOptim

Optimization helpers for Planar strategies, wrapping
[Optimization.jl](https://github.com/SciML/Optimization.jl) solvers
(`Optim`, `BlackBoxOptim`, `CMAEvolutionStrategy`, `Manopt`, etc.).

## Contents

- **Parameter optimization:** `optimize_params`, parameter search with bounds,
  constraints, and per-asset universes.
- **Symbolic integration:** symbolic problem building with `Symbolics.jl` for
  analytical gradients and closed-form constraints.

## Usage

```julia
using PlanarOptim

# Optimize a strategy's parameters against a simulation.
res = optimize_params(strat; ...)
best = res.u
```

## Relation to the parent monorepo

PlanarOptim is a strategy-level package in the
[`Planar.jl`](https://github.com/BubbleParticles/Planar.jl) ecosystem (registered
on [Julia's General registry](https://juliahub.com/ui/P/PlanarOptim)).
See the monorepo
[`PACKAGING.md`](../../PACKAGING.md) for registry status and layout details.
