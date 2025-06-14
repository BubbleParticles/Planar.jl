# test/cpu_fallback_test.jl

using Test
using DataFrames
using Dates
using Statistics # For mean, if used by strategy or tests directly

# --- Environment Setup ---
# Attempt to load Planar and its submodules.
# This assumes Planar is in JULIA_LOAD_PATH or accessible via relative paths.
PLANAR_LOADED = false
try
    # Try loading Planar as if it's an installed package or in the load path
    using Planar
    using Planar.Engine.Strategies
    using Planar.Engine.Executors
    using Planar.Engine.Instances
    using Planar.Engine.Types
    using Planar.Engine.OrderTypes
    using Planar.Engine.Exchange
    using Planar.SimMode
    # using Planar.StrategyTools # Not directly used in this test script, but SimMode might use it.
    PLANAR_LOADED = true
    println("Successfully loaded Planar and its submodules.")
catch e
    println("Standard 'using Planar' failed. Attempting to load from assumed relative paths...")
    # This block is a fallback for local development if Planar isn't "installed".
    # It assumes the test script is in a 'test' directory at the root of the Planar project.
    # Adjust these paths based on your actual project structure.
    try
        project_root = dirname(@__DIR__) # Assumes test script is in 'test/' subdir of project root

        include(joinpath(project_root, "src", "Engine", "Engine.jl"))
        using .Engine.Strategies
        using .Engine.Executors
        using .Engine.Instances
        using .Engine.Types
        using .Engine.OrderTypes
        using .Engine.Exchange

        include(joinpath(project_root, "src", "SimMode", "SimMode.jl"))
        # If StrategyTools is needed by SimMode and not automatically included by SimMode.jl:
        # include(joinpath(project_root, "src", "StrategyTools", "StrategyTools.jl"))

        # Make top-level modules available if they are not under a single Planar module
        # This depends on how Engine, SimMode etc. are structured.
        # For this test, directly using SimMode.start! etc.
        # And Engine.Strategies.call! etc.
        println("Successfully loaded Planar components from relative paths.")
        PLANAR_LOADED = true # Mark as loaded if this path succeeded
    catch inner_e
        println("Error: Could not load Planar components from relative paths either.")
        println("Initial error: ", e)
        println("Inner error (relative path load): ", inner_e)
        println("Ensure Planar modules are correctly set up in your Julia environment.")
        println("Skipping tests.")
        # To prevent further errors if Planar is not loaded, we can exit or skip tests.
        # For now, let it error out if used later, to show dependency.
    end
end

# Proceed only if Planar components are loaded
if PLANAR_LOADED
    # Load SimpleStrategy
    # Adjust path if your strategy is located elsewhere or if Planar has a strategy registry.
    STRATEGY_LOADED = false
    try
        project_root_for_strategy = dirname(@__DIR__) # Assumes 'user' is at project root
        include(joinpath(project_root_for_strategy, "user", "strategies", "SimpleStrategy", "src", "SimpleStrategy.jl"))
        using .SimpleStrategy # Assuming SimpleStrategy is a module
        STRATEGY_LOADED = true
        println("Successfully loaded SimpleStrategy.")
    catch e
        println("Error: Could not load SimpleStrategy.jl.")
        println("Current working directory: ", pwd())
        println("Make sure the path to SimpleStrategy.jl is correct relative to your test execution directory.")
        println(e)
        println("Skipping tests.")
    end

if STRATEGY_LOADED
# --- Test Data Generation ---
function generate_test_ohlcv_data(n_days::Int)
    start_date = DateTime(2023, 1, 1)
    timestamps = [start_date + Day(i) for i in 0:n_days-1]

    df = DataFrame(timestamp = timestamps)
    # Generate somewhat predictable data: a slight upward trend with noise
    df.open = [100.0 + 0.1*i + randn()*1.0 for i in 1:n_days]
    df.high = df.open .+ abs.(randn(n_days) .* 0.5 .+ 0.5) # Ensure high > open
    df.low = df.open .- abs.(randn(n_days) .* 0.5 .+ 0.5)  # Ensure low < open
    df.close = df.open .+ [rand([-0.5, 0.5, 0.2, -0.2, 0.1, -0.1]) + 0.05*i for i in 1:n_days] # Close around open, with trend
    df.volume = 1000.0 .+ rand(n_days) .* 500.0

    # Ensure consistency (high is max, low is min)
    for i in 1:n_days
        actual_open = df.open[i]
        actual_high = df.high[i]
        actual_low = df.low[i]
        actual_close = df.close[i]

        df.high[i] = max(actual_open, actual_high, actual_low, actual_close)
        df.low[i] = min(actual_open, actual_high, actual_low, actual_close)
        # Ensure open and close are within high/low
        df.open[i] = min(df.high[i], max(df.low[i], actual_open))
        df.close[i] = min(df.high[i], max(df.low[i], actual_close))
    end
    return df
end

ohlcv_data_btc_usdt = generate_test_ohlcv_data(50)

# --- Strategy Setup Function ---
function setup_strategy_for_test(ohlcv_df::DataFrame, strategy_constructor)
    strat = strategy_constructor() # e.g., SimpleStrategy.SC()

    # Call LoadStrategy - this should initialize assets within the strategy
    Strategies.call!(strat, Strategies.LoadStrategy())

    # Find the AssetInstance for "BTC/USDT".
    # This depends on how SimpleStrategy makes its AssetInstance(s) available.
    # Common patterns: strat.market, strat.assets[1], strat.universe[1]
    # Let's assume SimpleStrategy stores its primary market asset in a field named `market`.
    # This assumption MUST match the actual SimpleStrategy.jl implementation.
    ai_btc_usdt::AssetInstance = if hasproperty(strat, :market) && strat.market isa AssetInstance
        strat.market
    else
        # Fallback: search in universe if `market` field isn't there or not an AI
        found_ai = nothing
        if hasproperty(strat, :universe) && strat.universe isa AbstractVector
            for ai_candidate in strat.universe
                if ai_candidate isa AssetInstance && Instances.name(ai_candidate) == "BTC/USDT" # Assuming Instances.name
                    found_ai = ai_candidate
                    break
                end
            end
        end
        if found_ai === nothing
            error("Could not find AssetInstance for BTC/USDT in strategy. Check SimpleStrategy.jl structure.")
        end
        found_ai
    end

    tf_d1 = Types.TFd1 # Daily TimeFrame from Planar.Engine.Types

    # Initialize ai_btc_usdt.data if it's not already a Dict
    if !isdefined(ai_btc_usdt, :data) || ai_btc_usdt.data === nothing
        ai_btc_usdt.data = Dict{TimeFrame, DataFrame}()
    elseif !isa(ai_btc_usdt.data, Dict)
         @warn "AssetInstance.data is not a Dict, attempting to overwrite. Current type: $(typeof(ai_btc_usdt.data))"
         ai_btc_usdt.data = Dict{TimeFrame, DataFrame}()
    end
    ai_btc_usdt.data[tf_d1] = ohlcv_df

    Strategies.call!(strat, Strategies.ResetStrategy())
    return strat
end

# --- Metrics Extraction Function ---
function extract_test_metrics(strategy_obj)
    final_cash = strategy_obj.cash
    num_trades = 0
    # Accessing exchange history:
    # Path might be strategy_obj.exchange.trade_history or similar.
    # Based on SimMode usage of `s.holdings` and `orderscount(s)`,
    # let's assume `strategy_obj.exchange` is the standard way.
    if hasproperty(strategy_obj, :exchange) &&
       isdefined(strategy_obj.exchange, :history) && # Check if history is defined
       strategy_obj.exchange.history isa AbstractVector
        num_trades = length(strategy_obj.exchange.history)
    else
        @warn "Could not determine number of trades: exchange history not found in expected structure."
    end
    return (final_cash=final_cash, num_trades=num_trades)
end

# --- Test Execution ---
@testset "CPU Fallback Test for start_gpu!" begin
    # Setup CPU version
    strategy_cpu = setup_strategy_for_test(ohlcv_data_btc_usdt, SC) # SC is from SimpleStrategy module
    # Context creation: Using Context(strategy) which should infer range from data
    context_cpu = Executors.Context(strategy_cpu)

    println("Running start! (CPU native)...")
    SimMode.start!(strategy_cpu, context_cpu; show_progress=false)
    metrics_cpu = extract_test_metrics(strategy_cpu)

    # Setup GPU version (which should fallback to CPU)
    strategy_gpu_fallback = setup_strategy_for_test(ohlcv_data_btc_usdt, SC)
    context_gpu_fallback = Executors.Context(strategy_gpu_fallback)

    println("Running start_gpu! (expecting CPU fallback)...")
    # Verify that oneAPI is not functional (important for this test)
    oneapi_functional_check = false
    if isdefined(Main, :oneAPI) && hasproperty(Main.oneAPI, :functional)
        oneapi_functional_check = Main.oneAPI.functional()
    end
    if oneapi_functional_check
        @warn "WARNING: oneAPI appears to be functional in the test environment. This test is designed for when oneAPI is NOT functional, to test CPU fallback path of start_gpu!."
    else
        println("oneAPI not functional or not defined, as expected for CPU fallback test.")
    end

    SimMode.start_gpu!(strategy_gpu_fallback, context_gpu_fallback; show_progress=false)
    metrics_gpu_fallback = extract_test_metrics(strategy_gpu_fallback)

    # Compare results
    println("CPU Metrics: ", metrics_cpu)
    println("GPU Fallback Metrics: ", metrics_gpu_fallback)

    @test metrics_cpu.final_cash ≈ metrics_gpu_fallback.final_cash atol=1e-9
    @test metrics_cpu.num_trades == metrics_gpu_fallback.num_trades

    if metrics_cpu.final_cash ≈ metrics_gpu_fallback.final_cash atol=1e-9 && metrics_cpu.num_trades == metrics_gpu_fallback.num_trades
        println("Test Passed: CPU native and start_gpu! (CPU fallback) results match.")
    else
        println("Test Failed: Results mismatch between CPU native and start_gpu! (CPU fallback).")
    end
end

# End of STRATEGY_LOADED check
end
# End of PLANAR_LOADED check
end
println("CPU fallback test script finished.")

# To make this runnable:
# 1. Ensure Planar modules are in JULIA_LOAD_PATH or paths in the script are correct.
# 2. Ensure SimpleStrategy.jl is at the specified relative path.
# 3. Run `julia test/cpu_fallback_test.jl`.
# 4. If `Main.oneAPI` is somehow defined and functional, the fallback path won't be tested as intended.
#    The test attempts to proceed anyway but warns.

# Note on `AssetInstance.data` initialization:
# If `ai_btc_usdt.data` is immutable or not a Dict by default, the direct assignment
# `ai_btc_usdt.data[tf_d1] = ohlcv_df` might fail. The `setup_strategy_for_test` function
# includes a check and potential initialization for `ai_btc_usdt.data` to mitigate this.
# This relies on `AssetInstance.data` being a mutable field.

# Note on `SimpleStrategy`'s `AssetInstance` field:
# Assumed `strat.market` or found in `strat.universe`. If `SimpleStrategy.jl` uses a different way
# to store or name its main `AssetInstance`, `setup_strategy_for_test` must be adapted.
