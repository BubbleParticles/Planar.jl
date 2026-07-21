# Test helper for creating mock AssetInstance and Strategy objects.
#
# Usage:
#   include("test_helpers.jl")
#   ai = make_assetinstance("BTC/USDT", 50000.0)
#   strategy = make_strategy([ai])
#
# Requires the following packages to be available in the test environment:
#   Instances (via Metrics.Instances)
#   ExchangeTypes, ExchangeTypes (for mock exchange)
#   Data, TimeTicks, Lang, Misc
#   Collections (for AssetCollection)
#   DataFrames, DataStructures (for SortedDict)
#   OrderTypes (for Trade)

using Test
using Metrics
using Metrics.Instances: AssetInstance, NoMarginInstance, ohlcv
using Metrics.Instances.Instruments: AbstractAsset, parse, raw, cash!
using Metrics.Instances.Misc: NoMargin, Sim, Config
using Metrics.Instances.Exchanges.ExchangeTypes: CcxtExchange, ExchangeID, ExcPrecisionMode
using Metrics.Instances.Exchanges.ExchangeTypes.OrderedCollections: OrderedSet
using Metrics.ect.TimeTicks: TimeFrame, DateTime, TimeTicks, Minute, Second, Millisecond
using Metrics.st.Data.DataFrames: DataFrame
using Metrics.st.Data.DataStructures: SortedDict
using Metrics.st.Data: DFUtils
using Collections: AssetCollection

function make_exchange(name::Symbol=:test)
    id = ExchangeID{name}()
    CcxtExchange{typeof(id)}(
        id, string(name), "", OrderedSet{String}(["1m"]),
        Dict{String,Dict{String,Any}}(
            "BTC/USDT" => Dict{String,Any}(
                "id" => "BTC/USDT", "base" => "BTC", "quote" => "USDT",
                "type" => "swap", "active" => true, "swap" => true, "linear" => true,
                "precision" => Dict{String,Any}("amount" => 8, "price" => 2),
                "limits" => Dict{String,Any}(
                    "amount" => Dict{String,Any}("min" => 1e-6, "max" => 1e8),
                    "price" => Dict{String,Any}("min" => 0.01, "max" => 1e6),
                    "cost" => Dict{String,Any}("min" => 1.0, "max" => 1e8),
                ),
                "taker" => 0.001, "maker" => 0.001,
            ),
            "ETH/USDT" => Dict{String,Any}(
                "id" => "ETH/USDT", "base" => "ETH", "quote" => "USDT",
                "type" => "swap", "active" => true, "swap" => true, "linear" => true,
                "precision" => Dict{String,Any}("amount" => 8, "price" => 2),
                "limits" => Dict{String,Any}(
                    "amount" => Dict{String,Any}("min" => 1e-6, "max" => 1e8),
                    "price" => Dict{String,Any}("min" => 0.01, "max" => 1e6),
                    "cost" => Dict{String,Any}("min" => 1.0, "max" => 1e8),
                ),
                "taker" => 0.001, "maker" => 0.001,
            ),
        ),
        Set{Symbol}([:swap]), Dict{Symbol,Any}(:taker => 0.001, :maker => 0.001),
        Dict{Symbol,Any}(:fetchTicker => true, :fetchOHLCV => true),
        ExcPrecisionMode(2), nothing, [:fetchTicker, :fetchOHLCV], Dict{String,Any}(),
    )
end

const mock_exchange = make_exchange()

function make_ohlcv(price, n=10)
    start_dt = DateTime(2024, 1, 1, 0, 0, 0)
    DataFrame(
        timestamp = [start_dt + Minute(i) for i in 0:n-1],
        open = [price + randn()*0.1 for _ in 1:n],
        high = [price + 0.1 + randn()*0.1 for _ in 1:n],
        low = [price - 0.1 + randn()*0.1 for _ in 1:n],
        close = [price + randn()*0.1 for _ in 1:n],
        volume = [1000.0 for _ in 1:n],
    )
end

# Creates a minimal AssetInstance with OHLCV data and optional trades.
# Trades require Order/Trade objects from OrderTypes, see OrderTypes/test/ for examples.
function make_assetinstance(
    symbol="BTC/USDT"; price=50000.0, timeframe=TimeFrame("1m"), n_ohlcv=10
)
    a = parse(AbstractAsset, symbol)
    data = SortedDict(timeframe => make_ohlcv(price, n_ohlcv))
    AssetInstance(
        a, data, mock_exchange, NoMargin();
        limits=(; leverage=(; min=1.0, max=100.0), amount=(; min=1e-6, max=1e8),
                price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8)),
        precision=(; amount=8, price=2),
        fees=(; taker=0.001, maker=0.001, min=0.001, max=0.001),
    )
end

# Creates a minimal Strategy with mock AssetInstance objects in universe.
function make_strategy(assets=nothing; cash=10000.0, tf=TimeFrame("1m"))
    if assets === nothing
        assets = [make_assetinstance("BTC/USDT")]
    end
    uni = AssetCollection(assets)
    cfg = Config(; qc=:USDT, initial_cash=cash, sandbox=true)
    # Note: Strategy construction requires a module with @interface
    # Use the Stubs.StubStrategy pattern or define a minimal module:
    # module MockStrategy; Strategies.@interface; end
    error("Strategy construction needs a module with @interface. " *
          "See Stubs.StubStrategy or define a minimal one in test.")
end

# Example test block (uncomment and run when dependencies are available):
# @testset "AssetInstance mock" begin
#     ai = make_assetinstance("BTC/USDT")
#     @test ai isa AssetInstance
#     @test length(ai.data) == 1
#     @test :close in names(first(values(ai.data)))
#
#     # Empty history tests
#     @test isempty(ai.history)
#     # Uncomment when Metrics functions are imported:
#     # @test Metrics.trades_duration(ai; tf=TimeFrame("1m")) == Millisecond(0)
#     # @test isempty(Metrics.trades_size(ai))
#     # @test isempty(Metrics.trades_leverage(ai))
# end
