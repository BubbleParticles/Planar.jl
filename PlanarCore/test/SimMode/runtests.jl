module Runtests

using Test
using PlanarCore
using Random

using PlanarCore.SimMode
using PlanarCore.Collections
using PlanarCore.Strategies
using PlanarCore.Strategies.Instances.Exchanges.ExchangeTypes
using PlanarCore.Strategies.Instances.Exchanges.ExchangeTypes: CcxtExchange, ExchangeID, ExcPrecisionMode
using PlanarCore.Strategies.Instances.Exchanges.ExchangeTypes.OrderedCollections: OrderedSet
using PlanarCore.Strategies.Instances.Misc: Config
using PlanarCore.Strategies.Instances.Instruments: AbstractAsset
using PlanarCore.Strategies.Instances: AssetInstance, ohlcv, ohlcv_dict, ticks, setticks!, _check_ticks_ordered!, _ohlcv_keys
using PlanarCore.Strategies.Instances.DataStructures: SortedDict
using PlanarCore.Strategies.Instances.Data: DataFrame

const OT = SimMode.OrderTypes
const Order = OT.Order
const EID = OT.ExchangeTypes.ExchangeID
const DateTime = SimMode.DateTime
const Buy = SimMode.Buy
const Sell = SimMode.Sell

_asset = SimMode.Asset("BTC/USDT")
_eid = EID(:test)
_dt = DateTime(2024, 1, 1)

module TickStrat
using PlanarCore
using PlanarCore.Misc: Sim, DFT
using PlanarCore.Strategies: Strategy
import PlanarCore.Strategies: ping!
using PlanarCore.Executors: call!
using PlanarCore.Instances: raw
using PlanarCore.SimMode: TickContext, TradeTick
using PlanarCore.SimMode.OrderTypes: MarketOrder, Buy

const seen = Ref(0)
const seen_btc = Ref(0)
const buy_price = Ref(DFT(0.0))

function reset!()
    seen[] = 0
    seen_btc[] = 0
    buy_price[] = DFT(0.0)
end

function ping!(s::Strategy{Sim}, ctx::TickContext, tick::TradeTick)
    seen[] += 1
    if raw(tick.asset) == "BTC/USDT"
        seen_btc[] += 1
        if seen_btc[] == 5
            buy_price[] = tick.price
            call!(s, tick.asset, MarketOrder{Buy}; amount=1.0, date=tick.timestamp)
        end
    end
    nothing
end
end

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
    rng = Random.MersenneTwister(1234)
    # ratio > 100 → always filled, full amount
    filled, amt = SimMode._fill_happened(rng, 1.0, 200.0)
    @test filled == true
    @test amt == 1.0

    # ratio between 10 and 100 → rand() < log10(ratio)
    # log10(500/10) = log10(50) ≈ 1.699 → always true
    filled2, amt2 = SimMode._fill_happened(rng, 10.0, 500.0)
    @test filled2 == true
    @test amt2 == 10.0

    # ratio <= 10 → recursive reduction until amount exhausted
    filled3, amt3 = SimMode._fill_happened(rng, 10.0, 5.0)
    @test filled3 == false
    @test amt3 == 0.0

    # amount = 0 → Inf ratio, always filled
    filled4, amt4 = SimMode._fill_happened(rng, 0.0, 100.0)
    @test filled4 == true
    @test amt4 == 0.0

    # max_depth = 1 → immediate fail for ratio <= 10
    filled5, amt5 = SimMode._fill_happened(rng, 10.0, 5.0; max_depth=1)
    @test filled5 == false
    @test amt5 == 0.0

    # reduction exhausts amount before max_depth → hits inner else branch (line 122)
    # amount=5, cdl_vol=1, max_reduction=0.5 → reduced=2.5, threshold=2.5, not > → false
    filled6, amt6 = SimMode._fill_happened(rng, 5.0, 1.0; max_reduction=0.5)
    @test filled6 == false
    @test amt6 == 0.0
end

@testset "backtest types (backtest.jl)" begin
    @test isdefined(SimMode, :StatsColumn)
end

# ── tick-by-tick backtesting ──────────────────────────────────────────
function _make_tick_exchange(name::Symbol)
    id = ExchangeID{name}()
    CcxtExchange{typeof(id)}(
        id, string(name), "", OrderedSet{String}(["1m"]),
        Dict{String,Dict{String,Any}}(
            "BTC/USDT" => Dict{String,Any}(
                "id" => "BTC/USDT", "base" => "BTC", "quote" => "USDT",
                "type" => "spot", "active" => true, "spot" => true, "linear" => true,
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
                "type" => "spot", "active" => true, "spot" => true, "linear" => true,
                "precision" => Dict{String,Any}("amount" => 8, "price" => 2),
                "limits" => Dict{String,Any}(
                    "amount" => Dict{String,Any}("min" => 1e-6, "max" => 1e8),
                    "price" => Dict{String,Any}("min" => 0.01, "max" => 1e6),
                    "cost" => Dict{String,Any}("min" => 1.0, "max" => 1e8),
                ),
                "taker" => 0.001, "maker" => 0.001,
            ),
        ),
        Set{Symbol}([:spot]), Dict{Symbol,Any}(:taker => 0.001, :maker => 0.001),
        Dict{Symbol,Any}(:fetchTicker => true, :fetchOHLCV => true),
        ExcPrecisionMode(2), nothing, [:fetchTicker, :fetchOHLCV], Dict{String,Any}(),
    )
end

_mock_exc = _make_tick_exchange(:test)
# route getexchange!(:test) / Strategies.reset!(s) to the mock — no gateway spawn
ExchangeTypes.sb_exchanges[(:test, "")] = _mock_exc

# Build a queued order through the production basicorder path. OType is a
# CONCRETE-T alias (e.g. OT.LimitOrder{Buy}) — the generic LimitOrder{S} alias
# now has concrete T (LimitOrderType{S}) and flows through call!/committment/
# basicorder dispatch; a fully 4-param-explicit Order{...} type breaks the
# internal OrderTypes.Order(ai, type) call.
function _make_sim_order(ai, OType; price, amount=1.0, date=_dt)
    comm = Ref(SimMode.Executors.committment(OType, ai, price, amount))
    SimMode.Executors.basicorder(ai, price, amount, comm, SimMode.Executors.Checks.SanitizeOff(); type=OType, date=date)
end
_queue_order!(s, ai, o) = SimMode.queue!(s, o, ai)

function _make_ohlcv(price, n=200; start=_dt)
    DataFrame(
        timestamp = [start + SimMode.Minute(i) for i in 0:n-1],
        open = [price for _ in 1:n],
        high = [price + 1.0 for _ in 1:n],
        low = [price - 1.0 for _ in 1:n],
        close = [price for _ in 1:n],
        volume = [1000.0 for _ in 1:n],
    )
end

function _make_ticks(n=100; start=_dt + SimMode.Minute(1), step=SimMode.Millisecond(1), price0=100.0)
    DataFrame(
        timestamp = [start + step * (i - 1) for i in 1:n],
        price = [price0 + i for i in 1:n],
        amount = [1.0 for _ in 1:n],
    )
end

function _make_tick_ai(sym; tick_df=nothing, ohlcv_price=50000.0)
    a = SimMode.Asset(sym)
    data = SortedDict(tf"1m" => _make_ohlcv(ohlcv_price))
    ai = AssetInstance(
        a, data, _mock_exc, SimMode.NoMargin();
        limits=(; leverage=(; min=1.0, max=100.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8)),
        precision=(; amount=8, price=2),
        fees=(; taker=0.001, maker=0.001, min=0.001, max=0.001),
    )
    isnothing(tick_df) || setticks!(ai, tick_df)
    ai
end

function _make_tick_strategy(ais)
    uni = Collections.AssetCollection(ais)
    cfg = Config(; qc=:USDT, initial_cash=10000.0, sandbox=true)
    # zero-period timeframe → WarmupPeriod() == Millisecond(0) → no ticks skipped
    Strategies.Strategy(
        @__MODULE__, SimMode.Sim(), SimMode.NoMargin(), SimMode.TimeFrame(SimMode.Millisecond(0)), _mock_exc, uni;
        config=cfg,
    )
end

@testset "ticks storage & ordering (Instances/ticks.jl)" begin
    ai = _make_tick_ai("BTC/USDT")
    df = _make_ticks(10)
    setticks!(ai, df)
    @test ticks(ai) === df
    @test ticks(ai).timestamp isa Vector{DateTime}
    # ohlcv accessor still returns the smallest OHLCV tf when ticks are present
    @test ohlcv(ai) === ai.data[tf"1m"]
    @test SimMode.timeframe(ai) == tf"1m"
    @test first(_ohlcv_keys(ai)) == tf"1m"

    # equal timestamps are valid
    df2 = DataFrame(
        timestamp=[_dt, _dt, _dt + SimMode.Millisecond(1)],
        price=[1.0, 2.0, 3.0], amount=[1.0, 1.0, 1.0],
    )
    setticks!(ai, df2)
    @test _check_ticks_ordered!(ai)
    # fingerprint cached
    @test ai.attrs[:_tick_order][1] == (_dt, _dt + SimMode.Millisecond(1), 3)
    # middle-row mutation with unchanged fingerprint → cached result, no re-validation
    df2[2, :timestamp] = _dt - SimMode.Millisecond(5)
    @test _check_ticks_ordered!(ai)
    # first-tick change re-validates → decrease detected
    df2[1, :timestamp] = _dt + SimMode.Millisecond(10)
    @test_throws ArgumentError _check_ticks_ordered!(ai)
    # fresh decrease throws
    setticks!(
        ai,
        DataFrame(
            timestamp=[_dt + SimMode.Millisecond(2), _dt + SimMode.Millisecond(1)],
            price=[1.0, 2.0], amount=[1.0, 1.0],
        ),
    )
    @test_throws ArgumentError _check_ticks_ordered!(ai)
end

@testset "TradeTickRange (SimMode/tickrange.jl)" begin
    ai_a = _make_tick_ai("BTC/USDT")
    ai_b = _make_tick_ai("ETH/USDT")
    setticks!(
        ai_a,
        DataFrame(
            timestamp=[_dt + SimMode.Millisecond(1), _dt + SimMode.Millisecond(3), _dt + SimMode.Millisecond(4)],
            price=[1.0, 3.0, 4.0], amount=[1.0, 1.0, 1.0],
        ),
    )
    setticks!(
        ai_b,
        DataFrame(
            timestamp=[_dt + SimMode.Millisecond(2), _dt + SimMode.Millisecond(4)],
            price=[2.0, 40.0], amount=[1.0, 1.0],
        ),
    )
    s = _make_tick_strategy([ai_a, ai_b])
    r = SimMode.TradeTickRange(s)
    @test length(r) == 5
    @test eltype(r) == SimMode.TradeTick
    ts = [t.timestamp for t in r]
    @test issorted(ts)
    # same-ms ticks (4ms) keep universe order: A before B
    @test r[4].asset === ai_a && r[5].asset === ai_b
    @test r[4].timestamp == r[5].timestamp
    @test r[1].asset === ai_a && r[2].asset === ai_b && r[3].asset === ai_a

    # Integer (Unix-ms) timestamps are converted via dt
    ai_c = _make_tick_ai("BTC/USDT")
    setticks!(
        ai_c,
        DataFrame(
            timestamp=[1_700_000_000_000, 1_700_000_000_001],
            price=[1.0, 2.0], amount=[1.0, 1.0],
        ),
    )
    r2 = SimMode.TradeTickRange(_make_tick_strategy([ai_c]))
    @test length(r2) == 2
    @test r2[1].timestamp isa DateTime

    # universe asset without ticks is a hard error
    ai_d = _make_tick_ai("BTC/USDT")
    @test_throws ArgumentError SimMode.TradeTickRange(_make_tick_strategy([ai_d]))
end

@testset "LimitOrder alias via call! (OrderTypes)" begin
    # the generic LimitOrder{S} alias is concrete-T: ordertype extracts the leaf
    @test OT.ordertype(OT.LimitOrder{Buy}) == OT.LimitOrderType{Buy}
    @test OT.ordertype(OT.LimitOrder{Sell}) == OT.LimitOrderType{Sell}

    # buy: call! with the generic alias queues (no MethodError), then fills at the
    # exact tick price. Note: call! returns `nothing` for a non-triggered GTC
    # limit (limitorder_ifprice!'s else branch) — the order is queued regardless.
    s = _make_tick_strategy([_make_tick_ai("BTC/USDT")])
    ai = first(s.universe)
    reset!(s)
    SimMode.Executors.call!(s, ai, OT.LimitOrder{Buy}; amount=1.0, price=100.0, date=_dt)
    o = only(values(SimMode.Executors.orders(s, ai, Buy)))
    @test o isa Order{<:OT.LimitOrderType{Buy}}
    @test SimMode.isqueued(o, s, ai)
    tick = SimMode.TradeTick(_dt + SimMode.Millisecond(1), ai, SimMode.DFT(99.0), SimMode.DFT(1.0))
    SimMode.update!(s, tick, SimMode.UpdateOrdersTick())
    @test SimMode.isfilled(ai, o)
    @test !SimMode.isqueued(o, s, ai)
    @test SimMode.OrderTypes.trades(ai)[end].price == SimMode.DFT(99.0)

    # sell mirror: prefund, sell limit at 100, tick at 101 → filled
    s2 = _make_tick_strategy([_make_tick_ai("BTC/USDT"; ohlcv_price=50.0)])
    ai2 = first(s2.universe)
    reset!(s2)
    SimMode.Instruments.add!(SimMode.cash(ai2), 1.0)
    SimMode.Executors.call!(s2, ai2, OT.LimitOrder{Sell}; amount=1.0, price=100.0, date=_dt)
    o2 = only(values(SimMode.Executors.orders(s2, ai2, Sell)))
    @test o2 isa Order{<:OT.LimitOrderType{Sell}}
    @test SimMode.isqueued(o2, s2, ai2)
    tick2 = SimMode.TradeTick(_dt + SimMode.Millisecond(1), ai2, SimMode.DFT(101.0), SimMode.DFT(1.0))
    SimMode.update!(s2, tick2, SimMode.UpdateOrdersTick())
    @test SimMode.isfilled(ai2, o2)
    @test SimMode.OrderTypes.trades(ai2)[end].price == SimMode.DFT(101.0)
end

@testset "UpdateOrdersTick fills (SimMode/orders/updates.jl)" begin
    # queued buy limit fills at the exact tick price (no slippage)
    s = _make_tick_strategy([_make_tick_ai("BTC/USDT")])
    ai = first(s.universe)
    reset!(s)
    o = _make_sim_order(ai, OT.LimitOrder{Buy}; price=100.0)
    @test !isnothing(o)
    @test _queue_order!(s, ai, o)
    @test SimMode.isqueued(o, s, ai)
    tick = SimMode.TradeTick(_dt + SimMode.Millisecond(1), ai, SimMode.DFT(99.0), SimMode.DFT(1.0))
    SimMode.update!(s, tick, SimMode.UpdateOrdersTick())
    @test SimMode.isfilled(ai, o)
    @test !SimMode.isqueued(o, s, ai)
    t = SimMode.OrderTypes.trades(ai)[end]
    @test t.order === o
    @test t.price == SimMode.DFT(99.0)
    @test t.date == tick.timestamp

    # queued sell limit fills when tick.price >= o.price
    s2 = _make_tick_strategy([_make_tick_ai("BTC/USDT"; ohlcv_price=50.0)])
    ai2 = first(s2.universe)
    reset!(s2)
    SimMode.Instruments.add!(SimMode.cash(ai2), 1.0)
    o2 = _make_sim_order(ai2, OT.LimitOrder{Sell}; price=100.0)
    @test !isnothing(o2)
    @test _queue_order!(s2, ai2, o2)
    @test SimMode.isqueued(o2, s2, ai2)
    tick2 = SimMode.TradeTick(_dt + SimMode.Millisecond(1), ai2, SimMode.DFT(101.0), SimMode.DFT(1.0))
    SimMode.update!(s2, tick2, SimMode.UpdateOrdersTick())
    @test SimMode.isfilled(ai2, o2)
    @test SimMode.OrderTypes.trades(ai2)[end].price == SimMode.DFT(101.0)

    # non-triggered GTC limit stays queued
    s3 = _make_tick_strategy([_make_tick_ai("BTC/USDT")])
    ai3 = first(s3.universe)
    reset!(s3)
    o3 = _make_sim_order(ai3, OT.LimitOrder{Buy}; price=100.0)
    @test !isnothing(o3)
    @test _queue_order!(s3, ai3, o3)
    tick3 = SimMode.TradeTick(_dt + SimMode.Millisecond(1), ai3, SimMode.DFT(101.0), SimMode.DFT(1.0))
    SimMode.update!(s3, tick3, SimMode.UpdateOrdersTick())
    @test SimMode.isqueued(o3, s3, ai3)
    @test !SimMode.isfilled(ai3, o3)

    # non-triggered FOK limit is canceled (queued directly, no creation-time trigger)
    s4 = _make_tick_strategy([_make_tick_ai("BTC/USDT")])
    ai4 = first(s4.universe)
    reset!(s4)
    ofok = _make_sim_order(ai4, OT.FOKOrder{Buy}; price=100.0)
    @test !isnothing(ofok)
    @test _queue_order!(s4, ai4, ofok)
    @test SimMode.isqueued(ofok, s4, ai4)
    tick4 = SimMode.TradeTick(_dt + SimMode.Millisecond(1), ai4, SimMode.DFT(101.0), SimMode.DFT(1.0))
    SimMode.update!(s4, tick4, SimMode.UpdateOrdersTick())
    @test !SimMode.isqueued(ofok, s4, ai4)
    @test !SimMode.isfilled(ai4, ofok)
end

@testset "tick price plumbing (limit/market/slippage)" begin
    ai = _make_tick_ai("BTC/USDT")
    s = _make_tick_strategy([ai])
    reset!(s)
    o = _limit_buy(p=100.0, a=1.0)
    tick = SimMode.TradeTick(_dt + SimMode.Millisecond(1), ai, SimMode.DFT(88.0), SimMode.DFT(1.0))

    # priceat: tick price for the current tick's asset, openat otherwise
    s.attrs[:sim_current_tick] = tick
    @test SimMode.priceat(s, OT.MarketOrder{Buy}, ai, _dt) == SimMode.DFT(88.0)
    delete!(s.attrs, :sim_current_tick)
    @test SimMode.priceat(s, OT.MarketOrder{Buy}, ai, _dt) == SimMode.DFT(50000.0)  # openat fallback

    # with_slippage short-circuits in tick mode
    s.attrs[:sim_tick_mode] = true
    @test SimMode.Executors.with_slippage(
        s, o, ai; date=_dt, price=SimMode.DFT(88.0), actual_amount=SimMode.DFT(1.0)
    ) == SimMode.DFT(88.0)
    delete!(s.attrs, :sim_tick_mode)
end

@testset "tick backtest e2e (SimMode/backtest.jl)" begin
    TickStrat.reset!()
    ai_btc = _make_tick_ai("BTC/USDT"; tick_df=_make_ticks(100; price0=100.0))
    ai_eth = _make_tick_ai("ETH/USDT"; tick_df=_make_ticks(100; price0=200.0))
    s = _make_tick_strategy([ai_btc, ai_eth])
    r = SimMode.TradeTickRange(s)
    @test length(r) == 200
    ctx = SimMode.TickContext(SimMode.Sim(), r)
    @test SimMode.execmode(ctx) == SimMode.Sim
    SimMode.start!(s, ctx)

    # every tick visited (zero-period warmup skips nothing)
    @test TickStrat.seen[] == 200
    @test TickStrat.seen_btc[] == 100
    # buy filled at the exact 5th BTC tick price with no slippage
    @test TickStrat.buy_price[] == SimMode.DFT(105.0)
    tr = SimMode.OrderTypes.trades(ai_btc)
    @test length(tr) == 1
    @test tr[1].price == TickStrat.buy_price[]
    @test tr[1].price == SimMode.DFT(105.0)
    # tick-mode flags cleaned up
    @test !haskey(s.attrs, :sim_tick_mode)
    @test !haskey(s.attrs, :sim_current_tick)
end

end  # @testset SimMode

end  # module Runtests
