---
title: "Parameter Optimization"
description: "Complete guide to parameter optimization in Planar, including grid search, Bayesian optimization, and performance tuning"
category: "advanced"
difficulty: "advanced"
---

# Parameter Optimization

Parameter optimization is a crucial aspect of strategy development that helps you find the best configuration for your trading strategies. Planar provides sophisticated optimization tools including grid search, Bayesian optimization, and custom optimization algorithms.

## Overview

Parameter optimization in Planar allows you to:

- **Systematically explore parameter spaces** - Test multiple parameter combinations efficiently
- **Find optimal configurations** - Identify parameter values that maximize your objective function
- **Validate strategy robustness** - Ensure strategies perform well across different parameter ranges
- **Avoid overfitting** - Use proper validation techniques to prevent curve fitting

### Key Features

- **Multiple Algorithms** - Grid search, random search, Bayesian optimization
- **Parallel Execution** - Leverage multiple CPU cores for faster optimization
- **Custom Objectives** - Define your own optimization metrics
- **Result Analysis** - Comprehensive tools for analyzing optimization results
- **Visualization** - Plot optimization surfaces and parameter relationships

## Optimization Workflow

The typical optimization workflow in Planar follows these steps:

1. **Define Parameters** - Specify which strategy parameters to optimize
2. **Set Parameter Ranges** - Define the search space for each parameter
3. **Choose Algorithm** - Select optimization algorithm (grid search, Bayesian, etc.)
4. **Define Objective** - Specify the metric to optimize (Sharpe ratio, profit, etc.)
5. **Run Optimization** - Execute the optimization process
6. **Analyze Results** - Review and validate the optimal parameters

## Parameter Definition

### Basic Parameter Setup

Define optimizable parameters in your strategy:

```julia
mutable struct MyStrategy <: AbstractStrategy
    # Optimizable parameters
    rsi_period::Ref{Int}
    rsi_oversold::Ref{Float64}
    rsi_overbought::Ref{Float64}
    
    # Fixed parameters
    symbol::String
    timeframe::String
    
    # Parameter index for optimization
    params_index::Dict{Symbol, Int}
    
    function MyStrategy(symbol="BTC/USDT", timeframe="1h")
        strategy = new(
            Ref(14),    # RSI period
            Ref(30.0),  # Oversold threshold
            Ref(70.0),  # Overbought threshold
            symbol,
            timeframe,
            Dict{Symbol, Int}()
        )
        
        # Map parameter names to indices
        strategy.params_index[:rsi_period] = 1
        strategy.params_index[:rsi_oversold] = 2
        strategy.params_index[:rsi_overbought] = 3
        
        return strategy
    end
end
```

### Parameter Ranges

Define the search space for optimization:

```julia
# Define parameter ranges
param_ranges = Dict(
    :rsi_period => 10:2:20,           # Test periods 10, 12, 14, 16, 18, 20
    :rsi_oversold => 20.0:5.0:40.0,   # Test thresholds 20, 25, 30, 35, 40
    :rsi_overbought => 60.0:5.0:80.0  # Test thresholds 60, 65, 70, 75, 80
)
```

### Advanced Parameter Types

Support for different parameter types:

```julia
# Continuous parameters
param_ranges = Dict(
    :ma_period => 10:1:50,
    :threshold => 0.01:0.005:0.05,
    :risk_factor => 0.5:0.1:2.0
)

# Categorical parameters
param_ranges = Dict(
    :ma_type => [:sma, :ema, :wma],
    :signal_type => [:momentum, :mean_reversion, :trend_following]
)

# Mixed parameter types
param_ranges = Dict(
    :lookback => 20:5:100,           # Integer range
    :threshold => 0.01:0.01:0.1,     # Float range
    :method => [:linear, :exponential] # Categorical
)
```

## Optimization Algorithms

### Grid Search

Exhaustive search testing all parameter combinations:

```julia
using Planar

# Create strategy instance
strategy = MyStrategy("BTC/USDT", "1h")

# Define parameter ranges
param_ranges = Dict(
    :rsi_period => 10:2:20,
    :rsi_oversold => 25.0:5.0:35.0,
    :rsi_overbought => 65.0:5.0:75.0
)

# Configure optimization
opt_config = OptimizationConfig(
    algorithm = :grid_search,
    objective = :sharpe_ratio,
    parallel = true,
    max_evaluations = 1000
)

# Run optimization
results = optimize_strategy(strategy, param_ranges, opt_config)
```

### Bayesian Optimization

Efficient optimization using probabilistic models:

```julia
# Bayesian optimization configuration
opt_config = OptimizationConfig(
    algorithm = :bayesian,
    objective = :sharpe_ratio,
    max_evaluations = 100,
    acquisition_function = :expected_improvement,
    initial_samples = 10
)

# Run Bayesian optimization
results = optimize_strategy(strategy, param_ranges, opt_config)
```

### Random Search

Random sampling of parameter space:

```julia
# Random search configuration
opt_config = OptimizationConfig(
    algorithm = :random_search,
    objective = :total_return,
    max_evaluations = 200,
    seed = 42  # For reproducible results
)

# Run random search
results = optimize_strategy(strategy, param_ranges, opt_config)
```

### Evolutionary Algorithms

Genetic algorithm-based optimization:

```julia
# Evolutionary optimization
opt_config = OptimizationConfig(
    algorithm = :evolutionary,
    objective = :calmar_ratio,
    population_size = 50,
    generations = 20,
    mutation_rate = 0.1,
    crossover_rate = 0.8
)

# Run evolutionary optimization
results = optimize_strategy(strategy, param_ranges, opt_config)
```

## Objective Functions

### Built-in Objectives

Planar provides several built-in objective functions:

```julia
# Performance metrics
:total_return      # Total portfolio return
:sharpe_ratio      # Risk-adjusted return
:calmar_ratio      # Return vs maximum drawdown
:sortino_ratio     # Downside risk-adjusted return

# Risk metrics
:max_drawdown      # Maximum portfolio drawdown
:volatility        # Portfolio volatility
:var_95           # Value at Risk (95%)

# Trade metrics
:win_rate         # Percentage of winning trades
:profit_factor    # Gross profit / gross loss
:avg_trade_return # Average return per trade
```

### Custom Objective Functions

Define your own optimization objectives:

```julia
# Custom objective function
function custom_objective(results::BacktestResults)
    # Calculate custom metric
    returns = results.portfolio_returns
    trades = results.trades
    
    # Example: Risk-adjusted return with trade frequency penalty
    sharpe = sharpe_ratio(returns)
    trade_frequency = length(trades) / length(returns)
    
    # Penalize excessive trading
    penalty = trade_frequency > 0.1 ? 0.5 : 1.0
    
    return sharpe * penalty
end

# Use custom objective
opt_config = OptimizationConfig(
    algorithm = :bayesian,
    objective = custom_objective,
    maximize = true
)
```

### Multi-Objective Optimization

Optimize multiple objectives simultaneously:

```julia
# Multi-objective configuration
objectives = [
    :sharpe_ratio,
    :max_drawdown,
    :total_return
]

opt_config = MultiObjectiveConfig(
    algorithm = :nsga2,  # Non-dominated Sorting Genetic Algorithm
    objectives = objectives,
    weights = [0.5, 0.3, 0.2],  # Objective weights
    population_size = 100
)

# Run multi-objective optimization
results = optimize_multi_objective(strategy, param_ranges, opt_config)
```

## Optimization Configuration

### Basic Configuration

```julia
opt_config = OptimizationConfig(
    # Algorithm settings
    algorithm = :bayesian,
    max_evaluations = 100,
    
    # Objective settings
    objective = :sharpe_ratio,
    maximize = true,
    
    # Execution settings
    parallel = true,
    n_jobs = 4,
    
    # Validation settings
    validation_split = 0.3,
    cross_validation = true,
    n_folds = 5
)
```

### Advanced Configuration

```julia
opt_config = OptimizationConfig(
    # Algorithm-specific settings
    algorithm = :bayesian,
    acquisition_function = :expected_improvement,
    kernel = :matern52,
    initial_samples = 20,
    
    # Search space settings
    normalize_parameters = true,
    parameter_constraints = Dict(
        # Ensure rsi_oversold < rsi_overbought
        :constraint1 => (params) -> params[:rsi_oversold] < params[:rsi_overbought]
    ),
    
    # Performance settings
    parallel = true,
    batch_size = 10,
    memory_limit = "8GB",
    
    # Stopping criteria
    max_evaluations = 500,
    max_time = 3600,  # 1 hour
    convergence_threshold = 1e-6,
    patience = 50,  # Early stopping
    
    # Validation and robustness
    validation_method = :walk_forward,
    validation_periods = 5,
    bootstrap_samples = 100,
    
    # Logging and output
    verbose = true,
    save_intermediate = true,
    output_directory = "optimization_results"
)
```

## Result Analysis

### Accessing Results

```julia
# Get optimization results
results = optimize_strategy(strategy, param_ranges, opt_config)

# Best parameters
best_params = results.best_parameters
println("Best parameters: $best_params")

# Best objective value
best_score = results.best_score
println("Best score: $best_score")

# All evaluations
all_results = results.evaluations
println("Total evaluations: $(length(all_results))")
```

### Result Visualization

```julia
using Plots

# Plot optimization history
plot_optimization_history(results)

# Parameter importance analysis
plot_parameter_importance(results)

# 2D parameter surface (for 2 parameters)
plot_parameter_surface(results, :rsi_period, :rsi_oversold)

# Correlation matrix
plot_parameter_correlation(results)
```

### Statistical Analysis

```julia
# Parameter sensitivity analysis
sensitivity = analyze_parameter_sensitivity(results)

# Confidence intervals for best parameters
confidence_intervals = bootstrap_confidence_intervals(results, n_samples=1000)

# Robustness testing
robustness = test_parameter_robustness(results, noise_level=0.1)
```

## Validation and Overfitting Prevention

### Cross-Validation

```julia
# Time series cross-validation
opt_config = OptimizationConfig(
    algorithm = :bayesian,
    objective = :sharpe_ratio,
    validation_method = :time_series_cv,
    n_splits = 5,
    test_size = 0.2
)
```

### Walk-Forward Analysis

```julia
# Walk-forward optimization
opt_config = OptimizationConfig(
    algorithm = :grid_search,
    objective = :sharpe_ratio,
    validation_method = :walk_forward,
    optimization_window = 252,  # 1 year
    reoptimization_frequency = 63,  # Quarterly
    out_of_sample_period = 21  # 1 month
)
```

### Out-of-Sample Testing

```julia
# Reserve data for out-of-sample testing
opt_config = OptimizationConfig(
    algorithm = :bayesian,
    objective = :sharpe_ratio,
    train_split = 0.7,
    validation_split = 0.2,
    test_split = 0.1  # Reserved for final validation
)
```

## Performance Optimization

### Parallel Processing

```julia
# Enable parallel optimization
opt_config = OptimizationConfig(
    algorithm = :grid_search,
    parallel = true,
    n_jobs = 8,  # Use 8 CPU cores
    batch_size = 16  # Process 16 evaluations per batch
)
```

### Memory Management

```julia
# Memory-efficient optimization
opt_config = OptimizationConfig(
    algorithm = :bayesian,
    memory_efficient = true,
    cache_size = 1000,  # Cache last 1000 evaluations
    disk_cache = true,  # Use disk for large results
    compression = true  # Compress cached data
)
```

### Early Stopping

```julia
# Early stopping configuration
opt_config = OptimizationConfig(
    algorithm = :bayesian,
    early_stopping = true,
    patience = 50,  # Stop if no improvement for 50 evaluations
    min_improvement = 0.001,  # Minimum improvement threshold
    convergence_window = 20  # Window for convergence check
)
```

## Advanced Techniques

### Hierarchical Optimization

```julia
# Two-stage optimization
function hierarchical_optimization(strategy, param_ranges)
    # Stage 1: Coarse grid search
    coarse_ranges = Dict(
        :rsi_period => 10:5:30,
        :rsi_oversold => 20:10:40
    )
    
    coarse_results = optimize_strategy(strategy, coarse_ranges, 
                                     OptimizationConfig(algorithm=:grid_search))
    
    # Stage 2: Fine-tuned Bayesian optimization around best region
    best_params = coarse_results.best_parameters
    fine_ranges = refine_parameter_ranges(best_params, factor=0.2)
    
    fine_results = optimize_strategy(strategy, fine_ranges,
                                   OptimizationConfig(algorithm=:bayesian))
    
    return fine_results
end
```

### Ensemble Optimization

```julia
# Optimize ensemble of strategies
strategies = [
    TrendFollowingStrategy(),
    MeanReversionStrategy(),
    MomentumStrategy()
]

# Optimize weights and individual parameters
ensemble_config = EnsembleOptimizationConfig(
    strategies = strategies,
    weight_optimization = true,
    individual_optimization = true,
    correlation_penalty = 0.1
)

results = optimize_ensemble(strategies, param_ranges, ensemble_config)
```

### Adaptive Optimization

```julia
# Adaptive parameter optimization during live trading
adaptive_config = AdaptiveOptimizationConfig(
    reoptimization_frequency = "monthly",
    lookback_window = 252,  # 1 year
    min_performance_threshold = 0.05,  # Reoptimize if performance drops
    parameter_drift_detection = true
)

# Start adaptive optimization
start_adaptive_optimization(strategy, adaptive_config)
```

## Best Practices

### Parameter Selection

1. **Start Simple** - Begin with a few key parameters
2. **Domain Knowledge** - Use reasonable parameter ranges based on market knowledge
3. **Correlation Awareness** - Avoid highly correlated parameters
4. **Stability Testing** - Ensure parameters are stable across different market conditions

### Optimization Strategy

1. **Coarse to Fine** - Start with coarse grid search, then refine with Bayesian optimization
2. **Multiple Objectives** - Consider multiple metrics, not just returns
3. **Robustness Testing** - Test parameter sensitivity and stability
4. **Out-of-Sample Validation** - Always validate on unseen data

### Avoiding Overfitting

1. **Cross-Validation** - Use proper time series cross-validation
2. **Parameter Constraints** - Apply reasonable bounds to parameters
3. **Regularization** - Penalize excessive complexity
4. **Walk-Forward Testing** - Simulate realistic trading conditions

## Troubleshooting

### Common Issues

1. **Slow Optimization**
   - Enable parallel processing
   - Reduce parameter space size
   - Use more efficient algorithms (Bayesian vs grid search)

2. **Poor Results**
   - Check parameter ranges are reasonable
   - Verify objective function is appropriate
   - Ensure sufficient data for optimization

3. **Overfitting**
   - Use cross-validation
   - Reduce parameter complexity
   - Test on out-of-sample data

4. **Memory Issues**
   - Enable memory-efficient mode
   - Reduce batch size
   - Use disk caching

### Debug Mode

```julia
# Enable debug logging
ENV["JULIA_DEBUG"] = "Optimization"

# Run optimization with detailed logging
results = optimize_strategy(strategy, param_ranges, opt_config)
```

## See Also

- [Strategy Development](guides/strategy-development.md) - Creating optimizable strategies
- [Execution Modes](guides/execution-modes.md) - Testing optimized strategies
- [Performance Analysis](metrics.md) - Analyzing optimization results
- [Plotting](plotting.md) - Visualizing optimization results
- [API Reference](API/optimization.md) - Optimization API documentation