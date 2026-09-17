using Test
using PlanarCore
using PlanarCore.Misc: Sim, Paper, Live, Isolated, IsolatedHedged, Cross, CrossHedged, NoMargin, DFT, Hedged, MarginMode
using PlanarCore.Strategies: Strategy
using PlanarCore.Strategies.Instances: ishedged, isopen, Long, Short, position, freecash, cash, committed
using PlanarCore.Instances: InstrumentInstance, cash!
using PlanarCore.Instances.Instruments.Derivatives: Derivative
using PlanarCore.ExchangeTypes: CcxtExchange, ExchangeID, ExcPrecisionMode
using PlanarCore.ExchangeTypes.OrderedCollections: OrderedSet
using PlanarCore.Collections: InstrumentCollection
using PlanarCore.TimeTicks: TimeFrame
using PlanarCore.Exchanges: _TIER_CACHES, LeverageTier, marginmode!
using PlanarCore.Instances.Data: DataFrame
using PlanarCore.Instances.DataStructures: SortedDict
using PlanarCore.OrderTypes: Buy, Sell, BuyOrder, SellOrder, ShortBuyOrder
using PlanarCore.Executors: iscommittable, leverage, leverage!
using PlanarCore.Executors: UpdateLeverage
using PlanarCore.Strategies: call!
using PlanarCore.Misc: Config
using Dates: DateTime, Minute

include(joinpath(dirname(pathof(PlanarCore)), "..", "test", "test_margin_matrix.jl"))

@testset "leverage! setter is tier-bounded (BUG-1)" begin
    exc = _make_exchange_matrix(:lev_bound_test)
    tier = LeverageTier(Dict("tier"=>1,"notionalFloor"=>0.0,"notionalCap"=>1e6,"maxLeverage"=>10.0,"maintenanceMarginRate"=>0.01,"maintAmtNotional"=>0.0,"minNotional"=>0.0))
    _TIER_CACHES[(:lev_bound_test, "BTC/USDT:USDT")] = ([tier], time())
    ii = _make_instance_matrix(Isolated(), exc)
    # An out-of-tier leverage value must be clamped to the exchange tier max (10.0).
    leverage!(ii, 100.0, Long())
    @test leverage(ii, Long()) == 10.0
    leverage!(ii, 50.0, Long())
    @test leverage(ii, Long()) == 10.0
    # A value within tier is accepted unchanged.
    leverage!(ii, 5.0, Long())
    @test leverage(ii, Long()) == 5.0
    # Below the minimum (1.0) is clamped up.
    leverage!(ii, 0.0, Long())
    @test leverage(ii, Long()) == 1.0
end

@testset "UpdateLeverage call! is tier-bounded in Sim" begin
    exc = _make_exchange_matrix(:lev_call_test)
    tier = LeverageTier(Dict("tier"=>1,"notionalFloor"=>0.0,"notionalCap"=>1e6,"maxLeverage"=>10.0,"maintenanceMarginRate"=>0.01,"maintAmtNotional"=>0.0,"minNotional"=>0.0))
    _TIER_CACHES[(:lev_call_test, "BTC/USDT:USDT")] = ([tier], time())
    ii = _make_instance_matrix(Isolated(), exc)
    cfg = Config(; qc=:USDT, initial_cash=100000.0)
    s = Strategy(Main, Sim(), Isolated(), TimeFrame("1m"), exc, InstrumentCollection(["BTC/USDT:USDT"]; exc=exc, margin=Isolated(), load_data=false); config=cfg)
    # UpdateLeverage with an out-of-tier value must clamp to tier max.
    call!(s, ii, 100.0, UpdateLeverage(); pos=Long())
    @test leverage(ii, Long()) == 10.0
    # Within-tier value is accepted.
    call!(s, ii, 5.0, UpdateLeverage(); pos=Long())
    @test leverage(ii, Long()) == 5.0
end

@testset "UpdateLeverage call! is tier-bounded in Paper" begin
    exc = _make_exchange_matrix(:lev_paper_test)
    tier = LeverageTier(Dict("tier"=>1,"notionalFloor"=>0.0,"notionalCap"=>1e6,"maxLeverage"=>10.0,"maintenanceMarginRate"=>0.01,"maintAmtNotional"=>0.0,"minNotional"=>0.0))
    _TIER_CACHES[(:lev_paper_test, "BTC/USDT:USDT")] = ([tier], time())
    ii = _make_instance_matrix(Isolated(), exc)
    cfg = Config(; qc=:USDT, initial_cash=100000.0)
    s = Strategy(Main, Paper(), Isolated(), TimeFrame("1m"), exc, InstrumentCollection(["BTC/USDT:USDT"]; exc=exc, margin=Isolated(), load_data=false); config=cfg)
    call!(s, ii, 100.0, UpdateLeverage(); pos=Long())
    @test leverage(ii, Long()) == 10.0
    call!(s, ii, 5.0, UpdateLeverage(); pos=Long())
    @test leverage(ii, Long()) == 5.0
end