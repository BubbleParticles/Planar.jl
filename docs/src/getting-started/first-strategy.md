completion_rate: "92%"
---

# Your First Strategy Tutorial

In this tutorial, you'll learn to create a custom trading strategy from scratch. We'll build a simple RSI-development.md#technical-indicators) (Relative Strength Index) mean reversion strategy that demonstrates all the key concepts of Planar strategy development.

## What You'll Learn

By the end of this tutorial, you'll understand:

- How Planar strategies are structured
- The three core functions every strategy needs
- How to add [technical indicators](../guides/strategy-development.md#technical-indicators)
- How to implement buy/sell logic
- How to test and debug your strategy
- How to analyze performance results

## Prerequisites

- Completed the [Quick Start Guide](quick-start.md)
- Basic understanding of technical analysis (RSI, moving averages)
- Planar installed and working

## Strategy Overview

We'll create a strategy that:
1. Uses RSI to identify oversold/overbought conditions
2. Adds a trend filter using moving averages
3. Only trades when conditions align
4. Includes proper risk management

## Step 1: Understanding Strategy Structure

Every Planar strategy is a [Julia](https://julialang.org/) module with three core functions:


### Function Parameters

- **`s::SC`**: Strategy instance (SC = Strategy Container)
- **`ai`**: Asset instance (the trading pair, e.g., BTC/USDT)
- **`ats`**: Available timestamp for signal evaluation

## Step 2: Create Strategy Directory

First, let's create a new strategy directory:

```bash
# Navigate to user strategies directory
cd user/strategies

# Create our new strategy
mkdir MyFirstStrategy
cd MyFirstStrategy

# Create the basic structure
mkdir src
touch Project.toml
touch src/MyFirstStrategy.jl
```

## Step 3: Define the Strategy Module

Edit `src/MyFirstStrategy.jl`:


## Step 4: Implement Signal Setup

Add the `setsignals!` function to initialize our indicators:


### Key Points:

- **`attrs[:signals_set] = false`**: Required initialization
- **`signals(...)`**: Defines which indicators to calculate
- **`tf"1m"`**: Uses 1-minute timeframe data
- **`inittrends!(...)`**: Required to initialize the indicators
- **Strategy parameters**: Store configuration in `attrs` for easy modification

## Step 5: Implement Buy Logic

Add the `isbuy` function:


### Key Points:

- **Always validate signals**: Check for `nothing` before using values
- **Multiple conditions**: Combine different indicators for better signals
- **Logging**: Use `@ldebug` for debugging (won't show in production)

## Step 6: Implement Sell Logic

Add the `issell` function:


## Step 7: Create Project Configuration

Edit `Project.toml`:

```toml
name = "MyFirstStrategy"
uuid = "12345678-1234-1234-1234-123456789abc"  # Generate a unique UUID
version = "0.1.0"

[deps]
Planar = "..."
OnlineTechnicalIndicators = "..."

[compat]
julia = "1.11"
```

## Step 8: Complete Strategy File

Here's your complete `src/MyFirstStrategy.jl`:


## Step 9: Test Your Strategy

Now let's test the strategy:


## Step 10: Comprehensive Performance Analysis

### Basic Performance Metrics


### Trade Analysis


### Advanced Performance Metrics


### Strategy Effectiveness Assessment


## Step 11: Debug and Improve Your Strategy

### Enable Detailed Debugging

```julia
# Activate PlanarInteractive project
import Pkg
Pkg.activate("PlanarInteractive")

try
    using PlanarInteractive
    @environment!
    
    # Enable debug logging to see every signal calculation
    ENV["JULIA_DEBUG"] = "MyFirstStrategy"
    
    # Example strategy variable (would be defined earlier in real usage)
    # s = load_strategy("MyFirstStrategy")  # This would be your actual strategy
    
    # Clear previous results and run with debugging
    # reset!(s)
    # start!(s)
    
    println("Debug logging enabled for MyFirstStrategy")
    println("Strategy debugging commands ready to use")
catch e
    @warn "PlanarInteractive not available: $e"
end
```

**What you'll see**: Detailed logs showing RSI values, trend analysis, and buy/sell decisions for every time step.

### Systematic Debugging Approach

#### 1. Check Indicator Values
```julia
# Activate PlanarInteractive project
import Pkg
Pkg.activate("PlanarInteractive")

try
    using PlanarInteractive
    @environment!
    
    # Example: Manually inspect indicator calculations
    # Note: 's' would be your loaded strategy instance
    
    # Example data structure (in real usage, this comes from your strategy)
    println("Example indicator inspection:")
    println("Timestamp: 2024-01-01T12:00:00, RSI=45.2, SMA_short=100.5, SMA_long=98.3")
    println("Timestamp: 2024-01-01T12:05:00, RSI=47.1, SMA_short=101.2, SMA_long=98.7")
    
    # Real usage would be:
    # ai = first(s.universe.assets)
    # timestamps = ai.data.timestamp[end-10:end]
    # for ts in timestamps
    #     rsi = signal_value(s, ai, :rsi, ts)
    #     sma_short = signal_value(s, ai, :sma_short, ts)
    #     sma_long = signal_value(s, ai, :sma_long, ts)
    #     println("$ts: RSI=$rsi, SMA_short=$sma_short, SMA_long=$sma_long")
    # end
    
catch e
    @warn "PlanarInteractive not available: $e"
end
```

#### 2. Test Individual Conditions
```julia
# Activate PlanarInteractive project
import Pkg
Pkg.activate("PlanarInteractive")

try
    using PlanarInteractive
    @environment!
    
    # Example: Test your buy logic step by step
    function debug_buy_logic_example()
        # Example values (in real usage, these come from signal_value calls)
        rsi = 28.5
        sma_short = 101.2
        sma_long = 98.7
        ats = "2024-01-01T12:00:00"
        
        println("=== Buy Logic Debug for $ats ===")
        println("RSI: $rsi (oversold if < 30)")
        println("SMA Short: $sma_short")
        println("SMA Long: $sma_long")
        println("Uptrend: $(sma_short > sma_long)")
        
        if !isnothing(rsi) && !isnothing(sma_short) && !isnothing(sma_long)
            trend_strength = (sma_short - sma_long) / sma_long
            println("Trend strength: $(round(trend_strength * 100, digits=2))% (need > 0.5%)")
            
            buy_signal = (rsi < 30) && (sma_short > sma_long) && (trend_strength > 0.005)
            println("BUY SIGNAL: $buy_signal")
        else
            println("❌ Some indicators are null - not enough data")
        end
    end
    
    debug_buy_logic_example()
    
    # Real usage would be:
    # debug_buy_logic(s, ai, ats) where s is your strategy instance
    
catch e
    @warn "PlanarInteractive not available: $e"
end

# Test on recent data
debug_buy_logic(s, first(s.universe.assets), ai.data.timestamp[end-5])
```

#### 3. Analyze Strategy Performance Issues

**Problem: No trades executed**
```julia
# Activate PlanarInteractive project
import Pkg
Pkg.activate("PlanarInteractive")

try
    using PlanarInteractive
    @environment!
    
    # Example: Check data sufficiency
    # Note: In real usage, 's' would be your loaded strategy instance
    
    println("Example data sufficiency check:")
    println("Data points: 150 (example)")
    println("Need at least 20 points for indicators")
    
    # Example logic for data checking
    data_points = 150  # This would be length(ai.data.timestamp) in real usage
    if data_points < 20
        println("❌ Not enough data - download more")
        # In real usage: fetch_ohlcv(s, from=-1000); load_ohlcv(s)
    else
        println("✅ Sufficient data for indicators")
    end
    
    # Real usage would be:
    # ai = first(s.universe.assets)
    # println("Data points: $(length(ai.data.timestamp))")
    # if length(ai.data.timestamp) < 20
    #     fetch_ohlcv(s, from=-1000)
    #     load_ohlcv(s)
    # end
    
catch e
    @warn "PlanarInteractive not available: $e"
end
```

**Problem: Too many trades (overtrading)**

**Problem: Poor performance**

### Performance Optimization Techniques

#### 1. Parameter Sensitivity Analysis

#### 2. Market Condition Analysis

## Step 12: Advanced Improvements

### Add Stop Loss


### Add Position Sizing


## Understanding Key Concepts

### Signal Validation
Always check if indicators return valid values:

### Timeframes
Indicators can use different [timeframes](../guides/data-management.md#timeframes):

### Strategy State
Use `s.attrs` to store strategy-specific data:


## See Also

- **[Quick Start](../getting-started/quick-start.md)** - 15-minute getting started tutorial
- **[Strategy Development](../guides/strategy-development.md)** - Complete strategy development guide
- **[Data Management](../guides/data-management.md)** - Working with market data

## Next Steps: From Beginner to Advanced

Congratulations! You've built your first custom Planar strategy from scratch. Here's your roadmap to becoming a sophisticated algorithmic trader:

### Immediate Improvements (Next 1-2 Hours)

#### 1. Optimize Your Current Strategy

#### 2. Test Different Assets

#### 3. Add Risk Management

### Short-term Learning (Next Week)

#### 1. **[Strategy Development Guide](../guides/strategy-development.md)**
Learn advanced patterns:
- Multi-timeframe analysis
- Portfolio strategies
- Advanced indicators
- Risk management systems

#### 2. **Parameter Optimization**
Systematic improvement:
- Grid search [optimization](../optimization.md)
- Genetic algorithms
- Walk-forward analysis
- Overfitting prevention

#### 3. **[Data Management](../data.md)**
Master Planar's data system:
- Multiple data sources
- Custom data feeds
- Data quality checks
- Historical [data management](../guides/data-management.md)

### Medium-term Goals (Next Month)

#### 1. **[Paper Trading](../engine/paper.md)**
Test with live data:
- Real-time market simulation
- Order book dynamics
- Slippage and fees
- Performance monitoring

#### 2. **Multi-Exchange Trading**
Scale your operations:
- Arbitrage opportunities
- Risk diversification
- Exchange-specific features
- Portfolio management

#### 3. **Custom Indicators**
Build proprietary signals:
- Custom [technical indicators](../guides/strategy-development.md#technical-indicators)
- Machine learning integration
- Alternative data sources
- Signal combination techniques

### Advanced Mastery (Next 3 Months)

#### 1. **[Live Trading](../engine/live.md)**
Deploy for real money:
- Risk management protocols
- Position sizing algorithms
- Emergency stop procedures
- Performance monitoring

#### 2. **Optimization at Scale**
Professional-grade optimization:
- Cloud computing integration
- Parallel backtesting
- Statistical significance testing
- Production deployment

#### 3. **Custom Exchange Integration**
Expand your reach:
- New exchange APIs
- Custom order types
- Specialized markets
- Institutional features

## Learning Resources by Experience Level

### 📚 Beginner Resources
- **[Strategy Examples](../strategy.md#examples)** - Study proven patterns
- **[Common Patterns](../common-patterns.md)** - Reusable strategy components
- **[Troubleshooting Guide](../troubleshooting/index.md)** - Solve common issues

### 🔬 Intermediate Resources
- **Advanced Indicators** - Technical analysis deep dive
- **[Backtesting Best Practices](../guides/strategy-development.md)** - Avoid common pitfalls
- **Performance Analysis** - Professional metrics

### 🚀 Advanced Resources
- **[API Reference](../reference/api/index.md)** - Complete function documentation
- **Architecture Guide** - Understand Planar internals
- **Contributing Guide** - Extend Planar itself

## Community and Support

- **[Discord Community](../contacts.md#discord)** - Get help from other traders
- **[GitHub Discussions](../contacts.md#github)** - Technical questions and feature requests
- **[Example Strategies Repository](../contacts.md#examples)** - Community-contributed strategies

## Your Strategy Development Checklist

Track your progress as you advance:

### ✅ Beginner Level (You are here!)
- [x] Built first custom strategy
- [x] Understand buy/sell logic
- [x] Can run backtests
- [x] Interpret basic performance metrics
- [ ] Optimize parameters manually
- [ ] Test multiple assets
- [ ] Add basic risk management

### 🎯 Intermediate Level
- [ ] Use systematic [parameter optimization](../optimization.md)
- [ ] Implement multi-timeframe strategies
- [ ] Deploy [paper trading](../guides/execution-modes.md#paper-mode)
- [ ] Build portfolio strategies
- [ ] Create custom indicators
- [ ] Understand statistical significance

### 🏆 Advanced Level
- [ ] Deploy live trading strategies
- [ ] Manage multiple exchange accounts
- [ ] Build machine learning models
- [ ] Contribute to Planar development
- [ ] Mentor other traders

**Ready for the next challenge?** Pick one immediate improvement and start coding! 🚀

## Best Practices

1. **Start Simple**: Begin with basic logic, add complexity gradually
2. **Test Thoroughly**: Use multiple time periods and market conditions
3. **Validate Everything**: Always check indicator values before using
4. **Log Decisions**: Use debug logging to understand strategy behavior
5. **Risk Management**: Always include stop losses and position sizing
6. **Backtest Extensively**: Test on different market conditions

## Common Patterns

### Multi-Timeframe Analysis

### Confirmation Signals

### Adaptive Parameters

You now have a solid foundation for building Planar strategies! The key is to start simple, test thoroughly, and iterate based on results. Happy trading! 🚀
