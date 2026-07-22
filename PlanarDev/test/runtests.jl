# All the packages added in the test/Project.toml go here (before the NO_TMP switch)
using Aqua
using Test
include("env.jl")
ENV["PLANAR_NO_OPTENV"] = "1"

const GATEWAY_TESTS = Set{Symbol}([
    :exchanges, :markets, :collections, :orders, :orders2,
    :positions, :instances, :strategies,
    :ohlcv, :tradesohlcv, :watchers, :watcher_verification,
    :profits, :roi, :stoploss,
    :funding, :backtest, :paper, :warmup,
])
const GATEWAY_AVAILABLE = isfile("/tmp/ccxt_gateway.pid")
if !GATEWAY_AVAILABLE
    @warn "CcxtGateway not available (no pidfile at /tmp/ccxt_gateway.pid). Gateway-requiring tests will be skipped."
end
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
    #
    :ohlcv,
    :tradesohlcv,
    :watchers,
    :watcher_verification,
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
    :funding,
    #
    :backtest,
    :paper,
    :dbnomics,
    #
    :warmup,
]

tests(selected=ARGS) = begin
    selected = string.(selected)
    test_all = "all" ∈ selected || length(selected) == 0
    for testname in all_tests
        if test_all || lowercase(string(testname)) ∈ selected
            if testname in GATEWAY_TESTS && !GATEWAY_AVAILABLE
                @warn "Skipping test $(testname): gateway unavailable (port 8999)"
                continue
            end
            name = Symbol(:test_, testname)
            file_name = joinpath(PROJECT_PATH, "test", string(name, ".jl"))
            if file_name ∉ _INCLUDED_TEST_FILES
                push!(_INCLUDED_TEST_FILES, file_name)
                Base.include(Main, file_name)
            end
            f = Base.invokelatest(getproperty, Main, name)
            try
                Base.invokelatest(f)
            catch e
                if occursin("connection refused", sprint(showerror, e))
                    @warn "Skipping test $(testname): gateway unavailable"
                    continue
                end
                rethrow(e)
            end
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
