# Optimization

Planar provides tools to optimize strategy parameters. Optimzations are managed through the [`Optim.OptSession`](@ref) type. Which is a structure that holds informations about the optimization parameters, configuration and previous runs.
Optimization sessions can be periodically saved, and therefore can be reloaded at a later time to explore previous results or continue the optimization from where it left off.

There are currently 3 different optimization methods: [`Optim.gridsearch`](@ref), [`Optim.optimize`](@ref), `boptimize!`(when using `BayesianOptimization`).
Configuration is done by defining three `call!` functions.

- `call!(::S, ::OptSetup)`: returns a named tuples with:
   - `ctx`: a `Executors.Context` which is the period of time used for backtesting
   - `params`: a named tuple of all the parameters to be optimizied. Values should be in the form of iterables.
   - `bounds`: only required for `optimize`, a tuple of (lower, upper) bounds for the optimization parameters.
- `precision`: optional precision specification for each parameter. Use -1 for integers, 0 for no decimals, 1 for 1 decimal place, etc.
- `categorical`: optional categorical specification for each parameter. Use `nothing` for continuous parameters, or an array of categories for categorical parameters.
- `call!(::S, ::OptRun)`: called before a single backtest is run. Receives one combination of the parameters. Should apply the parameters to the strategy. No return values expected.
- `call!(::S, ::OptScore)::Vector`: for `optimize` and `boptimize!` it is the objective score that advances the optimization. In grid search it can be used to store additional metrics in the results dataframe. Within the `Stats` package there are metrics like `sharpe`` or `sortino` commonly used as optimization objectives.

### Grid search
This is the recommended approach, useful if the strategy has a small set of parameters (<5).
```julia
using Optim
gridsearch(s, splits=1, save_freq=Minute(1), resume=false)
```
Will perform an search from scratch, saving every minute.
`splits` controls the number of times a backtest is run using the _same_ combination of parameters. When splits > 1 we split the optimization `Context` into shorter ranges and restart the backtest on each one of these sub contexes. This allows to fuzz out scenarios of overfitting by averaging the results of different backtest "restarts".

### Black box optimization
The `Optimization.jl` framework offers multiple optimization algorithms through various packages like `OptimizationBBO`, `OptimizationCMAEvolutionStrategy`, etc. You can pass any arguments supported by the underlying optimization solver.

```julia
Optim.optimize(s, splits=3, maxiters=1000)
```

### Precision Support

The optimization framework supports parameter precision constraints. You can specify precision for each parameter:

```julia
# In your strategy's OptSetup function:
return (;
    ctx=Context(...),
    params=(x=1:10, y=0.0:0.1:1.0, z=[:a, :b, :c]),
    bounds=([1.0, 0.0, 1.0], [10.0, 1.0, 3.0]),
    precision=[0, 1, -1],  # x: integer, y: 1 decimal place, z: integer
    categorical=[nothing, nothing, [:a, :b, :c]],  # z is categorical
)
```

Precision values:
- `-1`: Integer parameter
- `0`: No decimal places
- `1`: 1 decimal place
- `2`: 2 decimal places
- etc.

Categorical values:
- `nothing`: Continuous parameter
- `[:a, :b, :c]`: Array of categorical values

**Note**: Precision constraints are applied during parameter evaluation, not during search space definition. The optimizer explores the continuous search space, but parameters are rounded to the specified precision before being applied to the strategy. This approach is compatible with Optimization.jl's interface while still providing precision control.

`@doc optimize` shows the available arguments for the optimization function.

### Speed Optimizations

The optimization framework includes several features to speed up the process:

1. **Result Caching**: Automatically caches results to avoid re-evaluating the same rounded parameters
2. **Early Termination**: Use `early_termination_threshold` to stop evaluation of poor performers early
3. **Parallel Evaluation**: Enable `parallel=true` for concurrent parameter evaluation (requires thread-safe strategy with `THREADSAFE = Ref(true)`)

```julia
# Example with speed optimizations
Optim.optimize(s, 
    parallel=true,
    early_termination_threshold=-0.5,  # Stop if Sharpe ratio < -0.5
    maxiters=1000
)

# To enable parallel optimization, add this to your strategy:
const THREADSAFE = Ref(true)
```

The `BayesianOptimization` package instead focus on gausiann processes and is provided as an extension of the `Optimization` package, (you need to install the packgage yourself). If you want to customize the optimization parameters you can define methods for your strategy over the functions `gpmodel`, `modelopt` and `acquisition`.
Like `optimize` you can pass any upstream kwargs to `boptimize!`.

## Multi-threading
Parallel execution is supported for optimizations, though the extent and approach vary depending on the optimization method used.

### Grid Search
In grid search optimizations, parallel execution is permitted across different parameter combinations, enhancing efficiency. However, repetitions of the optimization process are executed sequentially to maintain result consistency.

### Black Box Optimization
For black box optimization, the scenario is reversed: repetitions are performed in parallel to expedite the overall process, while the individual optimization runs are sequential. This approach is due to the limited benefits of parallelizing these runs and the current limitations in the underlying optimization libraries' multi-threading support.

To enable multi-threading, your strategy must declare a global thread-safe flag as follows:
```
julia
const THREADSAFE = Ref(true)
```

!!! warning "Thread Safety Caution"
    Multi-threading can introduce safety issues, particularly with Python objects. To prevent crashes, avoid using Python objects within your strategy and utilize synchronization mechanisms like locks or `ConcurrentCollections`. Ensuring thread safety is your responsibility.

## Plotting Results
Visualizing the outcomes of an optimization can be accomplished with the `Plotting.plot_results` function. This function is versatile, offering customization options for axes selection (supports up to three axes), color gradients (e.g., depicting cash flow from red to green in a scatter plot), and grouping of result elements. The default visualization is a scatter plot, but surface and contour plots are also supported.

!!! info "Package Loading Order"
    The `plot_results` function is part of the `Plotting` package, which acts as an extension. To use it, perform the following steps:
    ```
    julia
    # Restart the REPL if Planar was previously imported.
    using Pkg: Pkg
    Pkg.activate("PlanarInteractive")
    using PlanarInteractive
    # Now you can call Plotting.plot_results(...)
    ```
    Alternatively, activate and load the `Plotting` package first, followed by the `Optim` package. The `Planar` framework provides convenience functions to streamline this process:
    ```
    julia
    using Planar
    plots!() # This loads the Plotting package.
    using Optim
    ```
