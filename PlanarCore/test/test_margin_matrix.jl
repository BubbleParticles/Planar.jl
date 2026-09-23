using Test
using PlanarCore
using PlanarCore.Misc: Sim, Paper, Live, Isolated, IsolatedHedged, Cross, CrossHedged, NoMargin, DFT, Hedged, MarginMode
using PlanarCore.Strategies: Strategy
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
using PlanarCore.Executors: iscommittable
using PlanarCore.Executors: committed as exe_committed
using PlanarCore.ExchangeTypes.CcxtGateway.Rest
using Dates: DateTime, Minute


# Reuse mock from hedged_margin.jl style
function _make_exchange_matrix(name::Symbol; has_leverage=true, has_posmode=true, has_margin=true)
    hasd = Dict{Symbol,Any}(
        :fetchTicker => true,
        :fetchBalance => true,
        :setLeverage => has_leverage,
        :setMarginMode => has_margin,
        :setPositionMode => has_posmode,
    )
    CcxtExchange{ExchangeID{name}}(
        ExchangeID{name}(),
        string(name),
        "",
        OrderedSet{String}(["1m"]),
        Dict{String,Dict{String,Any}}(
            "BTC/USDT:USDT" => Dict{String,Any}(
                "id" => "BTC/USDT:USDT",
                "base" => "BTC",
                "quote" => "USDT",
                "type" => "future",
                "active" => true,
                "spot" => false,
                "linear" => true,
                "precision" => Dict{String,Any}("amount" => 8, "price" => 2),
                "limits" => Dict{String,Any}(
                    "amount" => Dict{String,Any}("min" => 1e-6, "max" => 1e8),
                    "price" => Dict{String,Any}("min" => 0.01, "max" => 1e6),
                    "cost" => Dict{String,Any}("min" => 1.0, "max" => 1e8),
                ),
                "taker" => 0.001,
                "maker" => 0.001,
            ),
        ),
        Set{Symbol}([:future]),
        Dict{Symbol,Any}(:taker => 0.001, :maker => 0.001),
        hasd,
        ExcPrecisionMode(2),
        nothing,
        [:fetchTicker],
        Dict{String,Any}(),
    )
end

function _make_instance_matrix(margin, exc)
    a = parse(Derivative, "BTC/USDT:USDT")
    df = DataFrame(
        timestamp=[DateTime(2024, 1, 1), DateTime(2024, 1, 1, 0, 1), DateTime(2024, 1, 1, 0, 2), DateTime(2024, 1, 1, 0, 3)],
        open=[50000.0, 50001.0, 50002.0, 50003.0],
        high=[50005.0, 50006.0, 50007.0, 50008.0],
        low=[49995.0, 49996.0, 49997.0, 49998.0],
        close=[50000.0, 50001.0, 50002.0, 50003.0],
        volume=[100.0, 100.0, 100.0, 100.0],
    )
    data = SortedDict{TimeFrame,DataFrame}(TimeFrame("1m") => df)
    limits = (leverage=(; min=1.0, max=10.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8))
    precision = (amount=1e-8, price=1e-8)
    fees = (taker=0.001, maker=0.001, min=0.001, max=0.001)
    InstrumentInstance(a, data, exc, margin; limits=limits, precision=precision, fees=fees)
end
# Live Strategy construction hits the gateway (setMarginMode/setPositionMode).
# Mock those endpoints so Live cells construct for real instead of skipping.
function _with_live_margin_mock(f)
    prev_post = Rest._http_post[]
    prev_get = Rest._http_get[]
    prev_init = Rest._gateway_initialized[]
    Rest._gateway_initialized[] = true
    mock_post = (url; headers=[], body=nothing, kwargs...) -> begin
        if occursin("/setMarginMode", url) ||
           occursin("/setPositionMode", url) ||
           occursin("/setLeverage", url)
            return Rest.HTTP.Response(
                200, Rest.JSON3.write(Dict("result" => true, "error" => nothing, "error_code" => nothing))
            )
        elseif occursin(r"/exchanges/[^/]+/start", url)
            return Rest.HTTP.Response(
                200, Rest.JSON3.write(Dict("result" => "started", "error" => nothing, "error_code" => nothing))
            )
        elseif occursin("/exchanges/", url)
            # Exchange info/has/markets/urls/fees lookups during Live construction:
            # return a benign payload instead of delegating to prev_post, which
            # may be real HTTP (Ccxt suites restore to HTTP.post) → 404.
            return Rest.HTTP.Response(
                200, Rest.JSON3.write(Dict("result" => Dict{String,Any}(), "error" => nothing, "error_code" => nothing))
            )
        end
        return prev_post(url; headers=headers, body=body, kwargs...)
    end
    Rest.set_http_post!(mock_post)
    try
        f()
    finally
        Rest.set_http_post!(prev_post)
        Rest.set_http_get!(prev_get)
        Rest._gateway_initialized[] = prev_init
    end
end

@testset "Margin × Hedged × ExecMode matrix (15 cells)" begin
    _with_live_margin_mock() do
        margins = (NoMargin(), Isolated(), IsolatedHedged(), Cross(), CrossHedged())
        modes = (Sim(), Paper(), Live())
        for margin in margins, mode in modes
            label = "$(typeof(margin).name.name)/$(typeof(mode).name.name)"
            @testset "$label" begin
                eid_sym = Symbol("t_$(typeof(mode).name.name)_$(typeof(margin).name.name)")
                exc = _make_exchange_matrix(eid_sym)
                # seed tier cache
                tier = LeverageTier(Dict("tier"=>1,"notionalFloor"=>0.0,"notionalCap"=>1e6,"maxLeverage"=>10.0,"maintenanceMarginRate"=>0.01,"maintAmtNotional"=>0.0,"minNotional"=>0.0))
                _TIER_CACHES[(Symbol(eid_sym), "BTC/USDT:USDT")] = ([tier], time())
                uni = InstrumentCollection(["BTC/USDT:USDT"]; exc=exc, margin=margin, load_data=false)
                cfg = PlanarCore.Misc.Config(; qc=:USDT, initial_cash=100000.0)
                # Live gateway endpoints are mocked above: construction must succeed
                # for real in all 15 cells (no skip/continue).
                s = Strategy(Main, mode, margin, TimeFrame("1m"), exc, uni; config=cfg)
                @test s isa Strategy
                ii = _make_instance_matrix(margin, exc)
                if margin isa NoMargin
                    @test ii isa PlanarCore.Instances.NoMarginInstance
                elseif margin isa Union{IsolatedHedged, CrossHedged}
                    @test ii isa PlanarCore.Instances.HedgedInstance
                else
                    @test ii isa PlanarCore.Instances.MarginInstance
                    @test !(ii isa PlanarCore.Instances.HedgedInstance)
                end
                # Hedged flag propagates from margin to instance
                @test ishedged(ii) == (margin isa Union{IsolatedHedged, CrossHedged})
                # Strategy marginmode matches (instance compare, not typeof)
                @test PlanarCore.Misc.marginmode(s) == margin
            end
        end
    end
end

@testset "Cash buckets: Increase→strategy, Reduce→position" begin
    exc = _make_exchange_matrix(:bucket_test)
    tier = LeverageTier(Dict("tier"=>1,"notionalFloor"=>0.0,"notionalCap"=>1e6,"maxLeverage"=>10.0,"maintenanceMarginRate"=>0.01,"maintAmtNotional"=>0.0,"minNotional"=>0.0))
    _TIER_CACHES[(:bucket_test, "BTC/USDT:USDT")] = ([tier], time())
    uni = InstrumentCollection(["BTC/USDT:USDT"]; exc=exc, margin=Isolated(), load_data=false)
    cfg = PlanarCore.Misc.Config(; qc=:USDT, initial_cash=100000.0)
    s = Strategy(Main, Sim(), Isolated(), TimeFrame("1m"), exc, uni; config=cfg)
    # Use the universe member so inuniverse(ii, s) holds.
    ii = first(s.universe)
    # Fund the long position bucket; strategy bucket starts at 100k.
    po = position(ii, Long())
    cash!(cash(po), 500.0)
    # Increase reads the strategy bucket: small commit passes on funded strategy.
    @test iscommittable(s, BuyOrder, Ref(10.0), ii)
    # Reduce reads the position bucket: small commit passes on funded position.
    @test iscommittable(s, SellOrder, Ref(10.0), ii)
    # Oversized commits are rejected per-bucket.
    @test !iscommittable(s, BuyOrder, Ref(1_000_000_000.0), ii)
    @test !iscommittable(s, SellOrder, Ref(1_000_000_000.0), ii)
    # Drain the strategy bucket: Increase blocks, Reduce (position bucket) still passes.
    # This is the regression guard for the old `st.freecash(ii, ...)` bug where
    # Reduce incorrectly read the strategy bucket.
    cash!(s.cash, 100.0)
    @test !iscommittable(s, BuyOrder, Ref(50_000.0), ii)
    @test iscommittable(s, SellOrder, Ref(10.0), ii)
end
@testset "Margin-mode setting authoritative" begin
    exc = _make_exchange_matrix(:auth_test)
    tier = LeverageTier(Dict("tier"=>1,"notionalFloor"=>0.0,"notionalCap"=>1e6,"maxLeverage"=>10.0,"maintenanceMarginRate"=>0.01,"maintAmtNotional"=>0.0,"minNotional"=>0.0))
    _TIER_CACHES[(:auth_test, "BTC/USDT:USDT")] = ([tier], time())
    prev_post = Rest._http_post[]
    prev_init = Rest._gateway_initialized[]
    Rest._gateway_initialized[] = true
    sent_hedged = Any[]
    n_posts = Ref(0)
    mock_post = (url; headers=[], body=nothing, kwargs...) -> begin
        n_posts[] += 1
        if occursin("/setPositionMode", url)
            raw = isnothing(body) ? get(kwargs, :body, nothing) : body
            hv = missing
            if raw isa AbstractDict
                hv = get(raw, "hedged", get(raw, :hedged, missing))
            elseif !isnothing(raw)
                parsed = try
                    Rest.JSON3.read(string(raw), Dict{String,Any})
                catch
                    Dict{String,Any}()
                end
                hv = get(parsed, "hedged", missing)
            end
            push!(sent_hedged, hv)
        end
        return Rest.HTTP.Response(
            200, Rest.JSON3.write(Dict("result" => true, "error" => nothing, "error_code" => nothing))
        )
    end
    Rest.set_http_post!(mock_post)
    try
        # Hedged mode must send hedged=true derived from the MarginMode itself.
        @test marginmode!(exc, IsolatedHedged(), "BTC/USDT:USDT")
        @test !isempty(sent_hedged) && last(sent_hedged) === true
        empty!(sent_hedged)
        # Non-hedged mode must send hedged=false.
        @test marginmode!(exc, Cross(), "BTC/USDT:USDT")
        @test !isempty(sent_hedged) && last(sent_hedged) === false
        # NoMargin is a local no-op: returns true without gateway traffic.
        n_before = n_posts[]
        @test marginmode!(exc, NoMargin(), "BTC/USDT:USDT")
        @test n_posts[] == n_before
    finally
        Rest.set_http_post!(prev_post)
        Rest._gateway_initialized[] = prev_init
    end
end

@testset "Hedged instance type discipline" begin
    exc = _make_exchange_matrix(:hedgetype_test)
    tier = LeverageTier(Dict("tier"=>1,"notionalFloor"=>0.0,"notionalCap"=>1e6,"maxLeverage"=>10.0,"maintenanceMarginRate"=>0.01,"maintAmtNotional"=>0.0,"minNotional"=>0.0))
    _TIER_CACHES[(:hedgetype_test, "BTC/USDT:USDT")] = ([tier], time())
    ii_h = _make_instance_matrix(IsolatedHedged(), exc)
    ii_s = _make_instance_matrix(Isolated(), exc)
    # Hedged instances carry both sides and stay a MarginInstance subtype.
    @test ii_h isa PlanarCore.Instances.HedgedInstance
    @test ii_h isa PlanarCore.Instances.MarginInstance
    @test ishedged(ii_h)
    @test !isnothing(position(ii_h, Long())) && !isnothing(position(ii_h, Short()))
    # Single-way instances are margin but not hedged.
    @test ii_s isa PlanarCore.Instances.MarginInstance
    @test !(ii_s isa PlanarCore.Instances.HedgedInstance)
    @test !ishedged(ii_s)
end

using PlanarCore.Misc: Config
using PlanarCore.Strategies: strategy!
using PlanarCore.Instances:
    leverage, leverage!, maintenance!, margin!, notional!, entryprice!, liqprice!, status!, PositionOpen, CrossMargin, value, cash!
using PlanarCore.SimMode: isliquidatable, maybe_liquidate!
import PlanarCore.SimMode: _cross_account_covered

module _MMProbeIso
using PlanarCore.Strategies: Strategy
using PlanarCore.Misc: Sim, Isolated
using PlanarCore.ExchangeTypes: ExchangeID
const S = Strategy{Sim,:MMProbeIso,ExchangeID{:binance},Isolated,:USDT}
end
module _MMProbeCrossSC
using PlanarCore.Strategies: Strategy
using PlanarCore.Misc: Sim, Cross
using PlanarCore.ExchangeTypes: ExchangeID
const SC{E} = Strategy{Sim,:MMProbeCross,E,Cross,:USDT}
end

@testset "Strategy-defined margin resolution" begin
    @test PlanarCore.Strategies._defined_marginmode(_MMProbeIso) == Isolated()
    @test PlanarCore.Strategies._defined_marginmode(_MMProbeCrossSC) == Cross()
end

@testset "Config/strategy margin mismatch is an error" begin
    cfg = Config(; margin=Cross(), mode=Sim(), exchange=:binance)
    @test_throws ErrorException strategy!(_MMProbeIso, cfg)
end

@testset "Cross max leverage is tier-bounded" begin
    exc = _make_exchange_matrix(:crossmax_test)
    tier = LeverageTier(Dict("tier"=>1,"notionalFloor"=>0.0,"notionalCap"=>1e6,"maxLeverage"=>10.0,"maintenanceMarginRate"=>0.01,"maintAmtNotional"=>0.0,"minNotional"=>0.0))
    _TIER_CACHES[(:crossmax_test, "BTC/USDT:USDT")] = ([tier], time())
    ii = _make_instance_matrix(Cross(), exc)
    leverage!(ii, Long(), Val(:max))
    # A 1e10 sentinel would zero the margin and push liqprice past entry
    @test leverage(ii, Long()) == 10.0
    @test leverage(ii, Long()) < 1e9
end

@testset "Cross liquidation is account-level" begin
    exc = _make_exchange_matrix(:crossliq_test)
    tier = LeverageTier(Dict("tier"=>1,"notionalFloor"=>0.0,"notionalCap"=>1e6,"maxLeverage"=>10.0,"maintenanceMarginRate"=>0.01,"maintAmtNotional"=>0.0,"minNotional"=>0.0))
    _TIER_CACHES[(:crossliq_test, "BTC/USDT:USDT")] = ([tier], time())
    uni = InstrumentCollection(["BTC/USDT:USDT"]; exc=exc, margin=Cross(), load_data=false)
    cfg = Config(; qc=:USDT, initial_cash=100000.0)
    s = Strategy(Main, Sim(), Cross(), TimeFrame("1m"), exc, uni; config=cfg)
    # Crash candles: 50k -> 40k, below the standalone long liq (45.5k)
    df = DataFrame(
        timestamp=[DateTime(2024, 1, 1) + Minute(i) for i in 0:3],
        open=[50000.0, 50000.0, 40000.0, 40000.0],
        high=[50005.0, 50005.0, 40005.0, 40005.0],
        low=[49995.0, 39900.0, 39900.0, 39990.0],
        close=[50000.0, 40000.0, 40000.0, 40000.0],
        volume=[100.0, 100.0, 100.0, 100.0],
    )
    a = parse(Derivative, "BTC/USDT:USDT")
    data = SortedDict{TimeFrame,DataFrame}(TimeFrame("1m") => df)
    limits = (leverage=(; min=1.0, max=10.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8))
    precision = (amount=1e-8, price=1e-8)
    fees = (taker=0.001, maker=0.001, min=0.001, max=0.001)
    ii = InstrumentInstance(a, data, exc, Cross(); limits=limits, precision=precision, fees=fees)
    po = position(ii, Long())
    cash!(cash(po), 1.0)
    entryprice!(po, 50000.0)
    notional!(po, 50000.0)
    leverage!(po, 10.0)
    margin!(po)
    maintenance!(po, 500.0)
    liqprice!(po, 45500.0)
    status!(ii, Long(), PositionOpen())
    push!(s.holdings, ii)
    date = DateTime(2024, 1, 1, 0, 1)
    # Standalone the position is liquidatable (39900 <= 45500) ...
    @test isliquidatable(s, ii, Long(), date)
    # ... but the funded account absorbs it: no liquidation
    @test _cross_account_covered(s, date)
    maybe_liquidate!(s, ii, date)
    @test isopen(ii, Long())
    # A drained account is under water: falls back to per-position liquidation
    cash!(s.cash, 100.0)
    @test !_cross_account_covered(s, date)
end

@testset "CrossHedged liquidation is account-level" begin
    exc = _make_exchange_matrix(:crosshedged_liq_test)
    tier = LeverageTier(Dict("tier"=>1,"notionalFloor"=>0.0,"notionalCap"=>1e6,"maxLeverage"=>10.0,"maintenanceMarginRate"=>0.01,"maintAmtNotional"=>0.0,"minNotional"=>0.0))
    _TIER_CACHES[(:crosshedged_liq_test, "BTC/USDT:USDT")] = ([tier], time())
    uni = InstrumentCollection(["BTC/USDT:USDT"]; exc=exc, margin=CrossHedged(), load_data=false)
    cfg = Config(; qc=:USDT, initial_cash=100000.0)
    s = Strategy(Main, Sim(), CrossHedged(), TimeFrame("1m"), exc, uni; config=cfg)
    # Crash candles: 50k -> 40k, below the standalone long liq (45.5k)
    df = DataFrame(
        timestamp=[DateTime(2024, 1, 1) + Minute(i) for i in 0:3],
        open=[50000.0, 50000.0, 40000.0, 40000.0],
        high=[50005.0, 50005.0, 40005.0, 40005.0],
        low=[49995.0, 39900.0, 39900.0, 39990.0],
        close=[50000.0, 40000.0, 40000.0, 40000.0],
        volume=[100.0, 100.0, 100.0, 100.0],
    )
    a = parse(Derivative, "BTC/USDT:USDT")
    data = SortedDict{TimeFrame,DataFrame}(TimeFrame("1m") => df)
    limits = (leverage=(; min=1.0, max=10.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8))
    precision = (amount=1e-8, price=1e-8)
    fees = (taker=0.001, maker=0.001, min=0.001, max=0.001)
    ii = InstrumentInstance(a, data, exc, CrossHedged(); limits=limits, precision=precision, fees=fees)
    po_long = position(ii, Long())
    cash!(cash(po_long), 1.0)
    entryprice!(po_long, 50000.0)
    notional!(po_long, 50000.0)
    leverage!(po_long, 10.0)
    margin!(po_long)
    maintenance!(po_long, 500.0)
    liqprice!(po_long, 45500.0)
    status!(ii, Long(), PositionOpen())
    # Also open a short position (hedged mode allows both)
    po_short = position(ii, Short())
    cash!(cash(po_short), 0.5)
    entryprice!(po_short, 50000.0)
    notional!(po_short, 25000.0)
    leverage!(po_short, 10.0)
    margin!(po_short)
    maintenance!(po_short, 250.0)
    liqprice!(po_short, 54500.0)  # Short liq above entry
    status!(ii, Short(), PositionOpen())
    push!(s.holdings, ii)
    date = DateTime(2024, 1, 1, 0, 1)
    # Long is liquidatable (39900 <= 45500) but funded account absorbs it
    @test isliquidatable(s, ii, Long(), date)
    @test _cross_account_covered(s, date)
    maybe_liquidate!(s, ii, date)
    @test isopen(ii, Long())  # Long should NOT be liquidated
    @test isopen(ii, Short())  # Short should still be open
    # A drained account is under water: falls back to per-position liquidation
    cash!(s.cash, 100.0)
    @test !_cross_account_covered(s, date)
end
@testset "Live liquidation throttle uses one clock read" begin
    using PlanarCore.SimMode: maybe_liquidate!
    using PlanarCore.Misc.TimeTicks
    exc = _make_exchange_matrix(:liveliq_test)
    tier = LeverageTier(Dict("tier"=>1,"notionalFloor"=>0.0,"notionalCap"=>1e6,"maxLeverage"=>10.0,"maintenanceMarginRate"=>0.01,"maintAmtNotional"=>0.0,"minNotional"=>0.0))
    _TIER_CACHES[(:liveliq_test, "BTC/USDT:USDT")] = ([tier], time())
    # A single read of the live clock must gate the throttle: two back-to-back
    # calls skip the second one, and the recorded stamp is a DateTime.
    _with_live_margin_mock() do
        uni = InstrumentCollection(["BTC/USDT:USDT"]; exc=exc, margin=Isolated(), load_data=false)
        cfg = Config(; qc=:USDT, initial_cash=100000.0)
        s = Strategy(Main, Live(), Isolated(), TimeFrame("1m"), exc, uni; config=cfg)
        ii = _make_instance_matrix(Isolated(), exc)
        date = DateTime(2024, 1, 1, 0, 6)
        maybe_liquidate!(s, ii, date)
        checks = s.attrs[:live_last_liq_check]
        @test haskey(checks, objectid(ii))
        @test checks[objectid(ii)] isa DateTime
        @test checks[objectid(ii)] <= TimeTicks.now()
        first_stamp = checks[objectid(ii)]
        maybe_liquidate!(s, ii, date)
        @test checks[objectid(ii)] == first_stamp
    end
end


@testset "IsolatedHedged liquidation is per-position" begin
    exc = _make_exchange_matrix(:isohedged_liq_test)
    tier = LeverageTier(Dict("tier"=>1,"notionalFloor"=>0.0,"notionalCap"=>1e6,"maxLeverage"=>10.0,"maintenanceMarginRate"=>0.01,"maintAmtNotional"=>0.0,"minNotional"=>0.0))
    _TIER_CACHES[(:isohedged_liq_test, "BTC/USDT:USDT")] = ([tier], time())
    uni = InstrumentCollection(["BTC/USDT:USDT"]; exc=exc, margin=IsolatedHedged(), load_data=false)
    cfg = Config(; qc=:USDT, initial_cash=100000.0)
    s = Strategy(Main, Sim(), IsolatedHedged(), TimeFrame("1m"), exc, uni; config=cfg)
    # Set SimMode slippage attrs needed for liquidation
    s.attrs[:sim_base_slippage] = Val(:spread)
    s.attrs[:sim_market_slippage] = Val(:skew)
    # Crash candles: 50k -> 40k, below the standalone long liq (45.5k)
    df = DataFrame(
        timestamp=[DateTime(2024, 1, 1) + Minute(i) for i in 0:3],
        open=[50000.0, 50000.0, 40000.0, 40000.0],
        high=[50005.0, 50005.0, 40005.0, 40005.0],
        low=[49995.0, 39900.0, 39900.0, 39990.0],
        close=[50000.0, 40000.0, 40000.0, 40000.0],
        volume=[100.0, 100.0, 100.0, 100.0],
    )
    a = parse(Derivative, "BTC/USDT:USDT")
    data = SortedDict{TimeFrame,DataFrame}(TimeFrame("1m") => df)
    limits = (leverage=(; min=1.0, max=10.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8))
    precision = (amount=1e-8, price=1e-8)
    fees = (taker=0.001, maker=0.001, min=0.001, max=0.001)
    ii = InstrumentInstance(a, data, exc, IsolatedHedged(); limits=limits, precision=precision, fees=fees)
    po_long = position(ii, Long())
    cash!(cash(po_long), 1.0)
    entryprice!(po_long, 50000.0)
    notional!(po_long, 50000.0)
    leverage!(po_long, 10.0)
    margin!(po_long)
    maintenance!(po_long, 500.0)
    liqprice!(po_long, 45500.0)
    status!(ii, Long(), PositionOpen())
    # Also open a short position (hedged mode allows both)
    po_short = position(ii, Short())
    cash!(cash(po_short), 0.5)
    entryprice!(po_short, 50000.0)
    notional!(po_short, 25000.0)
    leverage!(po_short, 10.0)
    margin!(po_short)
    maintenance!(po_short, 250.0)
    liqprice!(po_short, 54500.0)  # Short liq above entry
    status!(ii, Short(), PositionOpen())
    push!(s.holdings, ii)
    date = DateTime(2024, 1, 1, 0, 1)
    # IsolatedHedged: each position liquidates independently
    # Long is liquidatable (39900 <= 45500)
    @test isliquidatable(s, ii, Long(), date)
    # Short is NOT liquidatable (40000 < 54500)
    @test !isliquidatable(s, ii, Short(), date)
    maybe_liquidate!(s, ii, date)
    @test !isopen(ii, Long())  # Long should be liquidated
    @test isopen(ii, Short())  # Short should still be open
end

@testset "Margin hasorders covers all position/order-side legs" begin
    using PlanarCore.OrderTypes: Buy, Sell, MarketOrderType, Order
    using PlanarCore.Executors: hasorders, orders
    exc = _make_exchange_matrix(:hasorders_test)
    tier = LeverageTier(Dict("tier"=>1,"notionalFloor"=>0.0,"notionalCap"=>1e6,"maxLeverage"=>10.0,"maintenanceMarginRate"=>0.01,"maintAmtNotional"=>0.0,"minNotional"=>0.0))
    _TIER_CACHES[(:hasorders_test, "BTC/USDT:USDT")] = ([tier], time())
    uni = InstrumentCollection(["BTC/USDT:USDT"]; exc=exc, margin=IsolatedHedged(), load_data=false)
    cfg = Config(; qc=:USDT, initial_cash=100000.0)
    s = Strategy(Main, Sim(), IsolatedHedged(), TimeFrame("1m"), exc, uni; config=cfg)
    ii = _make_instance_matrix(IsolatedHedged(), exc)
    eid = exc.id
    # A Short-Sell (increase-short) order belongs to the Short position.
    o = Order(ii.asset, eid, Order{MarketOrderType{Sell}}, Short; price=50000.0, amount=1.0, date=DateTime(2024, 1, 1))
    push!(s, ii, o)
    # 4-arg order-side dispatch must see it (Short/Sell leg was missing).
    @test hasorders(s, ii, Short(), Sell)
    @test hasorders(s, ii, Short())
    @test !hasorders(s, ii, Short(), Buy)
    @test !hasorders(s, ii, Long(), Sell)
    @test !hasorders(s, ii, Long(), Buy)
    @test !isempty(collect(orders(s, ii, Short(), Sell)))
    @test isempty(collect(orders(s, ii, Short(), Buy)))
    # Long-Buy (increase-long) lands on the Long position.
    o2 = Order(ii.asset, eid, Order{MarketOrderType{Buy}}, Long; price=50000.0, amount=1.0, date=DateTime(2024, 1, 1))
    push!(s, ii, o2)
    @test hasorders(s, ii, Long(), Buy)
    @test hasorders(s, ii, Long())
    @test !isempty(collect(orders(s, ii, Long(), Buy)))
end

@testset "Binance sandbox marginmode! records mode locally" begin
    using PlanarCore.Exchanges: sandboxCache
    name = :binance
    exc = _make_exchange_matrix(name)
    # Take the Binance adhoc override's sandbox branch. `issandbox` caches
    # per ExchangeID, so seed it directly and clear it afterwards to avoid
    # cross-test leakage.
    sandboxCache[ExchangeID{name}()] = true
    try
        for (margin, expected) in (
            (Isolated(), "isolated"),
            (CrossHedged(), "cross"),
            (NoMargin(), "nomargin"),
        )
            @test marginmode!(exc, margin, "BTC/USDT:USDT")
            @test PlanarCore.Exchanges.marginmode(exc) == expected
        end
        @test_throws ErrorException marginmode!(exc, "bogus_mode", "BTC/USDT:USDT")
    finally
        delete!(sandboxCache, ExchangeID{name}())
    end
end

@testset "String marginmode! normalization + hedge flag" begin
    # The untyped string overload normalizes case/separators and hedged
    # suffixes, so "ISOLATED", "isolated-hedged" etc. behave canonically.
    prev_post = Rest._http_post[]
    prev_init = Rest._gateway_initialized[]
    Rest._gateway_initialized[] = true
    sent = Any[]
    mock_post = (url; headers=[], body=nothing, kwargs...) -> begin
        if occursin("/setPositionMode", url)
            raw = isnothing(body) ? get(kwargs, :body, nothing) : body
            hv = if raw isa AbstractDict
                get(raw, "hedged", get(raw, :hedged, missing))
            elseif !isnothing(raw)
                parsed = try
                    Rest.JSON3.read(string(raw), Dict{String,Any})
                catch
                    Dict{String,Any}()
                end
                get(parsed, "hedged", missing)
            else
                missing
            end
            push!(sent, hv)
        end
        return Rest.HTTP.Response(
            200, Rest.JSON3.write(Dict("result" => true, "error" => nothing, "error_code" => nothing))
        )
    end
    Rest.set_http_post!(mock_post)
    try
        exc = _make_exchange_matrix(:strnorm_test)
        @test marginmode!(exc, "ISOLATED", "BTC/USDT:USDT")
        @test PlanarCore.Exchanges.marginmode(exc) == "isolated"
        @test !isempty(sent) && last(sent) === false
        empty!(sent)
        @test marginmode!(exc, "isolated-hedged", "BTC/USDT:USDT")
        @test PlanarCore.Exchanges.marginmode(exc) == "isolated"
        @test !isempty(sent) && last(sent) === true
        empty!(sent)
        @test marginmode!(exc, "Cross Hedged", "BTC/USDT:USDT")
        @test PlanarCore.Exchanges.marginmode(exc) == "cross"
        @test !isempty(sent) && last(sent) === true
        @test_throws ErrorException marginmode!(exc, "bogus_mode", "BTC/USDT:USDT")
    finally
        Rest.set_http_post!(prev_post)
        Rest._gateway_initialized[] = prev_init
    end
end

@testset "Binance sandbox normalization + position mode" begin
    # Sandbox records the canonical base mode and the hedge flag, so
    # mixed-case / hedged-suffixed strings stay consistent with live state.
    using PlanarCore.Exchanges: sandboxCache
    name = :binance
    exc = _make_exchange_matrix(name)
    sandboxCache[ExchangeID{name}()] = true
    try
        @test marginmode!(exc, "ISOLATED", "BTC/USDT:USDT")
        @test PlanarCore.Exchanges.marginmode(exc) == "isolated"
        @test exc.options["defaultPositionMode"] == "oneway"
        @test marginmode!(exc, "isolated-hedged", "BTC/USDT:USDT")
        @test PlanarCore.Exchanges.marginmode(exc) == "isolated"
        @test exc.options["defaultPositionMode"] == "hedge"
        @test marginmode!(exc, Cross(), "BTC/USDT:USDT")
        @test exc.options["defaultPositionMode"] == "oneway"
        @test marginmode!(exc, CrossHedged(), "BTC/USDT:USDT")
        @test exc.options["defaultPositionMode"] == "hedge"
    finally
        delete!(sandboxCache, ExchangeID{name}())
    end
end
@testset "Binance non-sandbox string marginmode! forwards hedge flag" begin
    # The Binance adhoc override's non-sandbox branch falls through to the
    # generic path (`invoke(marginmode!, Tuple{Exchange,<:Any,<:Any}, ...)`),
    # which calls `dosetpositionmode` → `call_exchange(..., "setPositionMode")`.
    # `call_exchange` unwraps the GatewayResponse and returns the raw `result`
    # (a Bool for these methods). The Binance-specific `resptobool` did not
    # handle a direct Bool (only the generic path did), so `dosetpositionmode`
    # always failed on live — `marginmode!` returned false and the exchange
    # never switched to hedge mode. Guard: the Binance `resptobool` must
    # recognize a direct Bool the same way the generic path does.
    prev_post = Rest._http_post[]
    prev_init = Rest._gateway_initialized[]
    Rest._gateway_initialized[] = true
    sent = Any[]
    mock_post = (url; headers=[], body=nothing, kwargs...) -> begin
        if occursin("/setPositionMode", url)
            raw = isnothing(body) ? get(kwargs, :body, nothing) : body
            hv = if raw isa AbstractDict
                get(raw, "hedged", get(raw, :hedged, missing))
            elseif !isnothing(raw)
                parsed = try
                    Rest.JSON3.read(string(raw), Dict{String,Any})
                catch
                    Dict{String,Any}()
                end
                get(parsed, "hedged", missing)
            else
                missing
            end
            push!(sent, hv)
        end
        return Rest.HTTP.Response(
            200, Rest.JSON3.write(Dict("result" => true, "error" => nothing, "error_code" => nothing))
        )
    end
    Rest.set_http_post!(mock_post)
    name = :binance
    exc = _make_exchange_matrix(name)
    # Seed sandboxCache so issandbox(exc) returns false WITHOUT a network
    # call. Without this, issandbox fetches /exchanges/binance/urls via GET
    # (not mocked here), hits the real gateway, and — because Binance
    # exposes testnet URLs — returns true, taking the sandbox branch that
    # skips the gateway entirely and leaves `sent` empty.
    sandboxCache[ExchangeID{name}()] = false
    try
        @test marginmode!(exc, "ISOLATED", "BTC/USDT:USDT")
        @test PlanarCore.Exchanges.marginmode(exc) == "isolated"
        @test !isempty(sent) && last(sent) === false
        empty!(sent)
        @test marginmode!(exc, "isolated-hedged", "BTC/USDT:USDT")
        @test PlanarCore.Exchanges.marginmode(exc) == "isolated"
        @test !isempty(sent) && last(sent) === true
        empty!(sent)
        @test marginmode!(exc, "Cross Hedged", "BTC/USDT:USDT")
        @test PlanarCore.Exchanges.marginmode(exc) == "cross"
        @test !isempty(sent) && last(sent) === true
        @test_throws ErrorException marginmode!(exc, "bogus_mode", "BTC/USDT:USDT")
    finally
        Rest.set_http_post!(prev_post)
        Rest._gateway_initialized[] = prev_init
        delete!(sandboxCache, ExchangeID{name}())
    end
end


@testset "NoMargin dust Type-overload (Sim force-exit path)" begin
    using PlanarCore.Instances: isdust
    using PlanarCore.OrderTypes: MarketOrder, Buy, Sell
    exc = _make_exchange_matrix(:nomargin_dust_test)
    tier = LeverageTier(Dict("tier"=>1,"notionalFloor"=>0.0,"notionalCap"=>1e6,"maxLeverage"=>10.0,"maintenanceMarginRate"=>0.01,"maintAmtNotional"=>0.0,"minNotional"=>0.0))
    _TIER_CACHES[(:nomargin_dust_test, "BTC/USDT:USDT")] = ([tier], time())
    ii = _make_instance_matrix(NoMargin(), exc)
    # Spot dust is side-less: the (ii, OrderType, price) overload must not
    # `invoke` the MarginInstance/PositionSide method (MethodError on NoMargin).
    @test isdust(ii, MarketOrder{Buy}, 50000.0) isa Bool
    @test isdust(ii, MarketOrder{Sell}, 50000.0) == isdust(ii, 50000.0)
end

@testset "NoMargin leverage! is a no-op (ByPos overload)" begin
    using PlanarCore.Instances: NoMarginInstance
    exc = _make_exchange_matrix(:nomargin_lev_test)
    tier = LeverageTier(Dict("tier"=>1,"notionalFloor"=>0.0,"notionalCap"=>1e6,"maxLeverage"=>10.0,"maintenanceMarginRate"=>0.01,"maintAmtNotional"=>0.0,"minNotional"=>0.0))
    _TIER_CACHES[(:nomargin_lev_test, "BTC/USDT:USDT")] = ([tier], time())
    ii = _make_instance_matrix(NoMargin(), exc)
    @test ii isa NoMarginInstance
    # Spot has no position object: the generic `leverage!(ii, v, p)` must not
    # fall through to `leverage!(position(ii, p), v)` (== leverage!(nothing, v)).
    @test leverage!(ii, 100.0, Long()) === 100.0
    @test leverage!(ii, 100.0, Short()) === 100.0
    # NoMargin leverage is always 1.0, unaffected by the no-op setter.
    @test leverage(ii, Long()) == 1.0
    @test leverage(ii, Short()) == 1.0
end

@testset "Cross liquidation via candle path is account-level" begin
    # Regression: `_date_position!` (the candle path, shared by Sim+Paper via
    # `position!(s, ii, date, pos)`) used to call `liquidate!` directly,
    # bypassing the cross-margin `_cross_account_covered` guard that
    # `_maybe_liquidate_positions!` applies. A cross position breaching its
    # standalone liq price while the funded account absorbs it would be
    # liquidated anyway — the account-level semantics only held on the
    # trade path.
    exc = _make_exchange_matrix(:crossliq_candle_test)
    tier = LeverageTier(Dict("tier"=>1,"notionalFloor"=>0.0,"notionalCap"=>1e6,"maxLeverage"=>10.0,"maintenanceMarginRate"=>0.01,"maintAmtNotional"=>0.0,"minNotional"=>0.0))
    _TIER_CACHES[(:crossliq_candle_test, "BTC/USDT:USDT")] = ([tier], time())
    uni = InstrumentCollection(["BTC/USDT:USDT"]; exc=exc, margin=Cross(), load_data=false)
    cfg = Config(; qc=:USDT, initial_cash=100000.0)
    s = Strategy(Main, Sim(), Cross(), TimeFrame("1m"), exc, uni; config=cfg)
    # Set SimMode slippage attrs needed for liquidation (same as IsolatedHedged test)
    s.attrs[:sim_base_slippage] = Val(:spread)
    s.attrs[:sim_market_slippage] = Val(:skew)
    df = DataFrame(
        timestamp=[DateTime(2024, 1, 1) + Minute(i) for i in 0:3],
        open=[50000.0, 50000.0, 40000.0, 40000.0],
        high=[50005.0, 50005.0, 40005.0, 40005.0],
        low=[49995.0, 39900.0, 39900.0, 39990.0],
        close=[50000.0, 40000.0, 40000.0, 40000.0],
        volume=[100.0, 100.0, 100.0, 100.0],
    )
    a = parse(Derivative, "BTC/USDT:USDT")
    data = SortedDict{TimeFrame,DataFrame}(TimeFrame("1m") => df)
    limits = (leverage=(; min=1.0, max=10.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8))
    precision = (amount=1e-8, price=1e-8)
    fees = (taker=0.001, maker=0.001, min=0.001, max=0.001)
    ii = InstrumentInstance(a, data, exc, Cross(); limits=limits, precision=precision, fees=fees)
    po = position(ii, Long())
    cash!(cash(po), 1.0)
    entryprice!(po, 50000.0)
    notional!(po, 50000.0)
    leverage!(po, 10.0)
    margin!(po)
    maintenance!(po, 500.0)
    liqprice!(po, 45500.0)
    status!(ii, Long(), PositionOpen())
    push!(s.holdings, ii)
    date = DateTime(2024, 1, 1, 0, 1)
    # Standalone the position is liquidatable (39900 <= 45500) ...
    @test isliquidatable(s, ii, Long(), date)
    # ... but the funded account absorbs it: the candle path must NOT liquidate
    @test _cross_account_covered(s, date)
    position!(s, ii, date, po)
    @test isopen(ii, Long())  # candle path preserved account-level semantics
    # A drained account is under water: falls back to per-position liquidation
    cash!(s.cash, 100.0)
    @test !_cross_account_covered(s, date)
    position!(s, ii, date, po)
    @test !isopen(ii, Long())  # drained account: candle path liquidates
end
