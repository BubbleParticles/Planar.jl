"""
    Optimization

The `Optimization` module provides tools and abstractions for defining, configuring, and executing optimization routines within the Planar.jl framework. It is designed to support a variety of optimization strategies, including parameter tuning, strategy selection, and performance evaluation for trading systems and related applications. The module integrates seamlessly with other Planar.jl components, ensuring type safety, extensibility, and efficient execution.

Main features:
- Flexible optimization workflows for trading strategies and system parameters
- Integration with Planar.jl's data, strategy, and execution layers
- Support for precompilation and dynamic loading
- Extensible design for custom optimization algorithms

# Comparison of Search Methods

| Function      | Data Segmentation         | Parameter Selection         | Main Use Case                                  |
|---------------|--------------------------|----------------------------|------------------------------------------------|
| progsearch    | Segments by offset       | Filters after each round   | Robustness across data segments                |
| broadsearch   | Slices by fixed size     | Filters after each slice   | Adapting to changing regimes over time         |
| slidesearch   | Slides by timeframe      | No parameter search        | Granular, rolling/walk-forward backtesting     |

- `progsearch`: Progressive grid search with filtering and offsetting for robustness.
- `broadsearch`: Sequential grid search over contiguous slices, filtering at each step.
- `slidesearch`: Sliding window backtest, moving by the smallest timeframe increment.

# User-facing Optimization/Search Functions

- `gridsearch(s::Strategy; ...)`: Grid search over parameter combinations for a strategy.
- `progsearch(s::Strategy; ...)`: Progressive search, running multiple grid searches with filtering and resampling.
- `slidesearch(s::Strategy; ...)`: Slides a window over the backtesting period, running optimizations at each step.
- `broadsearch(s::Strategy; ...)`: Performs a broad search by slicing the context and optimizing in each slice.
- `optimize(s::Strategy; ...)`: Black-box optimization using the Optimization.jl framework (supports global optimization algorithms).
- `boptimize!(s::Strategy; ...)`: Bayesian optimization using Gaussian Processes (requires BayesExt and BayesianOptimization.jl).
"""
module Optim

if get(ENV, "JULIA_NOPRECOMP", "") == "all"
    __init__() = begin
        @eval include(joinpath(@__DIR__, "module.jl"))
    end
else
    occursin(string(@__MODULE__), get(ENV, "JULIA_NOPRECOMP", "")) && __precompile__(false)
    include("module.jl")
    if occursin(string(@__MODULE__), get(ENV, "JULIA_PRECOMP", ""))
        include("precompile.jl")
    end
end

end # module Plotting
