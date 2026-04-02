# All the packages added in the test/Project.toml go here (before the NO_TMP switch)
using Aqua
using Test

include("env.jl")

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
    :session_attributes,
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

    # Preload commonly used modules and bindings into Main to reduce world-age warnings.
    @eval begin
        try
            using Collections
            if !isdefined(Main, :AssetCollection)
                @eval Main const AssetCollection = Collections.AssetCollection
            end
        catch
        end
        try
            using Data
            if !isdefined(Main, :Data)
                @eval Main const Data = Data
            end
        catch
        end
        try
            using Processing
            if !isdefined(Main, :Processing)
                @eval Main const Processing = Processing
            end
        catch
        end
        try
            using ExchangeTypes
            if !isdefined(Main, :ExchangeTypes)
                @eval Main const ExchangeTypes = ExchangeTypes
            end
        catch
        end
        try
            using Exchanges
            if !isdefined(Main, :Exchanges)
                @eval Main const Exchanges = Exchanges
            end
        catch
        end
        try
            using Watchers
            if !isdefined(Main, :Watchers)
                @eval Main const Watchers = Watchers
            end
        catch
        end
        try
            using Instruments
            if !isdefined(Main, :Instruments)
                @eval Main const Instruments = Instruments
            end
        catch
        end
    end

    # Predefine placeholder test functions to avoid world-age warnings when tests are referenced before being defined
    for testname in all_tests
        name = Symbol(:test_, testname)
        if !isdefined(@__MODULE__, name)
            @eval begin
                function $(name)()
                    nothing
                end
            end
        end
    end
    for testname in all_tests
        if test_all || lowercase(string(testname)) ∈ selected
            name = Symbol(:test_, testname)
            file_name = joinpath(PROJECT_PATH, "test", string(name, ".jl"))
            if file_name ∉ _INCLUDED_TEST_FILES
                push!(_INCLUDED_TEST_FILES, file_name)
                (isdefined(Main, :Revise) ? includet : include)(file_name)
            end
            f = getproperty(@__MODULE__, name)
            # Use invokelatest to call test functions to avoid Julia world-age issues when globals are defined during test loading
            invokelatest(f)
            # After each test, ensure we clean up Exchange resources and watchers to avoid aiohttp leaks
            try
                if isdefined(Main, :PlanarDev) && isdefined(PlanarDev, :Planar)
                    try
                        PlanarDev.Planar.Engine.@eval begin
                            try
                                if isdefined(@__MODULE__, :Watchers)
                                    @eval Watchers._closeall()
                                end
                            catch
                            end
                            try
                                if isdefined(@__MODULE__, :ExchangeTypes)
                                    @eval ExchangeTypes._closeall()
                                end
                            catch
                            end
                        end
                    catch
                    end
                end
            catch
            end
        end
    end
end

if !isinteractive()
    tests()
end
