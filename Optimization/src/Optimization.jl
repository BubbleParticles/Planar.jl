"""
    Optimization

The `Optimization` module provides tools and abstractions for defining, configuring, and executing optimization routines within the Planar.jl framework. It is designed to support a variety of optimization strategies, including parameter tuning, strategy selection, and performance evaluation for trading systems and related applications. The module integrates seamlessly with other Planar.jl components, ensuring type safety, extensibility, and efficient execution.

Main features:
- Flexible optimization workflows for trading strategies and system parameters
- Integration with Planar.jl's data, strategy, and execution layers
- Support for precompilation and dynamic loading
- Extensible design for custom optimization algorithms

# User-facing Optimization/Search Functions

- `gridsearch(s::Strategy; ...)`: Grid search over parameter combinations for a strategy.
- `progsearch(s::Strategy; ...)`: Progressive search, running multiple grid searches with filtering and resampling.
- `slidesearch(s::Strategy; ...)`: Slides a window over the backtesting period, running optimizations at each step.
- `broadsearch(s::Strategy; ...)`: Performs a broad search by slicing the context and optimizing in each slice.
- `bboptimize(s::Strategy; ...)`: Black-box optimization using the BlackBoxOptim package (supports global optimization algorithms).
- `boptimize!(s::Strategy; ...)`: Bayesian optimization using Gaussian Processes (requires BayesExt and BayesianOptimization.jl).
"""
module Optimization

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
