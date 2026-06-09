module Runtests

using Test

using SimMode

const OT = SimMode.OrderTypes
const Order = OT.Order
const EID = OT.ExchangeTypes.ExchangeID
const DateTime = SimMode.DateTime
const Buy = SimMode.Buy
const Sell = SimMode.Sell

_asset = SimMode.Asset("BTC/USDT")
_eid = EID(:test)
_dt = DateTime(2024, 1, 1)

# ---- helpers ----
_market_buy(; p=100.0, a=1.0) = Order(_asset, _eid, Order{OT.MarketOrderType{Buy}}; price=p, amount=a, date=_dt)
_market_sell(; p=100.0, a=1.0) = Order(_asset, _eid, Order{OT.MarketOrderType{Sell}}; price=p, amount=a, date=_dt)
_limit_buy(; p=100.0, a=1.0) = Order(_asset, _eid, Order{OT.LimitOrderType{Buy}}; price=p, amount=a, date=_dt)
_limit_sell(; p=100.0, a=1.0) = Order(_asset, _eid, Order{OT.LimitOrderType{Sell}}; price=p, amount=a, date=_dt)

@testset "SimMode" begin

@testset "volumeskew (slippage.jl)" begin
    @test SimMode._volumeskew(10.0, 100.0) == 0.1
    @test SimMode._volumeskew(200.0, 100.0) == 1.0
    @test SimMode._volumeskew(10.0, 0.0) == 1.0
    @test SimMode._volumeskew(0.0, 100.0) == 0.0
end

@testset "addslippage (slippage.jl)" begin
    # limit buy: price - slp
    @test SimMode._addslippage(_limit_buy(), 100.0, 5.0) == 95.0
    @test SimMode._addslippage(_limit_buy(), 50.0, 0.0) == 50.0
    @test SimMode._addslippage(_limit_buy(), 100.0, 10.5) ≈ 89.5
    # limit sell: price + slp
    @test SimMode._addslippage(_limit_sell(), 100.0, 5.0) == 105.0
    @test SimMode._addslippage(_limit_sell(), 50.0, 0.0) == 50.0
    @test SimMode._addslippage(_limit_sell(), 100.0, 10.5) ≈ 110.5
    # market buy: price + slp
    @test SimMode._addslippage(_market_buy(), 100.0, 5.0) == 105.0
    @test SimMode._addslippage(_market_buy(), 50.0, 0.0) == 50.0
    # market sell: price - slp
    @test SimMode._addslippage(_market_sell(), 100.0, 5.0) == 95.0
    @test SimMode._addslippage(_market_sell(), 50.0, 0.0) == 50.0
end

@testset "spreadopt (slippage.jl)" begin
    @test SimMode.spreadopt(0.05, nothing, nothing) == 0.05
    @test SimMode.spreadopt(1.5, nothing, nothing) == 1.5
    @test SimMode.spreadopt(0.0, nothing, nothing) == 0.0
    @test_throws ErrorException SimMode.spreadopt("bad", nothing, nothing)
    @test_throws ErrorException SimMode.spreadopt(:symbol, nothing, nothing)
end

@testset "construct_order_func (orders/utils.jl)" begin
    @test SimMode.construct_order_func(Order{OT.LimitOrderType{Buy}}) === SimMode.create_sim_limit_order
    @test SimMode.construct_order_func(Order{OT.MarketOrderType{Sell}}) === SimMode.create_sim_market_order
    @test SimMode.construct_order_func(OT.LimitOrderType{Buy}) === SimMode.create_sim_limit_order
    @test SimMode.construct_order_func(OT.MarketOrderType{Sell}) === SimMode.create_sim_market_order
    @test SimMode.construct_order_func(Int) === SimMode.create_sim_limit_order
end

@testset "doclamp market (slippage.jl)" begin
    # _doclamp for market orders ignores ai/date → just returns price
    @test SimMode._doclamp(_market_buy(), 100.0, nothing, _dt) == 100.0
    @test SimMode._doclamp(_market_sell(), 50.0, nothing, _dt) == 50.0
end

@testset "lev_value (positions/call.jl)" begin
    @test SimMode._lev_value(42) == 42
    @test SimMode._lev_value(0.0) == 0.0
    @test SimMode._lev_value(() -> 3.0) == 3.0
end

@testset "fill_happened (orders/limit.jl)" begin
    # ratio > 100 → always filled, full amount
    filled, amt = SimMode._fill_happened(1.0, 200.0)
    @test filled == true
    @test amt == 1.0

    # ratio between 10 and 100 → rand() < log10(ratio)
    # log10(500/10) = log10(50) ≈ 1.699 → always true
    filled2, amt2 = SimMode._fill_happened(10.0, 500.0)
    @test filled2 == true
    @test amt2 == 10.0

    # ratio <= 10 → recursive reduction until amount exhausted
    filled3, amt3 = SimMode._fill_happened(10.0, 5.0)
    @test filled3 == false
    @test amt3 == 0.0

    # amount = 0 → Inf ratio, always filled
    filled4, amt4 = SimMode._fill_happened(0.0, 100.0)
    @test filled4 == true
    @test amt4 == 0.0

    # max_depth = 1 → immediate fail for ratio <= 10
    filled5, amt5 = SimMode._fill_happened(10.0, 5.0; max_depth=1)
    @test filled5 == false
    @test amt5 == 0.0

    # reduction exhausts amount before max_depth → hits inner else branch (line 122)
    # amount=5, cdl_vol=1, max_reduction=0.5 → reduced=2.5, threshold=2.5, not > → false
    filled6, amt6 = SimMode._fill_happened(5.0, 1.0; max_reduction=0.5)
    @test filled6 == false
    @test amt6 == 0.0
end

@testset "backtest types (backtest.jl)" begin
    @test isdefined(SimMode, :StatsColumn)
end

end  # @testset SimMode

end  # module Runtests
