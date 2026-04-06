# All the packages added in the test/Project.toml go here (before the NO_TMP switch)
using Aqua
using Test

include("env.jl")
ENV["PLANAR_NO_OPTENV"] = "1"

all_tests = [
    :aqua,
    :time,
    :data,
    :processing,
    #
    :derivatives,
    :exchanges,
    :markets,
    #
    :collections,
    :orders,
    :orders2,
    :positions,
    :instances,
    :strategies,
    # session attributes rely on Opt and external stubs; skip in CI when PLANAR_NO_OPTENV is set
    # :session_attributes,
    #
    :ohlcv,
    :tradesohlcv,
    :watchers,
    :average_ohlcv_watcher,
    #
    :profits,
    :roi,
    :stoploss,
    #
    :coinmarketcap,
    :coinpaprika,
    :coingecko,
    :frankfurter,
    :fred,
    :fred_comprehensive,
    :fred_performance,
    :fred_parameters,
    :fred_integration,
    :funding,
    #
    :backtest,
    :paper,
    :live,
    :live_call,
    :dbnomics,
    :dbnomics_api,
    #
    :warmup,
]

tests(selected=ARGS) = begin
    selected = string.(selected)
    test_all = "all" ∈ selected || length(selected) == 0
    for testname in all_tests
        if test_all || lowercase(string(testname)) ∈ selected
            name = Symbol(:test_, testname)
            file_name = joinpath(PROJECT_PATH, "test", string(name, ".jl"))
            if file_name ∉ _INCLUDED_TEST_FILES
                push!(_INCLUDED_TEST_FILES, file_name)
                # Include the test file into Main so `using` statements inside test files are at top-level.
                Base.include(Main, file_name)
            end
            f = Base.invokelatest(getproperty, Main, name)
            Base.invokelatest(f)
            # After each test, ensure we clean up Exchange resources and watchers to avoid aiohttp leaks
            try
                if isdefined(Main, :ExchangeTypes)
                    try
                        ExchangeTypes._closeall()
                    catch
                    end
                    try
                        ExchangeTypes._drain_finalizer_queue()
                    catch
                    end
                end
                if isdefined(Main, :Watchers)
                    try
                        Watchers._closeall()
                    catch
                    end
                end
                # Run garbage collection and short sleep to allow Python tasks to finalize
                try
                    GC.gc()
                    sleep(0.05)
                catch
                end
            catch
            end
        end
    end
end

if !isinteractive()
    tests()
end
