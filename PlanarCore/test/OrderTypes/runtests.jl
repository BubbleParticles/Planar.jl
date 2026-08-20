using PlanarCore.OrderTypes
using Test
using Serialization: serialize, deserialize
const Instruments = PlanarCore.OrderTypes.Instruments
const _Dates = Instruments.Misc.TimeTicks.Dates
using PlanarCore.Instruments: Instrument, AbstractInstrument, @a_str
using PlanarCore.OrderTypes: ExchangeID, Exchange, ExchangeEvent, InstrumentEvent, StrategyEvent
using PlanarCore.OrderTypes: Trade, orderside, positionside, pricetime
using PlanarCore.OrderTypes: signedamount, signedsize, isliquidation, sidetopos
using PlanarCore.OrderTypes: ByPos, BySide, ReduceOnlyOrder
using PlanarCore.OrderTypes:
    MarketOrderType, LimitOrderType, GTCOrderType, PostOnlyOrderType,
    ImmediateOrderType, FOKOrderType, IOCOrderType,
    LiquidationType, ForcedOrderType
using PlanarCore.OrderTypes: signedamount, signedsize, isliquidation, sidetopos
using PlanarCore.OrderTypes: postoside, fees as order_fees
using PlanarCore.OrderTypes: Long, Short, ordertype, exchangeid
using PlanarCore.OrderTypes: price, size, amount, fees, fees_base, order_fees
using Base: hash
test_date = _Dates.now()
asset = a"BTC/USDT"
eid = ExchangeID(:test_exchange)

function make_order(; T=MarketOrderType{Buy}, P=OrderTypes.Long, price=50000.0, amt=1.0, dt=test_date, id="", tag="", attrs=(;), kwargs...)
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
    @test o.date == test_date

    o4 = Order(asset, eid, Order{MarketOrderType{Buy}}, OrderTypes.Short; price=100.0, amount=2.0, date=test_date)
    @test o4 isa Order
    @test o4.price == 100.0
    @test o4.amount == 2.0

    o5 = Order(asset, eid, Order{LiquidationType{Sell}}; price=50.0, amount=0.5, date=test_date)
    @test o5 isa Order
    @test o5.price == 50.0
    @test o5.amount == 0.5

    o6 = Order(asset, eid, Order{ForcedOrderType{Sell}}; price=50.0, amount=0.5, date=test_date)
    @test o6 isa Order
    @test o6.price == 50.0
    @test o6.amount == 0.5

    o7 = Order(asset, eid, Order{MarketOrderType{Buy}}; price=50000.0, amount=1.0, date=test_date)
    @test o7 isa Order
    @test o7.price == 50000.0
    @test o7.amount == 1.0

    o8 = Order(asset, eid, Order{LimitOrderType{Buy}}; price=50000.0, amount=1.0, date=test_date)
    @test o8 isa Order
    @test o8.price == 50000.0
    @test o8.amount == 1.0

    o9 = Order(asset, eid, Order{GTCOrderType{Buy}}; price=50000.0, amount=1.0, date=test_date)
    @test o9 isa Order
    @test o9.price == 50000.0
    @test o9.amount == 1.0

    o10 = Order(asset, eid, Order{PostOnlyOrderType{Buy}}; price=50000.0, amount=1.0, date=test_date)
    @test o10 isa Order
    @test o10.price == 50000.0
    @test o10.amount == 1.0

    o11 = Order(asset, eid, Order{ImmediateOrderType{Buy}}; price=50000.0, amount=1.0, date=test_date)
    @test o11 isa Order
    @test o11.price == 50000.0
    @test o11.amount == 1.0

    o12 = Order(asset, eid, Order{FOKOrderType{Buy}}; price=50000.0, amount=1.0, date=test_date)
    @test o12 isa Order
    @test o12.price == 50000.0
    @test o12.amount == 1.0

    o13 = Order(asset, eid, Order{IOCOrderType{Buy}}; price=50000.0, amount=1.0, date=test_date)
    @test o13 isa Order
    @test o13.price == 50000.0
    @test o13.amount == 1.0

    o14 = Order(asset, eid, Order{MarketOrderType{Sell}}; price=50000.0, amount=1.0, date=test_date)
    @test o14 isa Order
    @test o14.price == 50000.0
    @test o14.amount == 1.0

    o15 = Order(asset, eid, Order{MarketOrderType{Buy}}; price=50000.0, amount=1.0, date=test_date)
    @test o15 isa Order
    @test o15.price == 50000.0
    @test o15.amount == 1.0
end

@testset "Order equality and comparison" begin
    o1 = make_order()
    o1c = make_order()
    @test o1 == o1c
    @test o1.id == o1c.id
    @test pricetime(o1) == (price=50000.0, time=test_date)

    @test o1 == o1c
    @test isless(o1, make_order(dt=test_date + _Dates.Second(1))) == true
end

@testset "Trade" begin
    o = make_order()
    t = Trade(o; date=test_date, amount=1.0, price=50000.0, fees=0.01, size=50000.0)
    @test t isa Trade
    @test t.order === o
    @test t.date == test_date
    @test t.amount == 1.0
    @test t.price == 50000.0
    @test t.value == 50000.0

    os = make_order(T=MarketOrderType{Sell})
    ts = Trade(os; date=test_date, amount=1.0, price=50000.0, fees=0.01, size=50000.0)
    @test ts.amount == -1.0
    @test ts.size == 50000.0

    oss = make_order(T=GTCOrderType{Sell}, P=OrderTypes.Short)
    tss = Trade(oss; date=test_date, amount=1.0, price=50000.0, fees=0.01, size=50000.0)
    @test tss.size < 0.0

    tb = Trade(o; date=test_date, amount=0.99, price=50000.0, fees=0.005, size=49500.0, fees_base=0.5)
    @test tb.fees_base == 0.5
    @test tb.value == 49500.0
end

@testset "Trade type aliases" begin
    b = Trade(make_order(); date=test_date, amount=1.0, price=100.0, fees=0.0, size=100.0)
    s = Trade(make_order(T=MarketOrderType{Sell}); date=test_date, amount=1.0, price=100.0, fees=0.0, size=100.0)
    sb = Trade(make_order(T=MarketOrderType{Buy}, P=OrderTypes.Short); date=test_date, amount=1.0, price=100.0, fees=0.0, size=100.0)
    ss = Trade(make_order(T=MarketOrderType{Sell}, P=OrderTypes.Short); date=test_date, amount=1.0, price=100.0, fees=0.0, size=100.0)
    liq = Trade(make_order(T=LiquidationType{Sell}); date=test_date, amount=1.0, price=100.0, fees=0.0, size=100.0)

    @test b isa OrderTypes.BuyTrade
    @test s isa OrderTypes.SellTrade
    @test sb isa OrderTypes.ShortBuyTrade
    @test ss isa OrderTypes.ShortSellTrade
    @test liq isa OrderTypes.LiquidationTrade
end

@testset "Trade helpers" begin
    t = Trade(make_order(); date=test_date, amount=1.0, price=50000.0, fees=0.01, size=50000.0)

    @test exchangeid(t) == ExchangeID{:test_exchange}
    @test positionside(t) == Long
    @test price(t) == 50000.0
    @test size(t) == -50000.0
    @test amount(t) == 1.0
    @test fees(t) == 0.01
    @test fees_base(t) == 0.0

    tb = Trade(make_order(); date=test_date, amount=1.0, price=50000.0, fees=0.01, size=50000.0, fees_base=0.5)
    @test order_fees(tb) == 0.01 + 0.5 * 50000.0
end

@testset "OrderEvent" begin
    pe = OrderEvent(
        :liq_event, :default, "BTC/USDT", (Long(), true),
        test_date, 45000.0, 48000.0, 1000.0, 2000.0, 10.0, 50000.0
    )
    @test pe.tag == :liq_event
    @test pe.asset == "BTC/USDT"
    @test pe.side == Long()
    @test pe.reduce_only == true
    @test pe.date == test_date
    @test pe.price == 45000.0
    @test pe.max_price == 48000.0
    @test pe.qty == 1000.0
    @test pe.max_qty == 2000.0
    @test pe.leverage == 10.0
    @test pe.entry_price == 50000.0
end

@testset "MarginEvent" begin
    me = MarginEvent(
        :margin_change, :group1, "ETH/USDT", Short(),
        test_date, "cross", 1000.0, 1500.0
    )
    @test me.side == Short()
    @test me.mode == "cross"
    @test me.date == test_date
    @test me.amount == 1000.0
    @test me.new_amount == 1500.0
end

@testset "LeverageEvent" begin
    le = LeverageEvent(
        :lev_change, :group1, "ETH/USDT", Long(),
        test_date, 5.0, 10.0
    )
    @test le.from == 5.0
    @test le.value == 10.0
    @test le.date == test_date
end

@testset "LiquidationOverride" begin
    lo = OrderTypes.LiquidationOverride(order=make_order(), liqprice=45000.0, liqdate=test_date, p=Long())
    @test lo isa OrderTypes.OrderError
    @test lo.liqprice == 45000.0
    @test lo.p == Long()
end

@testset "Serialization" begin
    o = make_order(id="test_id")
    t = Trade(o; date=test_date, amount=1.0, price=50000.0, fees=0.01, size=50000.0)
    buf = IOBuffer()
    display(buf, o)
    @test String(take!(buf)) != ""

    # serialization of order and trade
    ob = IOBuffer()
    serialize(ob, o)
    seekstart(ob)
    o2 = deserialize(ob)
    @test o2 == o

    tb = IOBuffer()
    serialize(tb, t)
    seekstart(tb)
    t2 = deserialize(tb)
    @test t2 == t
end

@testset "Edge cases" begin
    o_neg = Order(asset, eid, Order{MarketOrderType{Buy}}; price=-1.0, amount=-1.0, date=test_date)
    @test o_neg.price == -1.0
    @test o_neg.amount == -1.0
end

# ============================================================
# 12. Event System
# ============================================================
@testset "Event system" begin
    @test InstrumentEvent{:test} <: ExchangeEvent
    @test StrategyEvent{:test} <: ExchangeEvent

    ae = InstrumentEvent{:test}(:my_tag, :my_group, (key="val",))
    @test ae.tag == :my_tag
    @test ae.group == :my_group
    @test ae.data.key == "val"

    se = StrategyEvent{:test}(:other_tag, :other_group, (num=42,))
    @test se.tag == :other_tag
    @test se.group == :other_group
    @test se.data.num == 42

    @test InstrumentEvent{:test}(:t, :g, (k=1,)) isa ExchangeEvent
end

# ============================================================
# 13. Position Events
# ============================================================
@testset "Position events" begin
    using PlanarCore.OrderTypes: PositionEvent, PositionUpdated, MarginUpdated, LeverageUpdated

    pe = PositionUpdated{:binance}(
        :liq_event, :default, "BTC/USDT", (Long(), true),
        test_date, 45000.0, 48000.0, 1000.0, 2000.0, 10.0, 50000.0
    )
    @test pe.tag == :liq_event
    @test pe.asset == "BTC/USDT"
    @test pe.entryprice == 48000.0
    @test pe.leverage == 10.0
    @test pe.notional == 50000.0

    me = MarginUpdated{:okx}(
        :margin_change, :group1, "ETH/USDT", Short(),
        test_date, "cross", 1000.0, 1500.0
    )
    @test me.side == Short()
    @test me.mode == "cross"
    @test me.from == 1000.0

    le = LeverageUpdated{:bybit}(
        :lev_change, :group1, "ETH/USDT", Long(),
        test_date, 5.0, 10.0
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
    @test ReduceOnlyOrder(Long, Instrument) == OrderTypes.LongReduceOnlyOrder{Instrument}
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

    lo = OrderTypes.LiquidationOverride(order=make_order(), liqprice=45000.0, liqdate=test_date, p=Long())
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
    t = Trade(o; date=test_date, amount=1.0, price=50000.0, fees=0.01, size=50000.0)
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
    @test ReduceOnlyOrder(Long, Instrument, ExchangeID) == OrderTypes.LongReduceOnlyOrder{Instrument, ExchangeID}
    @test ReduceOnlyOrder(Short, Instrument, ExchangeID) == OrderTypes.ShortReduceOnlyOrder{Instrument, ExchangeID}
end

# ============================================================
# 21. Edge cases
# ============================================================
@testset "Edge cases" begin
    o_neg = Order(asset, eid, Order{MarketOrderType{Buy}}; price=-1.0, amount=-1.0, date=test_date)
    @test o_neg.price == -1.0
    @test o_neg.amount == -1.0

    @test Buy == OrderTypes.BuyOrSell
    @test OrderTypes.BuyOrSell == Sell
end
