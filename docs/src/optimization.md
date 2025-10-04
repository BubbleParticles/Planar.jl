---
category: "strategy-development"
difficulty: "advanced"
topics: [execution-modes, margin-trading, data-management, optimization, strategy-development, troubleshooting, visualization, configuration]
last_updated: "2025-10-04"---
---

# Optimization

Planar provides tools to optimize [strategy](../guides/strategy-development.md) parameters. Optimzations are managed through the [`Optim.OptSession`](@ref) type. Which is a structure that holds informations about the [optimization](../optimization.md) parameters, [configuration](../config.md) and previous runs.
Optimization sessions can be periodically saved, and therefore can be reloaded at a later time to explore previous results or continue the [optimization](../optimization.md) from where it left off.

There are currently 3 different [optimization](../optimization.md) methods: [`Optim.gridsearch`](@ref), [`Optim.optimize`](@ref), `boptimize!`(when using `BayesianOptimization`).
Configuration is done by defining three `call!` functions.

- `call!(::S, ::OptSetup)`: returns a named tuples with:
   - `ctx`: a `Executors.Context` which is the period of time used for [backtesting](../guides/execution-modes.md#[simulation](../guides/execution-modes.md#simulation-mode)-mode)
   - `params`: a named tuple of all the parameters to be optimizied. Values should be in the form of iterables.
   - `bounds`: only required for `optimize`, a tuple of (lower, upper) bounds for the optimization parameters.
- `precision`: optional precision specification for each parameter. Use -1 for integers, 0 for no decimals, 1 for 1 decimal place, etc.
- `categorical`: optional categorical specification for each parameter. Use `nothing` for continuous parameters, or an array of categories for categorical parameters.
- `call!(::S, ::OptRun)`: called before a single [backtest](../guides/execution-modes.md#[simulation](../guides/execution-modes.md#simulation-mode)-mode) is run. Receives one combination of the parameters. Should apply the parameters to the [strategy](../guides/strategy-development.md). No return values expected.
- `call!(::S, ::OptScore)::Vector`: for `optimize` and `boptimize!` it is the objective score that advances the optimization. In grid search it can be used to store additional metrics in the results dataframe. Within the `Stats` package there are metrics like `sharpe`` or `sortino` commonly used as optimization objectives.

## Complete Optimization Example

Here's a comprehensive example showing how to implement optimization in your [strategy](../guides/strategy-development.md):

```julia
using Planar
using Optim

# Define your strategy with optimization support
function call!(s::MyStrategy, ::OptSetup)
    # Define the optimization context (time period for [backtesting](../guides/execution-modes.md#[simulation](../guides/execution-modes.md#simulation-mode)-mode))
    ctx = Context(Sim(), tf"1h", dt"2023-01-01", dt"2024-01-01")
    
    # Define parameters to optimize with their ranges
    params = (;
        ma_fast_period = 5:1:20,           # Fast MA period: 5 to 20
        ma_slow_period = 20:5:100,         # Slow MA period: 20 to 100 in steps of 5
        rsi_period = 10:2:30,              # [RSI](../guides/strategy-development.md#technical-indicators) period: 10 to 30 in steps of 2
        rsi_oversold = 20.0:5.0:40.0,      # [RSI](../guides/strategy-development.md#technical-indicators) oversold threshold
        rsi_overbought = 60.0:5.0:80.0,    # [RSI](../guides/strategy-development.md#technical-indicators) overbought threshold
        stop_loss = 0.02:0.01:0.05,        # Stop loss: 2% to 5%
        take_profit = 0.05:0.01:0.15,      # Take profit: 5% to 15%
        position_size = 0.1:0.1:1.0,       # Position size: 10% to 100%
        order_type = [:market, :limit, :stop_limit]  # Order types (categorical)
    )
    
    # Calculate bounds for black box optimization
    lower, upper = Optim.lowerupper(params)
    
    # Define precision constraints
    precision = [
        -1,  # ma_fast_period: integer
        -1,  # ma_slow_period: integer  
        -1,  # rsi_period: integer
        1,   # rsi_oversold: 1 decimal place
        1,   # rsi_overbought: 1 decimal place
        3,   # stop_loss: 3 decimal places
        3,   # take_profit: 3 decimal places
        1,   # position_size: 1 decimal place
        -1   # order_type: integer (categorical index)
    ]
    
    # Define categorical parameters
    categorical = [
        nothing, nothing, nothing, nothing, nothing,
        nothing, nothing, nothing,
        [:market, :limit, :stop_limit]  # order_type is categorical
    ]
    
    return (;
        ctx = ctx,
        params = params,
        space = (; bounds = (lower, upper), precision = precision, categorical = categorical)
    )
end

# Apply parameters before each [backtest](../guides/execution-modes.md#simulation-mode) run
function call!(s::MyStrategy, params, ::OptRun)
    # Extract parameters and apply them to strategy
    s[:ma_fast_period] = params.ma_fast_period
    s[:ma_slow_period] = params.ma_slow_period
    s[:rsi_period] = params.rsi_period
    s[:rsi_oversold] = params.rsi_oversold
    s[:rsi_overbought] = params.rsi_overbought
    s[:stop_loss] = params.stop_loss
    s[:take_profit] = params.take_profit
    s[:position_size] = params.position_size
    s[:order_type] = params.order_type
    
    # Recalculate indicators with new parameters
    recalculate_indicators!(s)
end

# Define optimization objective
function call!(s::MyStrategy, ::OptScore)::Vector
    # Return negative Sharpe ratio for minimization
    # (optimization algorithms typically minimize)
    sharpe = Stats.sharpe(s, tf"1d")
    return [-sharpe]  # Negative because we want to maximize Sharpe
end

# Alternative multi-objective example
function call!(s::MyStrategy, ::OptScore)::Vector
    # Multi-objective optimization: minimize drawdown, maximize return
    max_dd = Stats.maxdrawdown(s)
    total_return = Stats.totalreturn(s)
    
    # Return as vector for multi-objective optimization
    return [max_dd, -total_return]  # Minimize drawdown, maximize return
end
```

## Parameter Definition Patterns

### Basic Parameter Ranges
```julia
params = (;
    # Integer ranges
    period = 10:5:50,                    # 10, 15, 20, ..., 50
    lookback = [7, 14, 21, 28],         # Specific values
    
    # Float ranges  
    threshold = 0.1:0.05:0.5,           # 0.1, 0.15, 0.2, ..., 0.5
    multiplier = 1.0:0.25:3.0,          # 1.0, 1.25, 1.5, ..., 3.0
    
    # Categorical parameters
    ma_type = [:sma, :ema, :wma],       # Moving average types
    [timeframe](../guides/data-management.md#timeframes) = [tf"5m", tf"15m", tf"1h"], # Timeframes
    
    # Boolean parameters (as integers)
    use_filter = [0, 1],                # 0 = false, 1 = true
)
```

### Advanced Parameter Constraints
```julia
function call!(s::MyStrategy, ::OptSetup)
    # Define base parameters
    params = (;
        fast_ma = 5:1:25,
        slow_ma = 20:5:100,
        rsi_period = 10:2:30,
        bb_period = 15:5:30,
        bb_std = 1.5:0.25:3.0
    )
    
    # Custom validation in OptRun to ensure fast_ma < slow_ma
    return (;
        ctx = Context(Sim(), tf"1h", dt"2023-01-01", dt"2024-01-01"),
        params = params,
        space = (; bounds = Optim.lowerupper(params))
    )
end

function call!(s::MyStrategy, params, ::OptRun)
    # Ensure parameter constraints are met
    fast_ma = params.fast_ma
    slow_ma = max(params.slow_ma, fast_ma + 5)  # Ensure slow > fast + 5
    
    s[:fast_ma] = fast_ma
    s[:slow_ma] = slow_ma
    s[:rsi_period] = params.rsi_period
    s[:bb_period] = params.bb_period
    s[:bb_std] = params.bb_std
end
```

### Grid search
This is the recommended approach, useful if the strategy has a small set of parameters (<5).
```julia
using Optim
gridsearch(s, splits=1, save_freq=Minute(1), resume=false)
```
Will perform an search from scratch, saving every minute.
`splits` controls the number of times a [backtest](../guides/execution-modes.md#simulation-mode) is run using the _same_ combination of parameters. When splits > 1 we split the optimization `Context` into shorter ranges and restart the backtest on each one of these sub contexes. This allows to fuzz out scenarios of overfitting by averaging the results of different backtest "restarts".

#### Grid Search Examples

**Basic Grid Search:**
```julia
# Simple grid search with default settings
sess, results = gridsearch(s)

# Grid search with multiple splits for robustness
sess, results = gridsearch(s, splits=3)

# Grid search with periodic saving
sess, results = gridsearch(s, splits=2, save_freq=Minute(5))
```

**Resuming Grid Search:**
```julia
# Resume a previously interrupted grid search
sess, results = gridsearch(s, resume=true)

# Resume with different split [configuration](../config.md)
sess, results = gridsearch(s, splits=5, resume=true)
```

**Grid Search with Custom Objective:**
```julia
function call!(s::MyStrategy, ::OptScore)::Vector
    # Custom multi-metric scoring for grid search
    sharpe = Stats.sharpe(s, tf"1d")
    sortino = Stats.sortino(s, tf"1d")
    max_dd = Stats.maxdrawdown(s)
    total_trades = Stats.ntrades(s)
    
    # Return multiple metrics (all will be stored in results)
    return [sharpe, sortino, max_dd, total_trades]
end

# Run grid search - all metrics will be available in results DataFrame
sess, results = gridsearch(s, splits=2)

# Access results
println("Best Sharpe: ", maximum(results.sharpe))
println("Best parameters: ", results[argmax(results.sharpe), :])
```

### Black box optimization
The `Optimization.jl` framework offers multiple optimization algorithms through various packages like `OptimizationBBO`, `OptimizationCMAEvolutionStrategy`, etc. You can pass any arguments supported by the underlying optimization solver.

```julia
Optim.optimize(s, splits=3, maxiters=1000)
```

#### Black Box Optimization Examples

**Basic Black Box Optimization:**
```julia
# Default BBO optimization
sess, result = optimize(s)

# BBO with custom iterations and splits
sess, result = optimize(s, maxiters=500, splits=3)

# BBO with time limit
sess, result = optimize(s, maxtime=3600, splits=2)  # 1 hour limit
```

**Different Optimization Algorithms:**
```julia
# Differential Evolution (BBO)
sess, result = optimize(s, solve_method=:bbo, maxiters=1000)

# CMA Evolution Strategy
sess, result = optimize(s, solve_method=:evo_cma, maxiters=500)

# Genetic Algorithm
sess, result = optimize(s, solve_method=:evo_ga, maxiters=800)

# LBFGS (gradient-based, requires differentiable objective)
sess, result = optimize(s, solve_method=:lbfgs, maxiters=200)

# Particle Swarm Optimization
sess, result = optimize(s, solve_method=:swarm, maxiters=600)
```

**Multi-Start Optimization:**
```julia
# Run multiple optimization jobs in parallel
sess, result = optimize(s, 
    multistart=true, 
    n_jobs=4,           # 4 parallel optimization runs
    maxiters=500,
    solve_method=:bbo
)
```

**Optimization with Early Termination:**
```julia
# Stop early if objective falls below threshold
sess, result = optimize(s,
    early_threshold=-2.0,    # Stop if Sharpe ratio < -2.0
    max_failures=10,         # Stop after 10 consecutive failures
    maxiters=1000
)
```

**Advanced Black Box Example:**
```julia
# Complex optimization with custom settings
sess, result = optimize(s,
    splits=5,                    # 5-fold cross validation
    maxiters=2000,              # Maximum iterations
    maxtime=7200,               # 2 hour time limit
    solve_method=:evo_cma,      # CMA-ES algorithm
    multistart=true,            # Multi-start optimization
    n_jobs=8,                   # 8 parallel jobs
    early_threshold=-1.5,       # Early stopping threshold
    parallel=true,              # Enable parallel evaluation
    save_freq=Minute(10),       # Save every 10 minutes
    resume=true                 # Resume if interrupted
)

# Access optimization results
println("Best objective: ", result.objective)
println("Best parameters: ", result.u)
println("Optimization time: ", result.solve_time)
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

#### Precision and Categorical Examples

**Mixed Parameter Types:**
```julia
function call!(s::MyStrategy, ::OptSetup)
    params = (;
        # Integer parameters
        ma_period = 10:1:50,           # Will be rounded to integers
        rsi_lookback = 5:1:25,         # Will be rounded to integers
        
        # Float parameters with different precisions
        stop_loss = 0.01:0.001:0.10,   # 3 decimal places
        take_profit = 0.02:0.01:0.20,  # 2 decimal places
        position_size = 0.1:0.05:1.0,  # 1 decimal place
        
        # Categorical parameters
        ma_type = [:sma, :ema, :wma, :hma],
        order_type = [:market, :limit, :stop],
        [timeframe](../guides/data-management.md#timeframes) = [tf"5m", tf"15m", tf"30m", tf"1h"]
    )
    
    lower, upper = Optim.lowerupper(params)
    
    # Define precision for each parameter (in same order as params)
    precision = [
        -1,  # ma_period: integer
        -1,  # rsi_lookback: integer
        3,   # stop_loss: 3 decimal places
        2,   # take_profit: 2 decimal places
        1,   # position_size: 1 decimal place
        -1,  # ma_type: integer (categorical index)
        -1,  # order_type: integer (categorical index)
        -1   # [timeframe](../guides/data-management.md#timeframes): integer (categorical index)
    ]
    
    # Define categorical mappings
    categorical = [
        nothing,                              # ma_period: continuous
        nothing,                              # rsi_lookback: continuous
        nothing,                              # stop_loss: continuous
        nothing,                              # take_profit: continuous
        nothing,                              # position_size: continuous
        [:sma, :ema, :wma, :hma],            # ma_type: categorical
        [:market, :limit, :stop],            # order_type: categorical
        [tf"5m", tf"15m", tf"30m", tf"1h"]   # timeframe: categorical
    ]
    
    return (;
        ctx = Context(Sim(), tf"1h", dt"2023-01-01", dt"2024-01-01"),
        params = params,
        space = (; bounds = (lower, upper), precision = precision, categorical = categorical)
    )
end

function call!(s::MyStrategy, params, ::OptRun)
    # Integer parameters are automatically rounded
    s[:ma_period] = params.ma_period        # Will be integer
    s[:rsi_lookback] = params.rsi_lookback  # Will be integer
    
    # Float parameters are rounded to specified precision
    s[:stop_loss] = params.stop_loss        # Will have 3 decimal places
    s[:take_profit] = params.take_profit    # Will have 2 decimal places
    s[:position_size] = params.position_size # Will have 1 decimal place
    
    # Categorical parameters are mapped to their values
    s[:ma_type] = params.ma_type            # Will be :sma, :ema, :wma, or :hma
    s[:order_type] = params.order_type      # Will be :market, :limit, or :stop
    s[:timeframe] = params.timeframe        # Will be tf"5m", tf"15m", tf"30m", or tf"1h"
end
```

**Time-Based Parameters:**
```julia
function call!(s::MyStrategy, ::OptSetup)
    params = (;
        # Time periods as minutes (will be converted to integers)
        signal_lifetime = [1, 2, 3, 5, 10, 15, 30],  # Minutes
        trade_cooldown = [5, 10, 15, 30, 60],        # Minutes
        order_timeout = [1, 2, 3, 5],                # Minutes
        
        # Regular numeric parameters
        threshold = 0.1:0.05:0.9,
        multiplier = 1.0:0.25:3.0
    )
    
    lower, upper = Optim.lowerupper(params)
    
    return (;
        ctx = Context(Sim(), tf"1m", dt"2023-01-01", dt"2024-01-01"),
        params = params,
        space = (; 
            bounds = (lower, upper),
            precision = [-1, -1, -1, 2, 2],  # All time params as integers
            categorical = [
                [1, 2, 3, 5, 10, 15, 30],    # signal_lifetime options
                [5, 10, 15, 30, 60],         # trade_cooldown options
                [1, 2, 3, 5],                # order_timeout options
                nothing,                      # threshold: continuous
                nothing                       # multiplier: continuous
            ]
        )
    )
end

function call!(s::MyStrategy, params, ::OptRun)
    # Convert time parameters back to Minute objects
    s[:signal_lifetime] = Minute(params.signal_lifetime)
    s[:trade_cooldown] = Minute(params.trade_cooldown)
    s[:order_timeout] = Minute(params.order_timeout)
    
    # Regular parameters
    s[:threshold] = params.threshold
    s[:multiplier] = params.multiplier
end
```

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

#### Performance Optimization Examples

**Thread-Safe Strategy Setup:**
```julia
# In your strategy module
const THREADSAFE = Ref(true)  # Enable parallel optimization

# Ensure your strategy doesn't use shared mutable state
function call!(s::MyStrategy, params, ::OptRun)
    # Use strategy-local state only
    s[:local_param] = params.value
    
    # Avoid global variables or shared state
    # BAD: global_cache[key] = value
    # GOOD: s[:cache][key] = value
end
```

**Caching and Early Termination:**
```julia
# Optimization with aggressive performance settings
sess, result = optimize(s,
    # Parallel settings
    parallel=true,
    multistart=true,
    n_jobs=Threads.nthreads(),
    
    # Early termination
    early_threshold=-2.0,        # Stop if objective < -2.0
    max_failures=5,              # Stop after 5 consecutive failures
    
    # Iteration limits
    maxiters=2000,
    maxtime=3600,                # 1 hour limit
    
    # Caching (automatic, but can be controlled)
    save_freq=Minute(5)          # Save progress every 5 minutes
)
```

**Memory-Efficient Optimization:**
```julia
function call!(s::MyStrategy, ::OptSetup)
    # Use smaller context for faster backtests during optimization
    ctx = Context(Sim(), tf"1h", dt"2023-06-01", dt"2023-12-01")  # 6 months
    
    # Limit parameter space size for grid search
    params = (;
        ma_fast = 5:2:15,        # Reduced range: 5,7,9,11,13,15
        ma_slow = 20:10:60,      # Reduced range: 20,30,40,50,60
        threshold = 0.1:0.1:0.5  # Reduced precision: 0.1,0.2,0.3,0.4,0.5
    )
    
    return (; ctx, params, space=(; bounds=Optim.lowerupper(params)))
end

# For production optimization, use full parameter space and longer context
function call!(s::MyStrategy, ::OptSetup, ::Val{:production})
    ctx = Context(Sim(), tf"1h", dt"2022-01-01", dt"2024-01-01")  # 2 years
    
    params = (;
        ma_fast = 5:1:25,         # Full range
        ma_slow = 20:5:100,       # Full range  
        threshold = 0.05:0.01:0.95 # Full precision
    )
    
    return (; ctx, params, space=(; bounds=Optim.lowerupper(params)))
end
```

**Optimization Progress Monitoring:**
```julia
# Custom callback for monitoring optimization progress
function optimization_callback(u, obj)
    println("Current parameters: ", u)
    println("Current objective: ", obj)
    println("Time: ", now())
    return false  # Continue optimization
end

# Run optimization with monitoring
sess, result = optimize(s,
    maxiters=1000,
    callback=optimization_callback,
    save_freq=Minute(2)  # Frequent saves for monitoring
)

# Monitor optimization session
println("Total evaluations: ", nrow(sess.results))
println("Best objective so far: ", minimum(sess.results.obj))
println("Best parameters: ", sess.best[])
```

The `BayesianOptimization` package instead focus on gausiann processes and is provided as an extension of the `Optimization` package, (you need to install the packgage yourself). If you want to customize the optimization parameters you can define methods for your strategy over the functions `gpmodel`, `modelopt` and `acquisition`.
Like `optimize` you can pass any upstream kwargs to `boptimize!`.

#### Bayesian Optimization Examples

**Basic Bayesian Optimization:**
```julia
# First install BayesianOptimization.jl
using Pkg
Pkg.add("BayesianOptimization")

using BayesianOptimization
using Optim

# Basic Bayesian optimization
sess, result = boptimize!(s, 
    maxiterations=100,
    initializer_iterations=10,  # Random exploration first
    splits=3
)
```

**Custom Bayesian Optimization Settings:**
```julia
# Define custom GP model for your strategy
function gpmodel(s::MyStrategy)
    # Custom Gaussian Process model
    # Return GP model [configuration](../config.md)
end

function modelopt(s::MyStrategy)
    # Custom model optimization settings
    # Return optimization settings for GP hyperparameters
end

function acquisition(s::MyStrategy)
    # Custom acquisition function (e.g., Expected Improvement, UCB)
    # Return acquisition function configuration
end

# Run with custom settings
sess, result = boptimize!(s,
    maxiterations=200,
    initializer_iterations=20,
    splits=5,
    # Custom Bayesian settings will be used automatically
)
```

**Bayesian Optimization with Multiple Objectives:**
```julia
function call!(s::MyStrategy, ::OptScore)::Vector
    # Multi-objective for Bayesian optimization
    sharpe = Stats.sharpe(s, tf"1d")
    sortino = Stats.sortino(s, tf"1d")
    calmar = Stats.calmar(s, tf"1d")
    
    # Weighted combination for single objective
    weights = [0.5, 0.3, 0.2]
    combined = weights[1] * sharpe + weights[2] * sortino + weights[3] * calmar
    
    return [-combined]  # Negative for minimization
end

# Run Bayesian optimization
sess, result = boptimize!(s,
    maxiterations=150,
    initializer_iterations=15,
    splits=4,
    seed=42
)
```

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

### Optimization Result Visualization Examples

**Basic Result Plotting:**
```julia
using PlanarInteractive  # Loads plotting capabilities
using Optim

# Run optimization
sess, result = gridsearch(s, splits=2)

# Basic scatter plot of results
Plotting.plot_results(sess.results, 
    x=:ma_fast_period,     # X-axis parameter
    y=:ma_slow_period,     # Y-axis parameter  
    color=:obj             # Color by objective value
)

# 2D parameter space with objective as color
Plotting.plot_results(sess.results,
    x=:threshold,
    y=:multiplier,
    color=:sharpe,         # Color by Sharpe ratio
    title="Parameter Space Exploration"
)
```

**3D Visualization:**
```julia
# 3D scatter plot
Plotting.plot_results(sess.results,
    x=:ma_fast_period,
    y=:ma_slow_period, 
    z=:rsi_period,         # Z-axis parameter
    color=:obj,            # Color by objective
    plot_type=:scatter3d
)

# Surface plot for continuous parameters
Plotting.plot_results(sess.results,
    x=:threshold,
    y=:multiplier,
    z=:obj,                # Z-axis as objective value
    plot_type=:surface
)
```

**Advanced Visualization Options:**
```julia
# Contour plot for parameter relationships
Plotting.plot_results(sess.results,
    x=:stop_loss,
    y=:take_profit,
    color=:total_return,
    plot_type=:contour,
    levels=20              # Number of contour levels
)

# Grouped results by categorical parameter
Plotting.plot_results(sess.results,
    x=:ma_period,
    y=:obj,
    group=:ma_type,        # Group by [moving average](../guides/strategy-development.md#technical-indicators) type
    plot_type=:scatter,
    title="Performance by MA Type"
)

# Multiple metrics comparison
Plotting.plot_results(sess.results,
    x=:sharpe,
    y=:sortino,
    color=:max_drawdown,
    size=:total_trades,    # Point size by number of trades
    title="Risk-Return Analysis"
)
```

**Time Series of Optimization Progress:**
```julia
# Plot optimization progress over time
progress_df = sess.results
progress_df.iteration = 1:nrow(progress_df)

Plotting.plot_results(progress_df,
    x=:iteration,
    y=:obj,
    plot_type=:line,
    title="Optimization Progress"
)

# Best objective over time (cumulative best)
progress_df.best_so_far = cummin(progress_df.obj)  # Assuming minimization

Plotting.plot_results(progress_df,
    x=:iteration,
    y=:best_so_far,
    plot_type=:line,
    title="Best Objective Over Time"
)
```

**Parameter Sensitivity Analysis:**
```julia
# Box plots for parameter sensitivity
using StatsPlots

# Group results by parameter ranges
results_copy = copy(sess.results)
results_copy.ma_fast_group = cut(results_copy.ma_fast_period, 3)  # 3 groups

@df results_copy boxplot(:ma_fast_group, :obj, 
    title="Objective Sensitivity to Fast MA Period",
    xlabel="Fast MA Period Group",
    ylabel="Objective Value"
)

# Correlation heatmap of parameters and objectives
using Plots
param_cols = [:ma_fast_period, :ma_slow_period, :threshold, :obj, :sharpe, :sortino]
correlation_matrix = cor(Matrix(sess.results[:, param_cols]))

heatmap(correlation_matrix, 
    xticks=(1:length(param_cols), string.(param_cols)),
    yticks=(1:length(param_cols), string.(param_cols)),
    title="Parameter-Objective Correlations"
)
```

**Interactive Optimization Dashboard:**
```julia
using PlotlyJS  # For interactive plots

# Interactive 3D scatter plot
plot_results_interactive = Plotting.plot_results(sess.results,
    x=:ma_fast_period,
    y=:ma_slow_period,
    z=:threshold,
    color=:obj,
    plot_type=:scatter3d,
    backend=:plotlyjs,     # Interactive backend
    title="Interactive Parameter Space"
)

# Add hover information
plot_results_interactive = Plotting.plot_results(sess.results,
    x=:ma_fast_period,
    y=:ma_slow_period,
    color=:obj,
    hover_data=[:sharpe, :sortino, :max_drawdown, :total_trades],
    title="Hover for Details"
)
```

**Optimization Result Analysis:**
```julia
# Find best parameters
best_idx = argmin(sess.results.obj)  # Assuming minimization
best_params = sess.results[best_idx, :]
println("Best parameters: ", best_params)

# Top N results
top_n = 10
top_results = sort(sess.results, :obj)[1:top_n, :]

# Plot top results
Plotting.plot_results(top_results,
    x=:ma_fast_period,
    y=:ma_slow_period,
    color=:obj,
    size=15,               # Larger points for top results
    title="Top $top_n Results"
)

# Parameter distribution of top results
using StatsPlots
@df top_results histogram(:ma_fast_period, 
    bins=10,
    title="Distribution of Fast MA Period in Top Results",
    xlabel="Fast MA Period",
    ylabel="Frequency"
)
```


## See Also

- **[Strategy Development](../guides/strategy-development.md)** - Build optimizable strategies
- **[Performance Issues](../troubleshooting/performance-issues.md)** - Optimize performance
- **[](../reference/api/)** - Optimization API reference
- **[Data Management](../guides/data-management.md)** - Guide: Data handling and management
- **[Exchanges](../exchanges.md)** - Data handling and management
- **[Execution Modes](../guides/execution-modes.md)** - Guide: Backtesting and simulation

## Optimization Result Analysis

Proper analysis of optimization results is crucial for understanding parameter relationships, detecting overfitting, and making informed decisions about strategy deployment.

### Interpreting Optimization Results

**Understanding the Results DataFrame:**
```julia
# After running optimization
sess, result = gridsearch(s, splits=3)

# Examine the results structure
println("Results columns: ", names(sess.results))
println("Number of parameter combinations tested: ", nrow(sess.results))
println("Best objective value: ", minimum(sess.results.obj))

# Basic statistics
using Statistics
println("Objective statistics:")
println("  Mean: ", mean(sess.results.obj))
println("  Std:  ", std(sess.results.obj))
println("  Min:  ", minimum(sess.results.obj))
println("  Max:  ", maximum(sess.results.obj))
```

**Analyzing Parameter Importance:**
```julia
using Statistics, StatsBase

# Calculate parameter correlations with objective
param_columns = [:ma_fast_period, :ma_slow_period, :threshold, :multiplier]
correlations = Dict()

for param in param_columns
    if param in names(sess.results)
        corr = cor(sess.results[!, param], sess.results.obj)
        correlations[param] = corr
        println("$param correlation with objective: $corr")
    end
end

# Sort parameters by absolute correlation
sorted_importance = sort(collect(correlations), by=x->abs(x[2]), rev=true)
println("\nParameter importance ranking:")
for (param, corr) in sorted_importance
    println("  $param: $(round(abs(corr), digits=3))")
end
```

**Statistical Significance Testing:**
```julia
using HypothesisTests

# Compare top 10% vs bottom 10% results
n_results = nrow(sess.results)
top_10_pct = Int(ceil(n_results * 0.1))
bottom_10_pct = Int(floor(n_results * 0.9))

sorted_results = sort(sess.results, :obj)
top_results = sorted_results[1:top_10_pct, :]
bottom_results = sorted_results[bottom_10_pct:end, :]

# Test if parameter distributions differ significantly
for param in param_columns
    if param in names(sess.results)
        top_values = top_results[!, param]
        bottom_values = bottom_results[!, param]
        
        # Mann-Whitney U test (non-parametric)
        test_result = MannWhitneyUTest(top_values, bottom_values)
        p_value = pvalue(test_result)
        
        println("$param significance test p-value: $(round(p_value, digits=4))")
        if p_value < 0.05
            println("  → Significant difference between top and bottom performers")
        else
            println("  → No significant difference")
        end
    end
end
```

### Overfitting Detection and Validation

**Cross-Validation Analysis:**
```julia
# Analyze results across different splits
if :split in names(sess.results)
    using DataFrames
    
    # Group by parameter combination and analyze split consistency
    param_cols = [:ma_fast_period, :ma_slow_period, :threshold]
    grouped = groupby(sess.results, param_cols)
    
    consistency_analysis = combine(grouped) do df
        (
            mean_obj = mean(df.obj),
            std_obj = std(df.obj),
            cv_obj = std(df.obj) / abs(mean(df.obj)),  # Coefficient of variation
            n_splits = nrow(df)
        )
    end
    
    # Sort by mean performance
    sort!(consistency_analysis, :mean_obj)
    
    # Identify stable vs unstable parameter combinations
    stable_threshold = 0.2  # CV threshold for stability
    stable_params = consistency_analysis[consistency_analysis.cv_obj .<= stable_threshold, :]
    unstable_params = consistency_analysis[consistency_analysis.cv_obj .> stable_threshold, :]
    
    println("Stable parameter combinations (CV <= $stable_threshold): ", nrow(stable_params))
    println("Unstable parameter combinations (CV > $stable_threshold): ", nrow(unstable_params))
    
    # Plot stability analysis
    using Plots
    scatter(consistency_analysis.mean_obj, consistency_analysis.cv_obj,
        xlabel="Mean Objective Value",
        ylabel="Coefficient of Variation",
        title="Parameter Stability Analysis",
        legend=false
    )
    hline!([stable_threshold], linestyle=:dash, color=:red, 
           label="Stability Threshold")
end
```

**Out-of-Sample Validation:**
```julia
# Define validation function for out-of-sample testing
function validate_parameters(s, params, validation_period)
    # Apply parameters to strategy
    for (key, value) in pairs(params)
        s[key] = value
    end
    
    # Run backtest on validation period
    validation_ctx = Context(Sim(), s.timeframe, validation_period...)
    backtest_result = backtest!(s, validation_ctx)
    
    # Return validation metrics
    return (
        sharpe = Stats.sharpe(s, tf"1d"),
        sortino = Stats.sortino(s, tf"1d"),
        max_drawdown = Stats.maxdrawdown(s),
        total_return = Stats.totalreturn(s)
    )
end

# Validate top parameters on out-of-sample data
validation_period = (dt"2024-01-01", dt"2024-06-01")  # Different from optimization period
top_n = 5
top_params = sort(sess.results, :obj)[1:top_n, :]

validation_results = []
for row in eachrow(top_params)
    # Extract parameter values
    param_dict = Dict()
    for col in param_columns
        if col in names(top_params)
            param_dict[col] = row[col]
        end
    end
    
    # Validate
    val_result = validate_parameters(s, param_dict, validation_period)
    push!(validation_results, merge(param_dict, val_result))
end

validation_df = DataFrame(validation_results)
println("Out-of-sample validation results:")
println(validation_df)
```

**Robustness Testing:**
```julia
# Test parameter robustness by adding noise
function test_parameter_robustness(s, best_params, noise_levels=[0.05, 0.1, 0.2])
    base_performance = validate_parameters(s, best_params, validation_period)
    
    robustness_results = []
    
    for noise_level in noise_levels
        noise_performances = []
        
        # Test multiple noise realizations
        for trial in 1:10
            noisy_params = Dict()
            for (key, value) in pairs(best_params)
                if value isa Number
                    # Add proportional noise
                    noise = randn() * noise_level * abs(value)
                    noisy_params[key] = value + noise
                else
                    noisy_params[key] = value  # Keep non-numeric params unchanged
                end
            end
            
            noisy_performance = validate_parameters(s, noisy_params, validation_period)
            push!(noise_performances, noisy_performance.sharpe)
        end
        
        push!(robustness_results, (
            noise_level = noise_level,
            mean_performance = mean(noise_performances),
            std_performance = std(noise_performances),
            performance_drop = base_performance.sharpe - mean(noise_performances)
        ))
    end
    
    return DataFrame(robustness_results)
end

# Test robustness of best parameters
best_param_dict = Dict(param => best_params[1, param] for param in param_columns)
robustness_df = test_parameter_robustness(s, best_param_dict)
println("Parameter robustness analysis:")
println(robustness_df)
```

### Visualization for Overfitting Detection

**Performance Distribution Analysis:**
```julia
using Plots, StatsPlots

# Distribution of objective values
histogram(sess.results.obj, 
    bins=30,
    title="Distribution of Optimization Results",
    xlabel="Objective Value",
    ylabel="Frequency",
    alpha=0.7
)

# Q-Q plot to check for normality
using StatsPlots
qqplot(Normal, sess.results.obj,
    title="Q-Q Plot: Objective Values vs Normal Distribution",
    xlabel="Theoretical Quantiles",
    ylabel="Sample Quantiles"
)

# Box plot by parameter values (for discrete parameters)
if :ma_type in names(sess.results)
    @df sess.results boxplot(:ma_type, :obj,
        title="Objective Distribution by MA Type",
        xlabel="Moving Average Type",
        ylabel="Objective Value"
    )
end
```

**Parameter Space Coverage:**
```julia
# Analyze parameter space coverage
function analyze_parameter_coverage(results, param_cols)
    coverage_stats = Dict()
    
    for param in param_cols
        if param in names(results)
            values = results[!, param]
            coverage_stats[param] = (
                unique_values = length(unique(values)),
                min_value = minimum(values),
                max_value = maximum(values),
                range_coverage = length(unique(values)) / (maximum(values) - minimum(values) + 1)
            )
        end
    end
    
    return coverage_stats
end

coverage = analyze_parameter_coverage(sess.results, param_columns)
println("Parameter space coverage analysis:")
for (param, stats) in coverage
    println("$param:")
    println("  Unique values: $(stats.unique_values)")
    println("  Range: $(stats.min_value) to $(stats.max_value)")
    println("  Coverage ratio: $(round(stats.range_coverage, digits=3))")
end
```

**Walk-Forward Analysis:**
```julia
# Implement walk-forward analysis for temporal robustness
function walk_forward_analysis(s, param_combinations, 
                              optimization_window=Month(6),
                              validation_window=Month(1),
                              step_size=Month(1))
    
    start_date = dt"2023-01-01"
    end_date = dt"2024-01-01"
    
    results = []
    current_date = start_date
    
    while current_date + optimization_window + validation_window <= end_date
        # Define periods
        opt_start = current_date
        opt_end = current_date + optimization_window
        val_start = opt_end
        val_end = val_start + validation_window
        
        println("Walk-forward period: $opt_start to $opt_end (opt), $val_start to $val_end (val)")
        
        # Test each parameter combination
        for params in param_combinations
            # Optimization period performance (in-sample)
            opt_performance = validate_parameters(s, params, (opt_start, opt_end))
            
            # Validation period performance (out-of-sample)
            val_performance = validate_parameters(s, params, (val_start, val_end))
            
            push!(results, merge(params, (
                opt_start = opt_start,
                opt_end = opt_end,
                val_start = val_start,
                val_end = val_end,
                in_sample_sharpe = opt_performance.sharpe,
                out_sample_sharpe = val_performance.sharpe,
                performance_decay = opt_performance.sharpe - val_performance.sharpe
            )))
        end
        
        current_date += step_size
    end
    
    return DataFrame(results)
end

# Run walk-forward analysis on top parameter combinations
top_param_dicts = [Dict(param => row[param] for param in param_columns) 
                   for row in eachrow(sort(sess.results, :obj)[1:5, :])]

wf_results = walk_forward_analysis(s, top_param_dicts)

# Analyze walk-forward results
println("Walk-forward analysis summary:")
println("Average in-sample Sharpe: ", mean(wf_results.in_sample_sharpe))
println("Average out-of-sample Sharpe: ", mean(wf_results.out_sample_sharpe))
println("Average performance decay: ", mean(wf_results.performance_decay))

# Plot walk-forward results
plot(wf_results.opt_start, wf_results.in_sample_sharpe, 
     label="In-Sample", marker=:circle)
plot!(wf_results.val_start, wf_results.out_sample_sharpe, 
      label="Out-of-Sample", marker=:square)
title!("Walk-Forward Analysis Results")
xlabel!("Date")
ylabel!("Sharpe Ratio")
```

### Best Practices for Result Analysis

**1. Always Validate Out-of-Sample:**
```julia
# Never deploy parameters without out-of-sample validation
function comprehensive_validation(s, best_params)
    # Multiple validation periods
    validation_periods = [
        (dt"2024-01-01", dt"2024-03-01"),  # Q1 2024
        (dt"2024-04-01", dt"2024-06-01"),  # Q2 2024
        (dt"2024-07-01", dt"2024-09-01"),  # Q3 2024
    ]
    
    validation_results = []
    for (start_date, end_date) in validation_periods
        result = validate_parameters(s, best_params, (start_date, end_date))
        push!(validation_results, merge(result, (period_start=start_date, period_end=end_date)))
    end
    
    return DataFrame(validation_results)
end
```

**2. Check for Parameter Clustering:**
```julia
# Identify if multiple parameter combinations perform similarly
using Clustering

function find_parameter_clusters(results, param_cols, n_clusters=3)
    # Extract parameter matrix
    param_matrix = Matrix(results[:, param_cols])
    
    # Standardize parameters
    param_matrix_std = (param_matrix .- mean(param_matrix, dims=1)) ./ std(param_matrix, dims=1)
    
    # K-means clustering
    clusters = kmeans(param_matrix_std', n_clusters)
    
    # Add cluster assignments to results
    results_with_clusters = copy(results)
    results_with_clusters.cluster = clusters.assignments
    
    # Analyze cluster performance
    cluster_stats = combine(groupby(results_with_clusters, :cluster)) do df
        (
            mean_obj = mean(df.obj),
            std_obj = std(df.obj),
            count = nrow(df),
            best_obj = minimum(df.obj)
        )
    end
    
    return results_with_clusters, cluster_stats
end

clustered_results, cluster_stats = find_parameter_clusters(sess.results, param_columns)
println("Parameter cluster analysis:")
println(cluster_stats)
```

**3. Document Your Analysis:**
```julia
# Create comprehensive analysis report
function create_optimization_report(sess, validation_results, robustness_results)
    report = """
    # Optimization Analysis Report
    
    ## Optimization Summary
    - Total parameter combinations tested: $(nrow(sess.results))
    - Best objective value: $(minimum(sess.results.obj))
    - Optimization period: $(sess.ctx.range.start) to $(sess.ctx.range.stop)
    
    ## Best Parameters
    $(best_params)
    
    ## Validation Results
    $(validation_results)
    
    ## Robustness Analysis
    $(robustness_results)
    
    ## Recommendations
    - Deploy parameters: $(recommendation)
    - Monitor metrics: $(monitoring_metrics)
    - Reoptimization schedule: $(reopt_schedule)
    """
    
    return report
end
```
