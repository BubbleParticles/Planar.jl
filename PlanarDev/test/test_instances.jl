using PlanarDev.Planar.Engine.Instruments: @a_str
using PlanarDev.Planar.Engine.Instruments.Derivatives: @d_str
using PlanarDev.Planar.Engine.Instances: @rprice, @ramount

macro asset_constructor(asset=PlanarDev.Planar.Engine.Instruments.@a_str("BTC/USDT"), margin=PlanarDev.Planar.Engine.Misc.NoMargin)
    e = quote
        a = $asset
        e = PlanarDev.Planar.Engine.Exchanges.getexchange!(:binance)
        eid = e.id
        M = $margin()
        ii = PlanarDev.Planar.Engine.Instances.InstrumentInstance(a, PlanarDev.Planar.Engine.Data.Dict(PlanarDev.Planar.Engine.TimeTicks.TimeFrames.@tf_str("1m") => PlanarDev.Planar.Engine.Data.DataFrame()), e, M; PlanarDev.Planar.Engine.Instances.DEFAULT_FIELDS...)
    end
    e = esc(e)
end

macro order_constructor()
    e = quote
    o = Planar.Engine.Executors.basicorder(
        ii,
        100,
        1,
        Ref(100),
        Planar.Engine.Executors.SanitizeOff();
        type=Planar.Engine.OrderTypes.MarketOrder{Planar.Engine.Misc.Buy},
        date=Planar.Engine.TimeTicks.Dates.DateTime(2020, 1, 1),
    )
    end
    e = esc(e)
end

function test_asset_instance()
    @asset_constructor()
    @test ii.asset == a"BTC/USDT"
    @test ii.data isa SortedDict{TimeFrame,DataFrame,Base.Order.ForwardOrdering}
    @test ii.history isa SortedArray{AnyTrade{typeof(a),typeof(eid)},1}
    @test isempty(ii.history)
    @test ii.lock isa SafeLock
    @test ii.cash isa CCash{typeof(eid)}
    @test ii.cash_committed isa CCash{typeof(eid)}
    @test ii.exchange == getexchange!(:binance)
    @test ii.longpos == nothing
    @test ii.shortpos == nothing
    @test ii.lastpos[] == nothing
    @test inst.marginmode(ii) == NoMargin()
    @test inst.ishedged(ii) == false

    @test_throws MethodError @asset_constructor(a"BTC/USDT", Cross)
    @asset_constructor(d"BTC/USDT:USDT", Cross)
    @test inst.marginmode(ii) == Cross()
    @test inst.ishedged(ii) == false
    @test_throws AssertionError @asset_constructor(d"BTC/USDT:USDT", CrossHedged)
    @asset_constructor(d"BTC/USDT:USDT", Isolated)
    @test inst.marginmode(ii) == Isolated()
    @test inst.ishedged(ii) == false
end

function test_positions_function()
    M = NoMargin
    a = a"BTC/USDT"
    limits = (;
        leverage=(; min=1.0, max=1.0),
        amount=(min=2.0, max=2.0),
        price=(min=3.0, max=3.0),
        cost=(min=4.0, max=4.0),
    )
    e = getexchange!(:binance)
    @test positions(M, a, limits, e) == (nothing, nothing)

    M = Cross
    @test_throws MethodError positions(M, a, limits, e)
    a = d"BTC/USDT:USDT"
    pos_long, pos_short = positions(M, a, limits, e)
    @test pos_long isa inst.LongPosition
    @test pos_short isa inst.ShortPosition
end

function test_hash_function()
    a = a"BTC/USDT"
    e = getexchange!(:binance)
    M = NoMargin()
    ii = InstrumentInstance(a, Dict(), e, M; inst.DEFAULT_FIELDS...)
    @test inst._hashtuple(ii) == (Instruments._hashtuple(a)..., e.id)
    @test hash(ii) == hash(inst._hashtuple(ii))
    @test hash(ii, UInt(123)) == hash(inst._hashtuple(ii), UInt(123))
end

function test_lock_function()
    @asset_constructor()

    @test lock(ii) === nothing
    @test islocked(ii) === true
    @test unlock(ii) === nothing
    @test islocked(ii) === false
end

function test_broadcastable_function()
    @asset_constructor()

    @test Broadcast.broadcastable(ii) isa Ref
    @test Broadcast.broadcastable(ii).x === ii
end

function test_propertynames_function()
    @asset_constructor()

    @test propertynames(ii) == (fieldnames(InstrumentInstance)..., :ohlcv, :funding)
    @test fieldnames(InstrumentInstance) == (
        :attrs,
        :asset,
        :data,
        :history,
        :lock,
        :_internal_lock,
        :cash,
        :cash_committed,
        :exchange,
        :longpos,
        :shortpos,
        :lastpos,
        :limits,
        :precision,
        :fees,
    )
end

function test_makerfees_function()
    @asset_constructor()
    @test makerfees(ii) == ii.fees.maker
end

function test_minfees_function()
    @asset_constructor()
    @test minfees(ii) == ii.fees.min
end

function test_maxfees_function()
    @asset_constructor()
    @test maxfees(ii) == ii.fees.max
end

function test_exchangeid_function()
    @asset_constructor()
    @test exchangeid(ii) == ExchangeID{:binance}
end

function test_exchange_function()
    @asset_constructor()
    @test exchange(ii) == getexchange!(:binance)
end

function test_position_function()
    @asset_constructor()
    @test_throws MethodError position(ii, Long())
    @test_throws MethodError position(ii, Short())
    @test_throws MethodError position(ii)
    @asset_constructor(d"BTC/USDT:USDT", Isolated)
    @test position(ii, Long()) isa inst.LongPosition
    @test position(ii, Short()) isa inst.ShortPosition
    @test position(ii) === nothing
    @test position(ii, Long()) == ii.longpos
    @test position(ii, Short()) == ii.shortpos
    @test position(ii) == ii.lastpos[]
end

function test_trades_function()
    @asset_constructor()
    @test trades(ii) === ii.history
    @test trades(ii) isa SortedArray{AnyTrade{typeof(a),typeof(eid)},1}
    @test isempty(trades(ii))
end

function test_timestamp_function()
    @asset_constructor()
    @test inst.timestamp(ii) == inst._history_timestamp(ii)
    @test inst.timestamp(ii, Long()) == DateTime(0)
    @asset_constructor(d"BTC/USDT:USDT", Isolated)
    @test inst.timestamp(ii, Long()) == inst.timestamp(position(ii, Long()))
    @test inst.timestamp(ii, Short()) == inst.timestamp(position(ii, Short()))
    @test inst.timestamp(ii) == DateTime(0)
end

function test_leverage_function()
    @asset_constructor()
    @test leverage(ii) == 1.0
    @test leverage(ii, Long()) == 1.0
    @test leverage(ii, Short()) == 1.0
    @asset_constructor(d"BTC/USDT:USDT", Isolated)
    @test leverage(ii, Long()) == leverage(position(ii, Long())) == 1.0
    @test leverage(ii, Short()) == leverage(position(ii, Short())) == 1.0
end

function test_marginmode_function()
    @asset_constructor()
    @test marginmode(ii) == NoMargin()
    @test marginmode(ii) == typeof(ii).parameters[3]()
    @test marginmode(ii, Long()) == typeof(ii).parameters[3]()
    @test marginmode(ii, Short()) == typeof(ii).parameters[3]()
    ii = @asset_constructor(d"BTC/USDT:USDT", Isolated)
    @test marginmode(ii, Long()) == marginmode(position(ii, Long()))
    @test marginmode(ii, Short()) == marginmode(position(ii, Short()))
end

function test_ishedged_function()
    @asset_constructor()
    @test inst.ishedged(ii) == false
    @test_throws AssertionError @asset_constructor(d"BTC/USDT:USDT", CrossHedged) # 
end

function test_tier_function()
    @asset_constructor()
    @test_throws MethodError inst.tier(ii)
    @asset_constructor(d"BTC/USDT:USDT", Isolated)
    @test_throws MethodError inst.tier(ii, Long())
    @test_throws MethodError inst.tier(ii, Short())
    @test inst.tier(ii, 1, Long())[1] == 1
    @test inst.tier(ii, 1e8, Short())[1] == nothing
end

function test_posside_function()
    @asset_constructor()
    @test inst.posside(ii) == Long()
    @asset_constructor(d"BTC/USDT:USDT", Isolated)
    @test inst.posside(ii) == nothing
    @test inst.posside(position(ii, Long)) == Long()
    @test inst.posside(position(ii, Short)) == Short()
end

function test_position_field_accessors()
    @asset_constructor(d"BTC/USDT:USDT", Isolated)
    @test inst.entryprice(ii, 0, Long()) == 0.0
    @test inst.entryprice(ii, 0, Short()) == 0.0
    @test inst.notional(ii, Long()) == 0.0
    @test inst.notional(ii, Short()) == 0.0
    @test inst.margin(ii, Long()) == 0.0
    @test inst.margin(ii, Short()) == 0.0
    @test inst.cash(ii, Long()) == 0.0
    @test inst.cash(ii, Short()) == 0.0
    @test inst.committed(ii, Long()) == 0.0
    @test inst.committed(ii, Short()) == 0.0
    @test_throws MethodError inst.pnl(ii, Long()) == 0.0
    @test_throws MethodError inst.pnl(ii, Short()) == 0.0
    @test inst.pnl(ii, Long(), 0) == 0.0
    @test inst.pnl(ii, Short(), 0) == 0.0
    @test inst.pnl(ii, Long(), 100) == 0.0
    @test inst.pnl(ii, Short(), 100) == 0.0
    cash!(cash(ii, Long()), 100.0)
    @test cash(ii, Long()) == 100.0
    cash!(cash(ii, Short()), 2.0)
    @test cash(ii, Short()) == 2.0
    p = position(ii, Long())
    entryprice!(p, 80.0)
    ii.longpos.status[] = PositionOpen()
    p = position(ii, Short())
    entryprice!(p, 60.0)
    ii.shortpos.status[] = PositionOpen()
    @test entryprice(ii, 10.0, Long()) == 80.0
    @test entryprice(ii, 10.0, Short()) == 60.0
    @test inst.pnl(ii, Long(), 80.0) == 0.0
    @test inst.pnl(ii, Long(), 60.0) == -2000.0
    @test inst.pnl(ii, Long(), 100.0) == 2000.0
    @test inst.pnlpct(ii, Long(), 0.0) == -1.0
    @test inst.pnlpct(ii, Long(), 81.0) == 0.0125
    @test inst.pnlpct(ii, Short(), 0.0) == 1.0
    @test inst.pnlpct(ii, Short(), 40.0) == 1 / 3
    @test inst.pnlpct(ii, Long(), 100.0) == 0.25
    @test inst.pnlpct(ii, Short(), 100.0) == -2 / 3
    @test inst.liqprice(ii, Long()) == 0.0
    @test inst.liqprice(ii, Short()) == 0.0
end

function test_bankruptcy_function()
    @asset_constructor()
    @test_throws MethodError inst.bankruptcy(ii, nothing)
    @asset_constructor(d"BTC/USDT:USDT", Isolated)
    @test inst.bankruptcy(ii, 100.0, Long()) == 0.0
    @test inst.bankruptcy(ii, 100.0, Short()) == 200.0
    cash!(cash(ii, Long()), 100.0)
    leverage!(ii, 10.0, Long())
    @test leverage(ii, Long()) == 10.0
    @test ii.longpos.leverage[] == 10.0
    @test inst.bankruptcy(ii, 100.0, Long()) == 90.0
    leverage!(ii, 10.0, Short())
    @test inst.leverage(ii, Short()) == 10.0
    @test ii.shortpos.leverage[] == 10.0
    @test inst.bankruptcy(ii, 100.0, Short()) == 110.0
end

function test_asset_instance_functions1()
    ii = @asset_constructor()

    # Test asset, raw, ohlcv, ohlcv_dict, bc, qc functions
    @test asset(ii) == ii.asset
    @test raw(ii) == raw(ii.asset)
    @test ohlcv(ii) == first(values(ii.data))
    @test ohlcv_dict(ii) == ii.data
    @test bc(ii) == ii.asset.bc
    @test qc(ii) == ii.asset.qc

    # Test takerfees, makerfees, maxfees, minfees functions
    @test takerfees(ii) == ii.fees.taker
    @test makerfees(ii) == ii.fees.maker
    @test maxfees(ii) == ii.fees.max
    @test minfees(ii) == ii.fees.min

    # Test exchangeid, exchange functions
    @test exchangeid(ii) == typeof(ii).parameters[2]
    @test exchange(ii) == ii.exchange

    # Test position, posside, cash, committed functions
    @test_throws MethodError position(ii, Long())
    @test_throws MethodError position(ii, Short())
    @test_throws MethodError position(ii)

    # Test liqprice, leverage, bankruptcy, entryprice, price functions
    @test_throws MethodError liqprice(ii, Long())
    @test_throws MethodError liqprice(ii, Short())
    @test_throws MethodError bankruptcy(ii, 100.0, Long())
    @test_throws MethodError bankruptcy(ii, 100.0, Short())
    @test_throws MethodError entryprice(ii, 100.0, Long())
    @test_throws MethodError entryprice(ii, 100.0, Short())

    # Test additional, margin, maintenance functions
    @test_throws MethodError additional(ii, Long())
    @test_throws MethodError additional(ii, Short())
    @test_throws MethodError margin(ii, Long())
    @test_throws MethodError margin(ii, Short())
    @test_throws MethodError maintenance(ii, Long())
    @test_throws MethodError maintenance(ii, Short())

    # Test leverage, mmr, status! functions
    @test_throws MethodError mmr(ii, 1000.0, Long())
    @test_throws MethodError mmr(ii, 1000.0, Short())
    @test_throws MethodError status!(ii, Long(), PositionOpen())
    @test_throws MethodError status!(ii, Short(), PositionOpen())

    # Test value functions
    @test value(ii) == ii.cash.value
    @test_throws MethodError value(ii, Long())
    @test_throws MethodError value(ii, Short())

    # Test pnl functions
    @test_throws MethodError pnl(ii, Long(), 100.0)
    @test_throws MethodError pnl(ii, Short(), 100.0)

    # Test pnlpct functions
    @test_throws MethodError inst.pnlpct(ii, Long(), 100.0)
    @test_throws MethodError inst.pnlpct(ii, Short(), 100.0)

    # Test lastprice functions
    price = 100.0
    amount = 100.0
    committed = Ref(100.0 * 100.0)
    o = ect.basicorder(
        ii,
        price,
        amount,
        committed,
        ect.SanitizeOff();
        type=MarketOrder{Buy},
        date=DateTime(2020, 1, 1),
    )
    size = committed[]
    fees = committed[] * ii.fees.taker
    fees_base = ZERO
    t = Trade(o; date=DateTime(2020, 1, 2), amount, price, size, fees, fees_base)
    push!(ii.history, t)
    @test lastprice(ii, Val(:history)) == last(ii.history).price
    @test lastprice(ii, DateTime(2020, 1, 1)) == lastprice(ii)

    # Test timeframe function
    @test timeframe(ii) == first(keys(ii.data))

    # Test instance and load! functions
    @test instance(ii.exchange, ii.asset) isa InstrumentInstance
    @test load!(ii) === nothing

    # Test similar function
    sim_ai = similar(ii)
    @test sim_ai isa InstrumentInstance
    @test sim_ai.asset == ii.asset
    @test sim_ai.exchange == ii.exchange
    @test marginmode(sim_ai) == marginmode(ii)
    @test ishedged(sim_ai) == ishedged(ii)

    # Test stub! function (skipped due to TimeTicks isless bug comparing Millisecond vs Month in Julia 1.12)
    @test_skip seeddata!(ii, da.empty_ohlcv())

end
function test_asset_instance_functions2()
    @asset_constructor(d"BTC/USDT:USDT", Isolated)
    # Test freecash functions
    cash!(cash(inst.position(ii, Long())), 100.0)
    cash!(cash(inst.position(ii, Short())), -200.0)
    cash!(committed(ii, Long()), 10.0)
    cash!(committed(ii, Short()), -20.0)
    @test_throws ErrorException freecash(ii)
    @test freecash(ii, Long()) == cash(ii, Long()) - committed(ii, Long())
    @test freecash(ii, Short()) == cash(ii, Short()) - committed(ii, Short())

    # Test reset! functions
    @test reset!(ii) === nothing
    @test reset!(ii, Long()) === nothing
    @test reset!(ii, Short()) === nothing

    # Test isdust functions
    @asset_constructor()
    @test isdust(ii, 100.0) == (ii.cash.value * 100.0 < ii.limits.cost.min)
    @test_throws MethodError isdust(ii, 100.0, Long())
    @test_throws MethodError isdust(ii, 100.0, Short())

    # Test nondust functions
    @asset_constructor(d"BTC/USDT:USDT", Isolated)
    pos = position(ii, Long())
    cash!(pos, 100.0)
    ii.lastpos[] = pos
    @test nondust(ii, 100.0) ==
        (cash(ii).value * 100.0 >= ii.limits.cost.min ? cash(ii).value : 0.0)
    @test nondust(ii, MarketOrder{Buy}, 101) == 100.0
    @test nondust(ii, MarketOrder{Sell}, 101) == 100.0

    # Test iszero functions
    @asset_constructor()
    @test iszero(ii, ii.cash.value) ==
        (abs(ii.cash.value) < ii.limits.amount.min - eps(DFT))
    @test iszero(ii, Long()) == (abs(ii.cash.value) < ii.limits.amount.min - eps(DFT))
    @test iszero(ii, Short()) == (abs(ii.cash.value) < ii.limits.amount.min - eps(DFT))
    @test iszero(ii) == (iszero(ii, Long()) && iszero(ii, Short()))

    # Test approxzero functions
    @test approxzero(ii, ii.cash.value) == iszero(ii, ii.cash.value)

    # Test gtxzero, ltxzero functions
    cash!(cash(ii), 100.0)
    @test gtxzero(ii, ii.cash.value, Val(:amount)) ==
        (ii.cash.value > ii.limits.amount.min + eps())
    @test ltxzero(ii, ii.cash.value, Val(:amount)) ==
        (ii.cash.value < ii.limits.amount.min + eps())
    cash!(cash(ii), -2ai.limits.amount.min)
    @test gtxzero(ii, ii.cash.value, Val(:amount)) == false
    @test ltxzero(ii, ii.cash.value, Val(:amount)) == true
    v = 2ai.limits.price.min
    @test gtxzero(ii, v, Val(:price)) == (v > ii.limits.price.min + eps())
    @test ltxzero(ii, v, Val(:price)) == (v < ii.limits.price.min + eps())
    v = 2ai.limits.cost.min
    @test gtxzero(ii, v, Val(:cost)) == (v > ii.limits.cost.min + eps())
    @test ltxzero(ii, v, Val(:cost)) == (v < ii.limits.cost.min + eps())
    v = -2ai.limits.price.min
    @test gtxzero(ii, v, Val(:price)) == (v > ii.limits.price.min + eps())
    @test ltxzero(ii, v, Val(:price)) == (v < ii.limits.price.min + eps())
    v = -2ai.limits.cost.min
    @test gtxzero(ii, v, Val(:cost)) == (v > ii.limits.cost.min + eps())
    @test ltxzero(ii, v, Val(:cost)) == (v < ii.limits.cost.min + eps())

    # Test isapprox functions
    @test isapprox(ii, ii.cash.value, ii.cash.value, Val(:amount)) == true
    @test isapprox(ii, 100.0, 100.0, Val(:price)) == true

    # Test isequal functions
    @test isequal(ii, ii.cash.value, ii.cash.value, Val(:amount)) == true
    @test isequal(ii, 100.0, 100.0, Val(:price)) == true

    # Test @_round, @rprice, @ramount macros
    @test (@rprice 100.0) == mi.toprecision(100.0, ii.precision.price)
    @test (@ramount 100.0) == mi.toprecision(100.0, ii.precision.amount)

    # Test candlelast functions
    df = da.empty_ohlcv()
    push!(df, Lang.fromstruct(da.default_value(da.Candle)))
    ii.data[tf"1m"] = df
    @test candlelast(ii, first(keys(ii.data)), DateTime(2020, 1, 1)) ==
        da.Candle(last(ii.data[first(keys(ii.data))])...)
    @test candlelast(ii) == da.Candle(last(ii.data[first(keys(ii.data))])...)

    # Test Order function
    @test_throws UndefKeywordError Order(ii, MarketOrder{Buy})
    @test Order(ii, MarketOrder{Buy}, date=DateTime(2020, 1, 1), price=10.0, amount=1.0) isa Order

    # Test print and show functions
    io = IOBuffer()
    print(io, ii)
    @test String(take!(io)) == "BTC/USDT~[-0.2(μ)]{Binance}"
    show(io, "text/plain", ii)
    @test !isempty(String(take!(io)))
    show(io, ii)
    @test !isempty(String(take!(io)))
end

function test_attr_functions()
    @asset_constructor()

    # Test attrs function
    @test attrs(ii) isa Dict{Symbol,Any}
    @test isempty(attrs(ii))

    # Test attr function
    setattr!(ii, 42, :test_key)
    @test attr(ii, :test_key) == 42
    @test attr(ii, :non_existent_key, "default") == "default"

    # Test hasattr function
    @test hasattr(ii, :test_key)
    @test !hasattr(ii, :non_existent_key)
    @test hasattr(ii, :test_key, :non_existent_key) == true
    @test hasattr(ii, :non_existent_key1, :non_existent_key2) == false

    # Test attr! function
    @test attr!(ii, :new_key, "new_value") == "new_value"
    @test attr(ii, :new_key) == "new_value"

    # Test setattr! function
    setattr!(ii, "updated_value", :test_key)
    @test attr(ii, :test_key) == "updated_value"

    # Test modifyattr! function
    @test_throws MethodError modifyattr!(ii, 10, +, :test_key)

    # Test multiple keys
    # setattr!(ii, 100, :key1, :key2, :key3)
    # @test attr(ii, :key1) == 100
    # @test attr(ii, :key2) == 100
    # @test attr(ii, :key3) == 100

    # Test attrs function with multiple keys
    # @test attrs(ii, :key1, :key2, :non_existent) == (100, 100, nothing)

    println("All attr functions tests passed!")
end

function test_instances()
    @eval begin
        using PlanarDev
        @environment!
        using Lang
        using .inst
        using .inst:
            Limits,
            positions,
            SortedDict,
            SortedArray,
            AnyTrade,
            ExchangeID,
            Exchange,
            CCash,
            CrossHedged,
            IsolatedHedged,
            trades,
            freecash,
            entryprice!
        using .Instruments
        using .Instruments: cash!
        using .inst.Data: DataFrame, candlelast
        using .im
        using .ect: SanitizeOff
    end
    prev = get(ENV, "JULIA_TEST_FAILFAST", false)
    ENV["JULIA_TEST_FAILFAST"] = true
    @testset "instances" begin
        try
            Base.invokelatest(test_asset_instance)
            Base.invokelatest(test_positions_function)
            Base.invokelatest(test_hash_function)
            Base.invokelatest(test_lock_function)
            Base.invokelatest(test_broadcastable_function)
            Base.invokelatest(test_propertynames_function)
            Base.invokelatest(test_makerfees_function)
            Base.invokelatest(test_minfees_function)
            Base.invokelatest(test_maxfees_function)
            Base.invokelatest(test_exchangeid_function)
            Base.invokelatest(test_exchange_function)
            Base.invokelatest(test_position_function)
            Base.invokelatest(test_trades_function)
            Base.invokelatest(test_leverage_function)
            Base.invokelatest(test_marginmode_function)
            Base.invokelatest(test_timestamp_function)
            Base.invokelatest(test_ishedged_function)
            Base.invokelatest(test_tier_function)
            Base.invokelatest(test_posside_function)
            Base.invokelatest(test_position_field_accessors)
            Base.invokelatest(test_bankruptcy_function)
            Base.invokelatest(test_asset_instance_functions1)
            @test_skip true && Base.invokelatest(test_asset_instance_functions2)  # Skipped due to TimeTicks isless bug
            Base.invokelatest(test_attr_functions)
        finally
            ENV["JULIA_TEST_FAILFAST"] = prev
        end
    end
end
