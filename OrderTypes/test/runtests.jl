using OrderTypes
using Test
const Instruments = OrderTypes.Instruments
const Dates = Instruments.Misc.TimeTicks.Dates
using .Instruments: Asset, AbstractAsset, @a_str
using OrderTypes: ExchangeID, Exchange, ExchangeEvent, AssetEvent, StrategyEvent
using OrderTypes: Trade, orderside, positionside, pricetime
using OrderTypes: signedamount, signedsize, isliquidation, sidetopos
using OrderTypes: ByPos, BySide, ReduceOnlyOrder
using OrderTypes:
    MarketOrderType, LimitOrderType, GTCOrderType, PostOnlyOrderType,
    ImmediateOrderType, FOKOrderType, IOCOrderType,
    LiquidationType, ForcedOrderType
using OrderTypes: signedamount, signedsize, isliquidation, sidetopos
using OrderTypes: postoside, fees as order_fees
using OrderTypes: Long, Short, ordertype, exchangeid
using Base: hash

date = Dates.now()
asset = a"BTC/USDT"
eid = ExchangeID(:test_exchange)

function make_order(; T=MarketOrderType{Buy}, P=OrderTypes.Long, price=50000.0, amt=1.0, dt=date, id="", tag="", attrs=(;), kwargs...)
    Order(asset, eid, Order{T}, P; price=price, amount=amt, date=dt, id=id, tag=tag, attrs=attrs, kwargs...)
end

# ============================================================
# 1. Type Hierarchy
# ============================================================
@testset "Type hierarchy" begin
    @test MarketOrderType{Buy} <: OrderType{Buy}
    @test LimitOrderType{Sell} <: OrderType{Sell}
    @test GTCOrderType{Buy} <: LimitOrderType{Buy}
    @test PostOnlyOrderType{Buy} <: GTCOrderType{Buy}
    @test ImmediateOrderType{Sell} <: LimitOrderType{Sell}
    @test FOKOrderType{Sell} <: ImmediateOrderType{Sell}
    @test IOCOrderType{Sell} <: ImmediateOrderType{Sell}
    @test LiquidationType{Sell} <: MarketOrderType{Sell}
    @test ForcedOrderType{Buy} <: MarketOrderType{Buy}
    @test Buy <: OrderSide
    @test Sell <: OrderSide
    @test BuyOrSell <: OrderSide
end

# ============================================================
# 2. Order Construction
# ============================================================
@testset "Order construction" begin
    o = make_order()
    @test o isa Order
    @test o.asset === asset
    @test o.exc === eid
    @test o.date == date
    @test o.price == 50000.0
    @test o.amount == 1.0
    @test o.id == ""
    @test o.tag == ""
    @test o.attrs isa NamedTuple

    o2 = make_order(T=GTCOrderType{Sell}, P=OrderTypes.Short)
    @test o2 isa Order

    o3 = make_order(id="ord123", tag="entry", attrs=(origin="manual",))
    @test o3.id == "ord123"
    @test o3.tag == "entry"
    @test o3.attrs.origin == "manual"

    o4 = Order(asset, eid, Order{MarketOrderType{Buy}}, OrderTypes.Short; price=100.0, amount=2.0, date=date)
    @test o4 isa Order
    @test o4.price == 100.0
    @test o4.amount == 2.0

    o5 = Order(asset, eid, Order{LiquidationType{Sell}}; price=50.0, amount=0.5, date=date)
    @test o5 isa Order
    @test o5.price == 50.0
    @test o5.amount == 0.5
end

# ============================================================
# 3. Order Type Aliases
# ============================================================
@testset "Order type aliases" begin
    b = make_order(T=MarketOrderType{Buy})
    s = make_order(T=MarketOrderType{Sell})
    sb = make_order(T=MarketOrderType{Buy}, P=OrderTypes.Short)
    ss = make_order(T=MarketOrderType{Sell}, P=OrderTypes.Short)

    @test b isa OrderTypes.BuyOrder
    @test s isa OrderTypes.SellOrder
    @test b isa OrderTypes.AnyBuyOrder
    @test s isa OrderTypes.AnySellOrder
    @test b isa OrderTypes.LongOrder
    @test ss isa OrderTypes.ShortOrder
    @test sb isa OrderTypes.ShortBuyOrder
    @test ss isa OrderTypes.ShortSellOrder

    @test b isa OrderTypes.IncreaseOrder
    @test ss isa OrderTypes.IncreaseOrder
    @test s isa OrderTypes.ReduceOrder
    @test sb isa OrderTypes.ReduceOrder

    @test make_order(T=FOKOrderType{Buy}) isa OrderTypes.AnyImmediateOrder
    @test make_order(T=IOCOrderType{Buy}) isa OrderTypes.AnyImmediateOrder
    @test make_order(T=GTCOrderType{Buy}) isa OrderTypes.AnyBuyOrder

    @test make_order(T=LiquidationType{Sell}) isa OrderTypes.LiquidationOrder
    @test make_order(T=ForcedOrderType{Sell}) isa OrderTypes.LongReduceOnlyOrder
    @test make_order(T=ForcedOrderType{Buy}, P=OrderTypes.Short) isa OrderTypes.ShortReduceOnlyOrder
end

# ============================================================
# 4. Order Helper Functions
# ============================================================
@testset "Order helpers" begin
    b = make_order(T=GTCOrderType{Buy})
    s = make_order(T=MarketOrderType{Sell})

    @test ordertype(b) == GTCOrderType{Buy}
    @test ordertype(s) == MarketOrderType{Sell}
    @test positionside(b) == OrderTypes.Long
    @test positionside(s) == OrderTypes.Long
    @test positionside(make_order(P=OrderTypes.Short)) == OrderTypes.Short
    @test orderside(b) == Buy
    @test orderside(s) == Sell

    @test exchangeid(b) == ExchangeID{:test_exchange}
    @test pricetime(b) == (price=50000.0, time=date)

    @test islong(b) == true
    @test islong(s) == true   # Sell with default Long position
    @test isshort(s) == false
    @test isshort(make_order(P=OrderTypes.Short)) == true
    @test islong(nothing) == false
    @test isshort(nothing) == false

    @test isimmediate(make_order(T=FOKOrderType{Buy})) == true
    @test isimmediate(make_order(T=MarketOrderType{Buy})) == true
    @test isimmediate(make_order(T=GTCOrderType{Buy})) == false

    @test ispos(Long(), b) == true
    @test ispos(Short(), b) == false

    @test sidetopos(b) == Long()
    @test sidetopos(s) == Short()
end

# ============================================================
# 5. opposite
# ============================================================
@testset "opposite" begin
    @test opposite(Buy) == Sell
    @test opposite(Sell) == Buy
    @test opposite(MarketOrderType{Buy}) == MarketOrderType{Sell}
    @test opposite(GTCOrderType{Sell}) == GTCOrderType{Buy}
end

# ============================================================
# 6. liqside and sidetopos / postoside
# ============================================================
@testset "liqside / sidetopos / postoside" begin
    @test liqside(Long()) == Sell
    @test liqside(Short()) == Buy
    @test liqside(Long) == Sell
    @test liqside(Short) == Buy

    @test sidetopos(Buy) == Long()
    @test sidetopos(Sell) == Short()
    @test postoside(Long()) == Buy
    @test postoside(Short()) == Sell
end

# ============================================================
# 7. Order hash and equality
# ============================================================
@testset "Order hash/equality" begin
    o1 = make_order(id="a")
    o2 = make_order(id="b")
    o1c = make_order(id="a")
    @test hash(o1) == hash(o1c)
    @test o1 == o1c
    @test isless(o1, make_order(dt=date + Dates.Second(1))) == true
end

# ============================================================
# 8. Trade Construction
# ============================================================
@testset "Trade construction" begin
    o = make_order()
    t = Trade(o; date=date, amount=1.0, price=50000.0, fees=0.01, size=50000.0)
    @test t isa Trade
    @test t.order === o
    @test t.date == date
    @test t.amount == 1.0
    @test t.price == 50000.0
    @test t.value == 50000.0
    @test t.fees == 0.01
    @test t.size == -50000.0
    @test t.leverage == 1.0
    @test t.entryprice == 50000.0
    @test t.fees_base == 0.0

    os = make_order(T=MarketOrderType{Sell})
    ts = Trade(os; date=date, amount=1.0, price=50000.0, fees=0.01, size=50000.0)
    @test ts.amount == -1.0
    @test ts.size == 50000.0

    oss = make_order(T=GTCOrderType{Sell}, P=OrderTypes.Short)
    tss = Trade(oss; date=date, amount=1.0, price=50000.0, fees=0.01, size=50000.0)
    @test tss.size < 0.0

    tb = Trade(o; date=date, amount=0.99, price=50000.0, fees=0.005, size=49500.0, fees_base=0.5)
    @test tb.fees_base == 0.5
    @test tb.value == 49500.0
end

# ============================================================
# 9. Trade Type Aliases
# ============================================================
@testset "Trade type aliases" begin
    b = Trade(make_order(); date=date, amount=1.0, price=100.0, fees=0.0, size=100.0)
    s = Trade(make_order(T=MarketOrderType{Sell}); date=date, amount=1.0, price=100.0, fees=0.0, size=100.0)
    sb = Trade(make_order(T=MarketOrderType{Buy}, P=OrderTypes.Short); date=date, amount=1.0, price=100.0, fees=0.0, size=100.0)
    ss = Trade(make_order(T=MarketOrderType{Sell}, P=OrderTypes.Short); date=date, amount=1.0, price=100.0, fees=0.0, size=100.0)
    liq = Trade(make_order(T=LiquidationType{Sell}); date=date, amount=1.0, price=100.0, fees=0.0, size=100.0)

    @test b isa OrderTypes.BuyTrade
    @test s isa OrderTypes.SellTrade
    @test sb isa OrderTypes.ShortBuyTrade
    @test ss isa OrderTypes.ShortSellTrade
    @test b isa OrderTypes.IncreaseTrade
    @test ss isa OrderTypes.IncreaseTrade
    @test s isa OrderTypes.ReduceTrade
    @test sb isa OrderTypes.ReduceTrade
    @test liq isa OrderTypes.LiquidationTrade
end

# ============================================================
# 10. Trade Helper Functions
# ============================================================
@testset "Trade helpers" begin
    t = Trade(make_order(); date=date, amount=1.0, price=50000.0, fees=0.01, size=50000.0)

    @test exchangeid(t) == ExchangeID{:test_exchange}
    @test positionside(t) == OrderTypes.Long
    @test orderside(t) == Buy
    @test ordertype(t) == MarketOrderType{Buy}

    @test islong(t) == true
    @test isshort(t) == false
    @test ispos(Long(), t) == true
    @test ispos(Short(), t) == false

    @test order_fees(t) == 0.01

    tb = Trade(make_order(); date=date, amount=1.0, price=50000.0, fees=0.01, size=50000.0, fees_base=0.5)
    @test order_fees(tb) == 0.01 + 0.5 * 50000.0
end

# ============================================================
# 12. Event System
# ============================================================
@testset "Event system" begin
    @test AssetEvent{:test} <: ExchangeEvent
    @test StrategyEvent{:test} <: ExchangeEvent

    ae = AssetEvent{:test}(:my_tag, :my_group, (key="val",))
    @test ae.tag == :my_tag
    @test ae.group == :my_group
    @test ae.data.key == "val"

    se = StrategyEvent{:test}(:other_tag, :other_group, (num=42,))
    @test se.tag == :other_tag
    @test se.group == :other_group
    @test se.data.num == 42

    @test AssetEvent{:test}(:t, :g, (k=1,)) isa ExchangeEvent
end

# ============================================================
# 13. Position Events
# ============================================================
@testset "Position events" begin
    using OrderTypes: PositionEvent, PositionUpdated, MarginUpdated, LeverageUpdated

    pe = PositionUpdated{:binance}(
        :liq_event, :default, "BTC/USDT", (Long(), true),
        date, 45000.0, 48000.0, 1000.0, 2000.0, 10.0, 50000.0
    )
    @test pe.tag == :liq_event
    @test pe.asset == "BTC/USDT"
    @test pe.entryprice == 48000.0
    @test pe.leverage == 10.0
    @test pe.notional == 50000.0

    me = MarginUpdated{:okx}(
        :margin_change, :group1, "ETH/USDT", Short(),
        date, "cross", 1000.0, 1500.0
    )
    @test me.side == Short()
    @test me.mode == "cross"
    @test me.from == 1000.0

    le = LeverageUpdated{:bybit}(
        :lev_change, :group1, "ETH/USDT", Long(),
        date, 5.0, 10.0
    )
    @test le.from == 5.0
    @test le.value == 10.0
end

# ============================================================
# 14. Balance / OHLCV Events
# ============================================================
@testset "Balance/OHLCV events" begin
    exc = Exchange(:test_only_for_events_2)
    be = OrderTypes.BalanceUpdated(exc, :bal_tag, :bal_group, Dict(:BTC => 1.5, :USDT => 10000.0))
    @test be.tag == :bal_tag
    @test be.group == :bal_group
    @test be.data.balance[:BTC] == 1.5

    oe = OrderTypes.OHLCVUpdated{:test}(:ohlcv_tag, :ohlcv_group, (open=100.0, high=110.0, low=99.0, close=105.0))
    @test oe.data.open == 100.0
end

# ============================================================
# 15. ByPos / BySide Dispatch
# ============================================================
@testset "ByPos/BySide dispatch" begin
    b2 = make_order()
    @test orderside(Buy) == Buy
    @test orderside(Sell) == Sell
    @test orderside(b2) == Buy
    @test isside(Long(), Long()) == true
    @test isside(Short(), Short()) == true
    @test isside(Long(), Short()) == false

    @test ReduceOnlyOrder(Long) == OrderTypes.LongReduceOnlyOrder
    @test ReduceOnlyOrder(Short) == OrderTypes.ShortReduceOnlyOrder
    @test ReduceOnlyOrder(Long, Asset) == OrderTypes.LongReduceOnlyOrder{Asset}
end

# ============================================================
# 16. Error Types
# ============================================================
@testset "Error types" begin
    @test OrderTypes.NotEnoughCash(required=100.0) isa OrderTypes.OrderError
    @test OrderTypes.NotEnoughLiquidity() isa OrderTypes.OrderError
    @test OrderTypes.NotMatched(price=100.0, this_price=101.0, amount=1.0, this_volume=0.5) isa OrderTypes.OrderError
    @test OrderTypes.NotFilled(amount=1.0, this_volume=0.5) isa OrderTypes.OrderError
    @test OrderTypes.OrderFailed(msg="some error") isa OrderTypes.OrderError
    @test OrderTypes.OrderTimeOut(order=make_order()) isa OrderTypes.OrderError
    @test OrderTypes.OrderCanceled(order=make_order()) isa OrderTypes.OrderError

    lo = OrderTypes.LiquidationOverride(order=make_order(), liqprice=45000.0, liqdate=date, p=Long())
    @test lo isa OrderTypes.OrderError
    @test lo.liqprice == 45000.0
    @test lo.p == Long()
end

# ============================================================
# 17. signedamount / signedsize
# ============================================================
@testset "signedamount/signedsize" begin
    b = make_order()
    s = make_order(T=MarketOrderType{Sell})

    @test signedamount(1.0, b) == 1.0
    @test signedamount(1.0, s) == -1.0

    @test signedsize(100.0, b) == -100.0
    @test signedsize(100.0, s) == 100.0
end

# ============================================================
# 18. Print / Display smoke tests
# ============================================================
@testset "Print/display" begin
    o = make_order(id="test_id")
    t = Trade(o; date=date, amount=1.0, price=50000.0, fees=0.01, size=50000.0)
    buf = IOBuffer()
    display(buf, o)
    @test String(take!(buf)) != ""
    display(buf, t)
    @test String(take!(buf)) != ""
    show(buf, o)
    @test String(take!(buf)) != ""

    # display with trades/committed/unfilled attributes
    o2 = make_order(attrs=(trades=[t], committed=Ref(0.5), unfilled=Ref(0.3)))
    buf2 = IOBuffer()
    display(buf2, o2)
    s = String(take!(buf2))
    @test occursin("Trades:", s)
    @test occursin("Committed:", s)
    @test occursin("Unfilled:", s)
end

# ============================================================
# 19. Macro-generated order types
# ============================================================
@testset "Macro order types" begin
    @test isdefined(OrderTypes, :GTCOrder)
    @test isdefined(OrderTypes, :ShortFOKOrder)
    gtc = make_order(T=GTCOrderType{Buy})
    @test gtc isa OrderTypes.GTCOrder
end

# ============================================================
# 20. ReduceOnlyOrder multi-param dispatch
# ============================================================
@testset "ReduceOnlyOrder multi-param" begin
    @test ReduceOnlyOrder(Long, Asset, ExchangeID) == OrderTypes.LongReduceOnlyOrder{Asset, ExchangeID}
    @test ReduceOnlyOrder(Short, Asset, ExchangeID) == OrderTypes.ShortReduceOnlyOrder{Asset, ExchangeID}
end

# ============================================================
# 21. Edge cases
# ============================================================
@testset "Edge cases" begin
    o_neg = Order(asset, eid, Order{MarketOrderType{Buy}}; price=-1.0, amount=-1.0, date=date)
    @test o_neg.price == -1.0
    @test o_neg.amount == -1.0

    @test Buy == OrderTypes.BuyOrSell
    @test OrderTypes.BuyOrSell == Sell
end
