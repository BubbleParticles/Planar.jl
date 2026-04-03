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
            if !isdefined(Main, :DataFrame)
                @eval Main const DataFrame = Data.DataFrame
            end
            if !isdefined(Main, :OHLCV_COLUMNS)
                @eval Main const OHLCV_COLUMNS = Data.OHLCV_COLUMNS
            end
            if !isdefined(Main, :DataStructures)
                @eval Main const DataStructures = Data.DataStructures
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
            # Bind leverage helpers exported by Exchanges into Main
            try
                if !isdefined(Main, :LeverageTier)
                    @eval Main const LeverageTier = Exchanges.LeverageTier
                end
                if !isdefined(Main, :LeverageTiersDict)
                    @eval Main const LeverageTiersDict = Exchanges.LeverageTiersDict
                end
                if !isdefined(Main, :leverage_tiers)
                    @eval Main const leverage_tiers = Exchanges.leverage_tiers
                end
                if !isdefined(Main, :tier)
                    @eval Main const tier = Exchanges.tier
                end
            catch
            end
        catch
        end
        try
            using Watchers
            if !isdefined(Main, :Watchers)
                @eval Main const Watchers = Watchers
            end
            # Provide wa alias and WatchersImpls binding used by some modules/tests
            try
                # avoid setting wa as a const so tests can reassign it
                if !isdefined(Main, :wa)
                    @eval Main wa = Watchers
                end
                if !isdefined(Main, :WatchersImpls)
                    @eval Main const WatchersImpls = Watchers.WatchersImpls
                end
            catch
            end
        catch
        end
        try
            using Instruments
            if !isdefined(Main, :Instruments)
                @eval Main const Instruments = Instruments
            end
            if !isdefined(Main, :Derivative)
                @eval Main const Derivative = Instruments.Derivatives.Derivative
            end
        catch
        end
        try
            using Executors
            if !isdefined(Main, :Executors)
                @eval Main const Executors = Executors
            end
            # Some tests reference Executors as `ect`/`inst` or `Executors` aliases; provide common aliases in Main
            if !isdefined(Main, :ect)
                @eval Main const ect = Executors
            end
            if !isdefined(Main, :inst)
                # Instances module is usually re-exported as inst inside Executors. Provide inst alias to Executors.Instances
                @eval Main const inst = Executors.Instances
            end
            if !isdefined(Main, :Instances)
                @eval Main const Instances = Executors.Instances
            end
            if !isdefined(Main, :AssetInstance)
                @eval Main const AssetInstance = Executors.Instances.AssetInstance
            end
            if !isdefined(Main, :NoMargin)
                @eval Main const NoMargin = Executors.Instances.NoMargin
            end
            if !isdefined(Main, :committment)
                @eval Main const committment = Executors.committment
            end
            # Preload Strategies and alias 'st' used in many tests
            try
                using Strategies
                if !isdefined(Main, :Strategies)
                    @eval Main const Strategies = Strategies
                end
                if !isdefined(Main, :st)
                    @eval Main const st = Strategies
                end
                # Bind commonly used strategy types into Main to avoid world-age errors
                try
                    if !isdefined(Main, :Strategy)
                        @eval Main const Strategy = Strategies.Strategy
                    end
                    if !isdefined(Main, :MarginStrategy)
                        @eval Main const MarginStrategy = Strategies.MarginStrategy
                    end
                    if !isdefined(Main, :NoMarginStrategy)
                        @eval Main const NoMarginStrategy = Strategies.NoMarginStrategy
                    end
                    if !isdefined(Main, :SimStrategy)
                        @eval Main const SimStrategy = Strategies.SimStrategy
                    end
                    if !isdefined(Main, :PaperStrategy)
                        @eval Main const PaperStrategy = Strategies.PaperStrategy
                    end
                    if !isdefined(Main, :LiveStrategy)
                        @eval Main const LiveStrategy = Strategies.LiveStrategy
                    end
                    if !isdefined(Main, :PriceTime)
                        @eval Main const PriceTime = Strategies.PriceTime
                    end
                catch
                end
            catch
            end
            # Preload Misc and OrderTypes commonly referenced globals
            try
                using Misc
                if !isdefined(Main, :Misc)
                    @eval Main const Misc = Misc
                end
                if !isdefined(Main, :Long)
                    @eval Main const Long = Misc.Long
                end
                if !isdefined(Main, :Short)
                    @eval Main const Short = Misc.Short
                end
                if !isdefined(Main, :Isolated)
                    @eval Main const Isolated = Misc.Isolated
                end
                if !isdefined(Main, :Cross)
                    @eval Main const Cross = Misc.Cross
                end
                if !isdefined(Main, :CrossHedged)
                    @eval Main const CrossHedged = Misc.CrossHedged
                end
            catch
            end
            try
                using Instances
                if !isdefined(Main, :Instances)
                    @eval Main const Instances = Instances
                end
                if !isdefined(Main, :CCash)
                    @eval Main const CCash = Instances.CCash
                end
                if !isdefined(Main, :entryprice!)
                    @eval Main const entryprice! = Instances.entryprice!
                end
                if !isdefined(Main, :pnlpct)
                    @eval Main const pnlpct = Instances.pnlpct
                end
                if !isdefined(Main, :positions)
                    @eval Main const positions = Instances.positions
                end
                if !isdefined(Main, :AnyTrade)
                    @eval Main const AnyTrade = Instances.AnyTrade
                end
            catch
            end
            try
                using Collections
                if !isdefined(Main, :Collections)
                    @eval Main const Collections = Collections
                end
                if !isdefined(Main, :SortedDict)
                    @eval Main const SortedDict = Collections.SortedDict
                end
            catch
            end
            try
                using OrderTypes
                if !isdefined(Main, :OrderTypes)
                    @eval Main const OrderTypes = OrderTypes
                end
                if !isdefined(Main, :ot)
                    @eval Main const ot = OrderTypes
                end
            catch
            end
            # Preload Executors.Checks helpers like withfees
            try
                using Executors.Checks
                if !isdefined(Main, :withfees)
                    @eval Main const withfees = Executors.Checks.withfees
                end
                if !isdefined(Main, :cost)
                    @eval Main const cost = Executors.Checks.cost
                end
                # Also bind Instances helpers used by tests
                if !isdefined(Main, :amount_with_fees)
                    @eval Main const amount_with_fees = Executors.Instances.amount_with_fees
                end
                # Bind lower-level helpers from Executors that tests reference directly (e.g., basicorder)
                try
                    if !isdefined(Main, :basicorder)
                        @eval Main const basicorder = Executors.basicorder
                    end
                    if !isdefined(Main, :orders)
                        @eval Main const orders = Executors.orders
                    end
                    if !isdefined(Main, :buyorders)
                        @eval Main const buyorders = Executors.buyorders
                    end
                    if !isdefined(Main, :sellorders)
                        @eval Main const sellorders = Executors.sellorders
                    end
                    if !isdefined(Main, :hasorders)
                        @eval Main const hasorders = Executors.hasorders
                    end
                    if !isdefined(Main, :OrderIterator)
                        @eval Main const OrderIterator = Executors.OrderIterator
                    end
                    if !isdefined(Main, :unfillment)
                        @eval Main const unfillment = Executors.unfillment
                    end
                    if !isdefined(Main, :iscommittable)
                        @eval Main const iscommittable = Executors.iscommittable
                    end
                    if !isdefined(Main, :orderscount)
                        @eval Main const orderscount = Executors.orderscount
                    end
                    if !isdefined(Main, :hascash)
                        @eval Main const hascash = Executors.hascash
                    end
                    if !isdefined(Main, :cash!)
                        @eval Main const cash! = Executors.cash!
                    end
                    # Bind SanitizeOff from Executors.Checks
                    if !isdefined(Main, :SanitizeOff)
                        @eval Main const SanitizeOff = Executors.Checks.SanitizeOff
                    end
                    # Bind PriceTime from Strategies
                    if !isdefined(Main, :PriceTime)
                        @eval Main const PriceTime = Strategies.PriceTime
                    end
                    # Bind committment helper
                    if !isdefined(Main, :committment)
                        @eval Main const committment = Executors.committment
                    end
                    # Bind freecash and other Instance helpers
                    if !isdefined(Main, :freecash)
                        @eval Main const freecash = Executors.Instances.freecash
                    end
                    if !isdefined(Main, :committed)
                        @eval Main const committed = Executors.Instances.committed
                    end
                catch
                end
            catch
            end
            # Bind some Base helpers commonly used by tests
            try
                if !isdefined(Main, :negate)
                    @eval Main const negate = Base.negate
                end
            catch
            end
            try
                using Lang
                if !isdefined(Main, :Lang)
                    @eval Main const Lang = Lang
                end
            catch
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
            invokelatest(f)
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
