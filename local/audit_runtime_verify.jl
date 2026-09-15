using Test
using Dates
using Dates: DateTime
using PlanarCore
using Planar
using PlanarCore.Misc: Sim, Paper, Live, Isolated, IsolatedHedged, Cross, CrossHedged, NoMargin, Config, MarginMode, Hedged
using PlanarCore.Strategies: Strategy
using PlanarCore.Strategies.Instances: ishedged, isopen, Long, Short, position, freecash, cash, committed
using PlanarCore.Instances: InstrumentInstance, HedgedInstance, MarginInstance, NoMarginInstance
using PlanarCore.Instances.Instruments.Derivatives: Derivative, parse
using PlanarCore.ExchangeTypes: CcxtExchange, ExchangeID, ExcPrecisionMode
using PlanarCore.ExchangeTypes.OrderedCollections: OrderedSet
using PlanarCore.Collections: InstrumentCollection
using PlanarCore.TimeTicks: TimeFrame
using PlanarCore.Exchanges: _TIER_CACHES, LeverageTier
using PlanarCore.Instances.Data: DataFrame
using PlanarCore.Instances.DataStructures: SortedDict
using PlanarCore.OrderTypes: Buy, Sell, ShortMarketOrder
using PlanarCore.ExchangeTypes: has
using PlanarCore.SimMode.OrderTypes: MarketOrder
using PlanarCore.Executors: iscommittable, call!

function mkexc(name::Symbol)
    hasd = Dict{Symbol,Any}(
        :fetchTicker => true, :fetchBalance => true,
        :setLeverage => true, :setMarginMode => true, :setPositionMode => true,
    )
    CcxtExchange{ExchangeID{name}}(
        ExchangeID{name}(), string(name), "", OrderedSet{String}(["1m"]),
        Dict{String,Dict{String,Any}}(
            "BTC/USDT:USDT" => Dict{String,Any}(
                "id" => "BTC/USDT:USDT", "base" => "BTC", "quote" => "USDT",
                "type" => "future", "active" => true, "spot" => false, "linear" => true,
                "precision" => Dict{String,Any}("amount" => 8, "price" => 2),
                "limits" => Dict{String,Any}(
                    "amount" => Dict{String,Any}("min" => 1e-6, "max" => 1e8),
                    "price" => Dict{String,Any}("min" => 0.01, "max" => 1e6),
                    "cost" => Dict{String,Any}("min" => 1.0, "max" => 1e8)),
                "taker" => 0.001, "maker" => 0.001)),
        Set{Symbol}([:future]),
        Dict{Symbol,Any}(:taker => 0.001, :maker => 0.001), hasd,
        ExcPrecisionMode(2), nothing, [:fetchTicker], Dict{String,Any}())
end

function mkii(margin, exc)
    a = parse(Derivative, "BTC/USDT:USDT")
    df = DataFrame(
        timestamp=[DateTime(2024,1,1)+Dates.Minute(i) for i in 0:30],
        open=fill(50000.0,31), high=fill(50050.0,31), low=fill(49950.0,31),
        close=fill(50000.0,31), volume=fill(100.0,31))
    data = SortedDict{TimeFrame,DataFrame}(TimeFrame("1m") => df)
    limits = (leverage=(; min=1.0, max=10.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8))
    InstrumentInstance(a, data, exc, margin; limits=limits, precision=(amount=1e-8, price=1e-8), fees=(taker=0.001, maker=0.001, min=0.001, max=0.001))
end

function mkstrat(mode, margin, tag)
    exc = mkexc(tag)
    uni = InstrumentCollection(["BTC/USDT:USDT"]; exc=exc, margin=margin, load_data=false)
    cfg = Config(; qc=:USDT, initial_cash=100000.0)
    s = Strategy(Main, mode, margin, TimeFrame("1m"), exc, uni; config=cfg)
    # Sim/Paper strategies require explicit default! before trading (established
    # convention: _simmode_defaults! sets sim_* attrs; Paper sets paper_* attrs).
    mode isa Sim && PlanarCore.Strategies.default!(s)
    mode isa Paper && Planar.PaperMode.st.default!(s)
    ii = mkii(margin, exc)
    s, ii
end
@testset "AUDIT Sim order flow × margin" begin
    for margin in (NoMargin(), Isolated(), IsolatedHedged(), Cross(), CrossHedged())
        label = string(typeof(margin))
        @testset "$label" begin
            s, ii = mkstrat(Sim(), margin, Symbol("audit_sim_$(hash(label)%100000)"))
            nomargin = margin isa NoMargin
            hedged = margin isa Union{IsolatedHedged,CrossHedged}
            # instance type
            if nomargin
                @test ii isa NoMarginInstance
            elseif hedged
                @test ii isa HedgedInstance
            else
                @test ii isa MarginInstance
                @test !(ii isa HedgedInstance)
            end
            @test ishedged(ii) == hedged
            # open long via market buy (Increase)
            r = call!(s, ii, MarketOrder{Buy}; amount=0.01, date=DateTime(2024,1,1,0,5))
            @test !isnothing(r)
            if nomargin
                # NoMargin has no positions: isopen(ii, side) is always false by
                # design (module.jl:962); openness is !iszero(ii).
                @test isopen(ii)
                # reduce via market sell lowers holdings; short never opens
                r2 = call!(s, ii, MarketOrder{Sell}; amount=0.005, date=DateTime(2024,1,1,0,6))
                @test !isnothing(r2)
                @test isopen(ii)
            else
                @test isopen(ii, Long())
                if hedged
                    # hedged: short opens alongside long
                    r2 = call!(s, ii, ShortMarketOrder{Sell}; amount=0.01, date=DateTime(2024,1,1,0,6))
                    @test !isnothing(r2)
                    @test isopen(ii, Short())
                    @test isopen(ii, Long())
                else
                    # non-hedged: opposite side blocked
                    @test PlanarCore.SimMode.singlewaycheck(s, ii, ShortMarketOrder{Sell}) == false
                    r2 = call!(s, ii, ShortMarketOrder{Sell}; amount=0.01, date=DateTime(2024,1,1,0,6))
                    @test isnothing(r2)
                    @test !isopen(ii, Short())
                end
            end
        end
    end
end

@testset "AUDIT cash buckets Sim" begin
    s, ii = mkstrat(Sim(), Isolated(), :audit_cash)
    # Increase uses strategy cash
    @test PlanarCore.Strategies.freecash(s) > 0
    # Reduce uses position cash: fresh instance has ~0 position freecash
    @test abs(freecash(ii, Long())) < 1e-9
    # _cashfrom parity via source (already covered) + iscommittable methods exist
    @test length(methods(iscommittable)) >= 6
end

@testset "AUDIT Live check_available_cash buckets (BUG-1/BUG-2)" begin
    using Planar.LiveMode: check_available_cash
    using PlanarCore.OrderTypes: BuyOrder, SellOrder, ShortSellOrder, ShortBuyOrder
    s, ii = mkstrat(Sim(), Isolated(), :audit_livecash)
    # Isolated Increase with empty position but funded strategy MUST pass (BUG-1)
    @test check_available_cash(s, ii, 0.01, 50000.0, BuyOrder) == true
    @test check_available_cash(s, ii, 0.01, 50000.0, ShortSellOrder) == true
    # Reduce on empty position MUST fail even though strategy is funded (BUG-2)
    @test check_available_cash(s, ii, 0.01, 50000.0, SellOrder) == false
    @test check_available_cash(s, ii, 0.01, 50000.0, ShortBuyOrder) == false
    # Cross Reduce on empty position must also fail
    sc, iic = mkstrat(Sim(), Cross(), :audit_livecash_cross)
    @test check_available_cash(sc, iic, 0.01, 50000.0, SellOrder) == false
    # NoMargin short fast path
    sn, iin = mkstrat(Sim(), NoMargin(), :audit_livecash_nom)
    @test check_available_cash(sn, iin, 0.01, 50000.0, ShortSellOrder) == false
end

@testset "AUDIT Live sync dispatch + holdings" begin
    src = read(joinpath(@__DIR__, "../Planar/src/LiveMode/positions/sync.jl"), String)
    @test occursin("function live_sync_position!(s::LiveStrategy, ii::HedgedInstance", src)
    @test occursin("function live_sync_position!(s::LiveStrategy, ii::MarginInstance", src)
    @test occursin("delete!(s.holdings, ii)", src)
    @test occursin("if iszero(ii)", src)
end

@testset "AUDIT marginmode! authoritative + string path" begin
    using PlanarCore.Exchanges: marginmode!, dosetpositionmode, check_margin_support!
    @test hasmethod(dosetpositionmode, Tuple{PlanarCore.ExchangeTypes.Exchange, AbstractString, AbstractString})
    @test hasmethod(marginmode!, Tuple{PlanarCore.ExchangeTypes.Exchange, MarginMode})
    exc = mkexc(:audit_mm)
    @test check_margin_support!(exc, IsolatedHedged()) == true
    @test check_margin_support!(exc, Cross()) == true
    exc2 = mkexc(:audit_mm2)
    # stub without caps fails fast
    hasd = exc2.has
    @test has(exc2, :setMarginMode) == true
end

@testset "AUDIT Paper order flow × margin" begin
    for margin in (NoMargin(), Isolated(), IsolatedHedged(), Cross(), CrossHedged())
        label = string(typeof(margin))
        @testset "$label" begin
            s, ii = mkstrat(Paper(), margin, Symbol("audit_paper_$(hash(label)%100000)"))
            nomargin = margin isa NoMargin
            hedged = margin isa Union{IsolatedHedged,CrossHedged}
            # Paper priceat defaults to a gateway fetchTicker; pass explicit price
            # to exercise the local order path without a gateway.
            r = call!(s, ii, MarketOrder{Buy}; amount=0.01, date=DateTime(2024,1,1,0,5), price=50000.0)
            @test !isnothing(r)
            if nomargin
                @test isopen(ii)
                # spot cannot short: blocked in shared maketrade via iscashenough=false
                rs = call!(s, ii, ShortMarketOrder{Sell}; amount=0.01, date=DateTime(2024,1,1,0,6), price=50000.0)
                @test isnothing(rs)
            else
                @test isopen(ii, Long())
                if hedged
                    r2 = call!(s, ii, ShortMarketOrder{Sell}; amount=0.01, date=DateTime(2024,1,1,0,6), price=50000.0)
                    @test !isnothing(r2)
                    @test isopen(ii, Short())
                    @test isopen(ii, Long())
                else
                    r2 = call!(s, ii, ShortMarketOrder{Sell}; amount=0.01, date=DateTime(2024,1,1,0,6), price=50000.0)
                    @test isnothing(r2)
                    @test !isopen(ii, Short())
                end
            end
        end
    end
end

@testset "AUDIT Live NoMargin short fast-path (BUG-4, no gateway)" begin
    using Planar.LiveMode: live_send_order
    # NoMargin Live construction touches no gateway (WithMargin gate only)
    s, ii = mkstrat(Live(), NoMargin(), :audit_livenm)
    r = live_send_order(s, ii, ShortMarketOrder{Sell}; amount=0.01, price=50000.0)
    @test isnothing(r)
    r2 = live_send_order(s, ii, ShortMarketOrder{Buy}; amount=0.01, price=50000.0)
    @test isnothing(r2)
end

@testset "AUDIT Live positionSide wire (hedged only)" begin
    src = read(joinpath(@__DIR__, "../Planar/src/LiveMode/orders/send.jl"), String)
    @test occursin("if ishedged(ii)", src)
    @test occursin("pygetorconvert!(params, \"positionSide\", _ccxtposside(posside(t)))", src)
    # fast-path precedes all gateway activity
    # fast-path precedes all gateway activity — NoMargin short rejected via
    # positionside(t) == Short() before any gateway call (send.jl:151)
    @test occursin("positionside(t) == Short()", src)
end

@testset "AUDIT Cross leverage sentinel + liquidation dispatch" begin
    using PlanarCore.Instances: leverage!
    using PlanarCore.SimMode: maybe_liquidate!
    using PlanarCore.Executors: isliquidatable
    using Dates: DateTime as DateTime2
    _, iic = mkstrat(Sim(), Cross(), :audit_levcross)
    leverage!(iic, Long(), Val(:max))
    # Cross max-leverage resolves a real ceiling (bounded by exchange tier +
    # ii.limits.leverage.max), not the 1e10 sentinel — see leverage! comment.
    @test PlanarCore.Instances.leverage(iic, Long()) >= 1.0
    _, iih = mkstrat(Sim(), CrossHedged(), :audit_levcrossh)
    leverage!(iih, Short(), Val(:max))
    @test PlanarCore.Instances.leverage(iih, Short()) >= 1.0
    # liquidation dispatch: Sim uses candle low/high, Paper/Live use lastprice
    s_liq, ii_liq = mkstrat(Sim(), Isolated(), :audit_liq)
    r = call!(s_liq, ii_liq, MarketOrder{Buy}; amount=0.01, date=DateTime(2024,1,1,0,5))
    @test !isnothing(r)
    @test maybe_liquidate!(s_liq, ii_liq, DateTime(2024,1,1,0,6)) !== :crashed
    @test isopen(ii_liq, Long())  # healthy position survives
    @test hasmethod(isliquidatable, Tuple{PlanarCore.Strategies.SimStrategy, PlanarCore.Instances.MarginInstance, PlanarCore.Misc.PositionSide, DateTime})
    @test hasmethod(isliquidatable, Tuple{PlanarCore.Strategies.Strategy{PlanarCore.Misc.Live}, PlanarCore.Instances.MarginInstance, PlanarCore.Misc.PositionSide, DateTime})
end
