using PlanarCore.Instances
using PlanarCore.Exchanges
using PlanarCore.Exchanges.ExchangeTypes
using PlanarCore.Exchanges: CurrencyCash, Exchange, LeverageTier
using PlanarCore.Instances.Instruments: @a_str, add!, sub!, cash!, value, freecash
using PlanarCore.Instances.Instruments.Derivatives: Derivative, perpetual, sc
using PlanarCore.Instances.DataStructures: SortedDict
using PlanarCore.Instances.TimeTicks: TimeFrame, @tf_str
using PlanarCore.Instances.Data: DataFrame
using PlanarCore.Instances.Misc: NoMargin, Isolated, Cross, DFT, Long, Short, WithMargin, IsolatedHedged, CrossHedged, CrossMargin, Hedged, NotHedged, opposite
using Test

const _Dates = Instances.TimeTicks.Dates
const HTTP = Instances.Exchanges.ExchangeTypes.CcxtGateway.HTTP
const JSON3 = Instances.Exchanges.ExchangeTypes.JSON3

const date = _Dates.now()

# ── Setup mock HTTP ──────────────────────────────────────────
const _mock_sandbox = Dict{String,Bool}()

function _mock_currency_response()
    btc = Dict("id" => "BTC", "precision" => 8,
               "limits" => Dict("amount" => Dict("min" => 0.0001, "max" => 1000000.0)))
    Dict("result" => Dict("BTC" => btc))
end

function _mock_market_response()
    mk = Dict("id" => "BTC/USDT", "type" => "spot",
              "base" => "BTC", "quote" => "USDT",
              "taker" => 0.001, "maker" => 0.001,
              "precision" => Dict("amount" => 0.0001, "price" => 0.01),
              "limits" => Dict(
                  "amount" => Dict("min" => 0.0001, "max" => 1000.0),
                  "price" => Dict("min" => 0.01, "max" => 1000000.0),
                  "cost" => Dict("min" => 1.0, "max" => 10000000.0)))
    Dict("result" => Dict("BTC/USDT" => mk))
end

function _mock_urls_response(name)
    sandbox_mode = get(_mock_sandbox, name, false)
    if sandbox_mode
        urls = Dict("apiBackup" => "https://testnet.example.com",
                    "api" => "https://api.example.com")
    else
        urls = Dict("api" => "https://api.example.com")
    end
    Dict("result" => urls)
end

ExchangeTypes.CcxtGateway.Rest.set_http_get!((url; kwargs...) -> begin
    if occursin("/admin/exchange_names", url)
        HTTP.Response(200, JSON3.write(Dict("result" => ["mocktest"])))
    elseif occursin("/currencies", url)
        HTTP.Response(200, JSON3.write(_mock_currency_response()))
    elseif occursin("/markets", url)
        HTTP.Response(200, JSON3.write(_mock_market_response()))
    elseif occursin("/status", url)
        HTTP.Response(200, JSON3.write(Dict("result" => Dict("running" => true))))
    elseif occursin("/urls", url)
        m = match(r"/exchanges/([^/]+)/urls", url)
        name = m !== nothing ? m[1] : ""
        HTTP.Response(200, JSON3.write(_mock_urls_response(name)))
    elseif occursin("/fetchMarketLeverageTiers", url)
        result = [
            Dict("tier" => 1, "notionalFloor" => 0.0, "notionalCap" => 100000.0,
                 "maxLeverage" => 10.0, "maintenanceMarginRate" => 0.01,
                 "maintAmtNotional" => 0.0, "minNotional" => 0.0),
            Dict("tier" => 2, "notionalFloor" => 100000.0, "notionalCap" => 500000.0,
                 "maxLeverage" => 5.0, "maintenanceMarginRate" => 0.025,
                 "maintAmtNotional" => 0.0, "minNotional" => 0.0),
        ]
        HTTP.Response(200, JSON3.write(Dict("result" => result)))
    else
        HTTP.Response(200, JSON3.write(Dict("result" => nothing)))
    end
end)

ExchangeTypes.CcxtGateway.Rest.set_http_post!((url; kwargs...) -> begin
    if occursin("/setSandboxMode", url)
        m = match(r"/exchanges/([^/]+)/setSandboxMode", url)
        name = m !== nothing ? m[1] : ""
        body_str = get(kwargs, :body, "{}")
        body = JSON3.parse(body_str)
        enabled = get(body, "enabled", false)
        _mock_sandbox[name] = enabled
        HTTP.Response(200, JSON3.write(Dict("result" => Dict("success" => true))))
    else
        HTTP.Response(200, JSON3.write(Dict("result" => "started")))
    end
end)

# Create a shared mock exchange
# Use an exchange name NOT in the ccxt exchange set to skip gateway calls
const exc = Exchange(:mocktest)
# Manually seed markets so InstrumentInstance constructor doesn't crash
exc.markets["BTC/USDT"] = Dict{String,Any}(
    "id" => "BTC/USDT", "type" => "spot",
    "base" => "BTC", "quote" => "USDT",
    "taker" => 0.001, "maker" => 0.001,
    "precision" => Dict("amount" => 0.0001, "price" => 0.01),
    "limits" => Dict(
        "amount" => Dict("min" => 0.0001, "max" => 1000.0),
        "price" => Dict("min" => 0.01, "max" => 1000000.0),
        "cost" => Dict("min" => 1.0, "max" => 10000000.0)))
push!(exc.types, :spot)
exc.markets["BTC/USDT:USDT"] = Dict{String,Any}(
    "id" => "BTC/USDT:USDT", "type" => "swap",
    "base" => "BTC", "quote" => "USDT",
    "taker" => 0.001, "maker" => 0.001,
    "precision" => Dict("amount" => 0.0001, "price" => 0.01),
    "limits" => Dict(
        "amount" => Dict("min" => 0.0001, "max" => 1000.0),
        "price" => Dict("min" => 0.01, "max" => 1000000.0),
        "cost" => Dict("min" => 1.0, "max" => 10000000.0)))
push!(exc.types, :swap)
const a = a"BTC/USDT"

# =============================================================
# 1. Type hierarchy and aliases
# =============================================================
@testset "Type hierarchy" begin
    @test Instances.NoMarginInstance <: Instances.AbstractInstance
    @test Instances.MarginInstance{Isolated} <: Instances.AbstractInstance
    @test Instances.MarginInstance{Cross} <: Instances.AbstractInstance
    @test Instances.HedgedInstance{IsolatedHedged} <: Instances.AbstractInstance
    @test Instances.HedgedInstance{CrossHedged} <: Instances.AbstractInstance
    @test Instances.CrossInstance{CrossHedged} <: Instances.AbstractInstance

    @test Instances.PositionOpen <: Instances.PositionStatus
    @test Instances.PositionClose <: Instances.PositionStatus
    @test Instances.PositionUpdate <: Instances.PositionChange
    @test Instances.PositionOpen <: Instances.PositionChange
    @test Instances.PositionClose <: Instances.PositionChange
end

# =============================================================
# 2. Exchange and CurrencyCash
# =============================================================
@testset "Exchange and CurrencyCash" begin
    @test string(exc.id) == "mocktest"
    @test exc isa Exchange

    c = CurrencyCash(exc, "BTC", 0.0)
    @test c isa CurrencyCash
    @test value(c) == 0.0
    @test c.id == :BTC
end

# =============================================================
# 3. NoMarginInstance construction
# =============================================================
@testset "NoMarginInstance" begin
    limits = (leverage=(min=1.0, max=10.0), amount=(min=1e-8, max=1e8), price=(min=1e-8, max=1e8), cost=(min=1e-8, max=1e8))
    precision = (amount=1e-8, price=1e-8)
    fees = (taker=0.01, maker=0.01, min=0.01, max=0.01)
    data = SortedDict{TimeFrame,DataFrame}(tf"1m" => DataFrame())

    ii = Instances.InstrumentInstance(a, data, exc, NoMargin(); limits=limits, precision=precision, fees=fees)
    @test ii isa Instances.InstrumentInstance
    @test ii isa Instances.NoMarginInstance
    @test Instances.raw(ii) == "BTC/USDT"
    @test Instances.bc(ii) == :BTC
    @test Instances.qc(ii) == :USDT
    @test Instances.exchange(ii) === exc
    @test Instances.exchangeid(ii) == ExchangeID{:mocktest}
    @test Instances.asset(ii) === a
    @test iszero(ii)
end

# =============================================================
# 4. NoMarginInstance cash operations
# =============================================================
@testset "Cash operations" begin
    limits = (leverage=(min=1.0, max=10.0), amount=(min=1e-8, max=1e8), price=(min=1e-8, max=1e8), cost=(min=1e-8, max=1e8))
    precision = (amount=1e-8, price=1e-8)
    fees = (taker=0.01, maker=0.01, min=0.01, max=0.01)
    data = SortedDict{TimeFrame,DataFrame}(tf"1m" => DataFrame())
    ii = Instances.InstrumentInstance(a, data, exc, NoMargin(); limits=limits, precision=precision, fees=fees)
    @test value(Instances.cash(ii)) == 0.0
    @test value(Instances.committed(ii)) == 0.0

    # add cash
    ai_cash = Instances.cash(ii)
    add!(ai_cash, 1.5)
    @test value(Instances.cash(ii)) == 1.5
    @test !iszero(ii)

    # committed
    add!(Instances.committed(ii), 0.5)
    @test value(Instances.committed(ii)) == 0.5

    # freecash
    @test Instances.freecash(ii) ≈ 1.0

    # cash via add! directly
    add!(ii, 0.5)
    @test value(Instances.cash(ii)) == 2.0

    # sub
    sub!(ii, 0.3)
    @test value(Instances.cash(ii)) == 1.7

    # cash!
    cash!(ii, 10.0)
    @test value(Instances.cash(ii)) == 10.0

    # long position
    @test Instances.posside(ii) == Long()
    @test Instances.islong(ii)
    @test !Instances.isshort(ii)

    # limits, precision, fees
    @test Instances.takerfees(ii) == 0.01
    @test Instances.makerfees(ii) == 0.01
    @test Instances.maxfees(ii) == 0.01
    @test Instances.minfees(ii) == 0.01

    # reset
    Instances.reset!(ii)
    @test iszero(ii)
    @test value(Instances.cash(ii)) == 0.0
    @test value(Instances.committed(ii)) == 0.0
end

# =============================================================
# 5. amount_with_fees
# =============================================================
@testset "amount_with_fees" begin
    @test Instances.amount_with_fees(1.0, 0.01) ≈ 0.99
    @test Instances.amount_with_fees(1.0, -0.01) ≈ 0.99
    @test Instances.amount_with_fees(1.0, 0.0) ≈ 1.0
end

# =============================================================
# 6. opposite for PositionStatus
# =============================================================
@testset "opposite" begin
    @test opposite(Instances.PositionOpen()) == Instances.PositionClose()
    @test opposite(Instances.PositionClose()) == Instances.PositionOpen()
end

# =============================================================
# 7. Events
# =============================================================
@testset "Position events" begin
    using .Instances.OrderTypes: PositionUpdated, MarginUpdated, LeverageUpdated

    pe = PositionUpdated{:mocktest}(
        :liq_event, :default, "BTC/USDT", (Long(), true),
        date, 45000.0, 48000.0, 1000.0, 2000.0, 10.0, 50000.0
    )
    @test pe.tag == :liq_event
    @test pe.asset == "BTC/USDT"
    @test pe.side_status == (Long(), true)
    @test pe.entryprice == 48000.0
    @test pe.leverage == 10.0
    @test pe.notional == 50000.0
    @test pe.maintenance_margin == 1000.0

    me = MarginUpdated{:mocktest}(
        :margin_change, :group1, "ETH/USDT", Short(),
        date, "cross", 1000.0, 1500.0
    )
    @test me.side == Short()
    @test me.mode == "cross"
    @test me.from == 1000.0
    @test me.value == 1500.0

    le = LeverageUpdated{:mocktest}(
        :lev_change, :group1, "ETH/USDT", Long(),
        date, 5.0, 10.0
    )
    @test le.from == 5.0
    @test le.value == 10.0
end

# =============================================================
# 8. isdust for NoMarginInstance
# =============================================================
@testset "isdust" begin
    limits = (leverage=(min=1.0, max=10.0), amount=(min=0.1, max=1e8), price=(min=1e-8, max=1e8), cost=(min=100.0, max=1e8))
    precision = (amount=1e-8, price=1e-8)
    fees = (taker=0.01, maker=0.01, min=0.01, max=0.01)
    data = SortedDict{TimeFrame,DataFrame}(tf"1m" => DataFrame())
    ii = Instances.InstrumentInstance(a, data, exc, NoMargin(); limits=limits, precision=precision, fees=fees)

    add!(Instances.cash(ii), 0.05)
    @test Instances.isdust(ii, 1000.0) == true

    cash!(Instances.cash(ii), 0.2)
    @test Instances.isdust(ii, 1000.0) == false
end

# =============================================================
# 9. Print/Display smoke tests
# =============================================================
@testset "Print/display" begin
    limits = (leverage=(min=1.0, max=10.0), amount=(min=1e-8, max=1e8), price=(min=1e-8, max=1e8), cost=(min=1e-8, max=1e8))
    precision = (amount=1e-8, price=1e-8)
    fees = (taker=0.01, maker=0.01, min=0.01, max=0.01)
    data = SortedDict{TimeFrame,DataFrame}(tf"1m" => DataFrame())
    ii = Instances.InstrumentInstance(a, data, exc, NoMargin(); limits=limits, precision=precision, fees=fees)

    add!(Instances.cash(ii), 1.5)
    buf = IOBuffer()
    print(buf, ii)
    s = String(take!(buf))
    @test occursin("BTC/USDT", s)
    @test occursin("mocktest", s)

    show(buf, ii)
    @test String(take!(buf)) != ""

    show(buf, MIME("text/plain"), ii)
    @test String(take!(buf)) != ""
end

# =============================================================
# 10. Default asset DataFrame
# =============================================================
@testset "default_asset_df" begin
    limits = (leverage=(min=1.0, max=10.0), amount=(min=1e-8, max=1e8), price=(min=1e-8, max=1e8), cost=(min=1e-8, max=1e8))
    precision = (amount=1e-8, price=1e-8)
    fees = (taker=0.01, maker=0.01, min=0.01, max=0.01)
    data = SortedDict{TimeFrame,DataFrame}(tf"1m" => DataFrame())
    ii = Instances.InstrumentInstance(a, data, exc, NoMargin(); limits=limits, precision=precision, fees=fees)

    df = Instances.default_asset_df(ii)
    @test df isa DataFrame
end

# =============================================================
# 11. BalanceUpdated and OHLCVUpdated event
# =============================================================
@testset "Other events" begin
    be = Instances.OrderTypes.BalanceUpdated(exc, :bal_tag, :bal_group, Dict(:BTC => 1.5, :USDT => 10000.0))
    @test be.tag == :bal_tag
    @test be.group == :bal_group
    @test be.data.balance[:BTC] == 1.5

    oe = Instances.OrderTypes.OHLCVUpdated{:test}(:ohlcv_tag, :ohlcv_group, (open=100.0, high=110.0, low=99.0, close=105.0))
    @test oe.data.open == 100.0
end

# =============================================================
# 12. Position pure helper functions
# =============================================================
@testset "bankruptcy" begin
    @test Instances.bankruptcy(100.0, 10.0, Long()) ≈ 90.0
    @test Instances.bankruptcy(100.0, 10.0, Short()) ≈ 110.0
    @test Instances.bankruptcy(100.0, 5.0, Long()) ≈ 80.0
    @test Instances.bankruptcy(100.0, 5.0, Short()) ≈ 120.0
    @test Instances.bankruptcy(100.0, 1.0, Long()) ≈ 0.0
    @test Instances.bankruptcy(100.0, 1.0, Short()) ≈ 200.0
end

@testset "pnl arithmetic" begin
    # Long: (current_price - entryprice) * abs(amount)
    @test Instances.pnl(100.0, 110.0, 1.0, Long()) == 10.0
    @test Instances.pnl(100.0, 90.0, 1.0, Long()) == -10.0
    # Short: (entryprice - current_price) * abs(amount)
    @test Instances.pnl(100.0, 90.0, 1.0, Short()) == 10.0
    @test Instances.pnl(100.0, 110.0, 1.0, Short()) == -10.0
end

# =============================================================
# 13. Position construction and state
# =============================================================
@testset "Position state" begin
    da = parse(Derivative, "BTC/USDT")
    tier1 = LeverageTier(Dict(
        "tier" => 1, "notionalFloor" => 0.0, "notionalCap" => 100000.0,
        "maxLeverage" => 10.0, "maintenanceMarginRate" => 0.01, 
        "maintAmtNotional" => 0.0, "minNotional" => 0.0))
    tiers_v = [tier1]
    cc = CurrencyCash(exc, "BTC", 0.0)

    po = Instances.Position{Long, ExchangeID{:mocktest}, Isolated}(
        asset=da, min_size=0.001, cash=cc, cash_committed=cc,
        tiers=[tiers_v], this_tier=[tier1])

    @test Instances.posside(po) == Long()
    @test Instances.islong(po)
    @test !Instances.isshort(po)
    @test !Instances.isopen(po)
    @test Instances.status(po) == Instances.PositionClose()
    @test Instances.leverage(po) == 1.0
    @test Instances.notional(po) == 0.0
    @test Instances.margin(po) == 0.0
    @test Instances.maintenance(po) == 0.0
    @test Instances.additional(po) == 0.0
    @test Instances.collateral(po) == 0.0
    @test Instances.entryprice(po) == 0.0
    @test Instances.liqprice(po) == 0.0
    @test Instances.price(po) == 0.0
    @test Instances.mmr(po) == 0.01
    @test Instances.maxleverage(po) == 10.0
    @test Instances.marginmode(po) == Isolated()
    @test Instances.ishedged(po) == false
    @test Instances.cash(po) === cc
    @test Instances.committed(po) === cc
end

# =============================================================
# 14. Position mutating operations
# =============================================================
@testset "Position mutations" begin
    da = parse(Derivative, "BTC/USDT")
    tier1 = LeverageTier(Dict(
        "tier" => 1, "notionalFloor" => 0.0, "notionalCap" => 100000.0,
        "maxLeverage" => 10.0, "maintenanceMarginRate" => 0.01,
        "maintAmtNotional" => 0.0, "minNotional" => 0.0))
    tiers_v = [tier1]
    cc = CurrencyCash(exc, "BTC", 0.0)

    po = Instances.Position{Long, ExchangeID{:mocktest}, Isolated}(
        asset=da, min_size=0.001, cash=cc, cash_committed=cc,
        tiers=[tiers_v], this_tier=[tier1])

    # leverage!
    Instances.leverage!(po, 5.0)
    @test Instances.leverage(po) == 5.0

    # timestamp!
    dt = _Dates.now()
    Instances.timestamp!(po, dt)
    @test Instances.timestamp(po) == dt

    # notional! -> triggers tier!
    Instances.notional!(po, 50000.0)
    @test Instances.notional(po) == 50000.0
    @test Instances.leverage(po) == 5.0  # unchanged

    # margin! and maintenance!
    Instances.margin!(po)
    @test Instances.margin(po) ≈ 50000.0 / 5.0  # notional / leverage
    Instances.maintenance!(po, 500.0)
    @test Instances.maintenance(po) == 500.0

    # additional!
    Instances.additional!(po, 200.0)
    @test Instances.additional(po) == 200.0
    @test Instances.collateral(po) == Instances.margin(po) + 200.0

    # addmargin!
    Instances.addmargin!(po, 100.0)
    @test Instances.additional(po) == 300.0

    # entryprice!
    Instances.entryprice!(po, 45000.0)
    @test Instances.entryprice(po) == 45000.0

    # liqprice!
    Instances.liqprice!(po, 40000.0)
    @test Instances.liqprice(po) == 40000.0

    # isopen after mutations
    @test !Instances.isopen(po)

    # tier lookup by notional (returns LeverageTier, not tuple)
    @test Instances.tier(po, 50000.0) == tier1
    @test Instances.tier(po, 0.0) == tier1

    # _status! throws on close→close transition
    @test_throws AssertionError Instances._status!(po, Instances.PositionClose())
end

# =============================================================
# 15. Position PNL
# =============================================================
@testset "Position PNL" begin
    da = parse(Derivative, "BTC/USDT")
    tier1 = LeverageTier(Dict(
        "tier" => 1, "notionalFloor" => 0.0, "notionalCap" => 100000.0,
        "maxLeverage" => 10.0, "maintenanceMarginRate" => 0.01,
        "maintAmtNotional" => 0.0, "minNotional" => 0.0))
    cc = CurrencyCash(exc, "BTC", 0.0)

    po = Instances.Position{Long, ExchangeID{:mocktest}, Isolated}(
        asset=da, min_size=0.001, cash=cc, cash_committed=cc,
        tiers=[[tier1]], this_tier=[tier1])

    # closed position returns 0 PNL
    @test Instances.pnl(po, 50000.0) == 0.0

    # open with cash
    add!(Instances.cash(po), 1.0)  # 1 BTC
    Instances.notional!(po, 50000.0)
    Instances.leverage!(po, 5.0)
    Instances.entryprice!(po, 45000.0)
    Instances.margin!(po)
    po.status[] = Instances.PositionOpen()

    @test Instances.isopen(po)
    @test Instances.pnl(po, 50000.0) ≈ 5000.0   # (50000-45000)*1.0
    @test Instances.pnl(po, 40000.0) ≈ -5000.0

    # Short position
    cc2 = CurrencyCash(exc, "BTC", 0.0)
    po2 = Instances.Position{Short, ExchangeID{:mocktest}, Isolated}(
        asset=da, min_size=0.001, cash=cc2, cash_committed=cc2,
        tiers=[[tier1]], this_tier=[tier1])
    add!(Instances.cash(po2), 1.0)
    po2.status[] = Instances.PositionOpen()
    Instances.notional!(po2, 50000.0)
    Instances.leverage!(po2, 5.0)
    Instances.entryprice!(po2, 45000.0)

    @test Instances.pnl(po2, 40000.0) ≈ 5000.0  # (45000-40000)*1.0
    @test Instances.pnl(po2, 50000.0) ≈ -5000.0

    # pnlpct for Long: pnl(po, v, 1.0) / price(po)
    @test Instances.pnlpct(po, 50000.0) ≈ 5000.0 / 45000.0
    @test Instances.pnlpct(po, 40000.0) ≈ -5000.0 / 45000.0
end

# =============================================================
# 16. Position display
# =============================================================
@testset "Position display" begin
    da = parse(Derivative, "BTC/USDT")
    tier1 = LeverageTier(Dict(
        "tier" => 1, "notionalFloor" => 0.0, "notionalCap" => 100000.0,
        "maxLeverage" => 10.0, "maintenanceMarginRate" => 0.01,
        "maintAmtNotional" => 0.0, "minNotional" => 0.0))
    cc = CurrencyCash(exc, "BTC", 0.0)
    po = Instances.Position{Long, ExchangeID{:mocktest}, Isolated}(
        asset=da, min_size=0.001, cash=cc, cash_committed=cc,
        tiers=[[tier1]], this_tier=[tier1])

    buf = IOBuffer()
    print(buf, po)
    s = String(take!(buf))
    @test occursin("Position", s)
    @test occursin("Long", s)
    @test occursin("BTC/USDT", s)
end

# =============================================================
# 17. MarginInstance construction
# =============================================================
@testset "MarginInstance construction" begin
    da = parse(Derivative, "BTC/USDT:USDT")
    limits = (leverage=(min=1.0, max=10.0), amount=(min=1e-8, max=1e8),
              price=(min=1e-8, max=1e8), cost=(min=1e-8, max=1e8))
    precision = (amount=1e-8, price=1e-8)
    fees = (taker=0.01, maker=0.01, min=0.01, max=0.01)
    data = SortedDict{TimeFrame,DataFrame}(tf"1m" => DataFrame())

    # Seed leverage tiers to avoid gateway call
    tier_key = (Symbol(exc.id), "BTC/USDT:USDT")
    tier1 = LeverageTier(Dict(
        "tier" => 1, "notionalFloor" => 0.0, "notionalCap" => 100000.0,
        "maxLeverage" => 10.0, "maintenanceMarginRate" => 0.01,
        "maintAmtNotional" => 0.0, "minNotional" => 0.0))
    Exchanges._TIER_CACHES[tier_key] = ([tier1], time() * 1000)

    ii = Instances.InstrumentInstance(da, data, exc, Isolated(); limits=limits, precision=precision, fees=fees)
    @test ii isa Instances.InstrumentInstance
    @test ii isa Instances.MarginInstance{Isolated}
    @test Instances.raw(ii) == "BTC/USDT:USDT"
    @test Instances.bc(ii) == :BTC
    @test Instances.qc(ii) == :USDT
    @test Instances.exchange(ii) === exc
    @test Instances.exchangeid(ii) == ExchangeID{:mocktest}
    @test Instances.asset(ii) === da
    @test Instances.marginmode(ii) == Isolated()

    # Positions should be created with tiers
    longpos = Instances.position(ii, Long())
    shortpos = Instances.position(ii, Short())
    @test longpos !== nothing
    @test shortpos !== nothing
    @test Instances.islong(longpos)
    @test Instances.isshort(shortpos)
    @test Instances.leverage(longpos) == 1.0
    @test Instances.maxleverage(longpos) == 10.0
    @test Instances.mmr(longpos) == 0.01

    # Cash is nothing for margin instances
    @test Instances.cash(ii) === nothing
    @test Instances.committed(ii) === nothing

    # Cross margin
    ii2 = Instances.InstrumentInstance(da, data, exc, Cross(); limits=limits, precision=precision, fees=fees)
    @test ii2 isa Instances.MarginInstance{Cross}
    @test Instances.marginmode(ii2) == Cross()

    # Float conversion
    @test float(ii) == 0.0
end

@testset "MarginInstance cash/reset/print regression" begin
    da = parse(Derivative, "BTC/USDT:USDT")
    limits = (leverage=(min=1.0, max=10.0), amount=(min=1e-8, max=1e8),
              price=(min=1e-8, max=1e8), cost=(min=1e-8, max=1e8))
    precision = (amount=1e-8, price=1e-8)
    fees = (taker=0.01, maker=0.01, min=0.01, max=0.01)
    data = SortedDict{TimeFrame,DataFrame}(tf"1m" => DataFrame())
    tier_key = (Symbol(exc.id), "BTC/USDT:USDT")
    tier1 = LeverageTier(Dict(
        "tier" => 1, "notionalFloor" => 0.0, "notionalCap" => 100000.0,
        "maxLeverage" => 10.0, "maintenanceMarginRate" => 0.01,
        "maintAmtNotional" => 0.0, "minNotional" => 0.0))
    Exchanges._TIER_CACHES[tier_key] = ([tier1], time() * 1000)
    ii = Instances.InstrumentInstance(da, data, exc, Isolated(); limits=limits, precision=precision, fees=fees)
    # guarded getters must not crash on a normal instance
    @test Instances.cash(ii, Long()) !== nothing
    @test Instances.cash(ii, Short()) !== nothing
    @test Instances.committed(ii, Long()) !== nothing
    @test Instances.committed(ii, Short()) !== nothing
    @test Instances.iszero(ii) == true
    @test Instances.freecash(ii, Long()) == 0.0
    @test Instances.freecash(ii, Short()) == 0.0
    @test_nowarn Instances.reset!(ii, Short())
    @test_nowarn sprint(show, ii)
    # committed(ii) with no active position must not throw (returns nothing),
    # mirroring cash(ii) which already guards the absent side.
    ii.lastpos[] = nothing
    @test Instances.committed(ii) === nothing
    @test_nowarn sprint(show, ii)
end


# =============================================================
# 18. @rprice and @ramount macros
# =============================================================
@testset "@rprice/@ramount macros" begin
    da = parse(Derivative, "BTC/USDT:USDT")
    limits = (leverage=(min=1.0, max=10.0), amount=(min=1e-8, max=1e8),
              price=(min=1e-8, max=1e8), cost=(min=1e-8, max=1e8))
    precision = (amount=1e-4, price=0.01)  # coarser precision for meaningful test
    fees = (taker=0.01, maker=0.01, min=0.01, max=0.01)
    data = SortedDict{TimeFrame,DataFrame}(tf"1m" => DataFrame())

    ii = Instances.InstrumentInstance(da, data, exc, Isolated(); limits=limits, precision=precision, fees=fees)

    # The macros use the `ii` variable in scope
    @test (@rprice 100.123) == Instances.toprecision(100.123, ii.precision.price)
    @test (@rprice 100.125) == Instances.toprecision(100.125, ii.precision.price)
    @test (@ramount 0.00123) == Instances.toprecision(0.00123, ii.precision.amount)
    @test (@ramount 0.00125) == Instances.toprecision(0.00125, ii.precision.amount)
end

# =============================================================
# 19. _roundpos
# =============================================================
@testset "_roundpos" begin
    @test Instances._roundpos(1.23456, 2) ≈ 1.23
    @test Instances._roundpos(-1.23456, 2) ≈ -1.23
    @test Instances._roundpos(0.0, 5) == 0.0
    @test Instances._roundpos(1.23456789, 4) ≈ 1.2345  # default precision with RoundToZero
    @test Instances._roundpos(-1.23456789, 4) ≈ -1.2345
end

# =============================================================
# 20. Base.iszero for InstrumentInstance
# =============================================================
@testset "Base.iszero for InstrumentInstance" begin
    limits = (leverage=(min=1.0, max=10.0), amount=(min=1e-8, max=1e8),
              price=(min=1e-8, max=1e8), cost=(min=1e-8, max=1e8))
    precision = (amount=1e-8, price=1e-8)
    fees = (taker=0.01, maker=0.01, min=0.01, max=0.01)
    data = SortedDict{TimeFrame,DataFrame}(tf"1m" => DataFrame())
    ii = Instances.InstrumentInstance(a, data, exc, NoMargin(); limits=limits, precision=precision, fees=fees)
    @test iszero(ii)
    add!(Instances.cash(ii), 0.5)
    @test !iszero(ii)
end

# =============================================================
# 21. _status! Position state transitions
# =============================================================
@testset "_status! transitions" begin
    da = parse(Derivative, "BTC/USDT")
    tier1 = LeverageTier(Dict(
        "tier" => 1, "notionalFloor" => 0.0, "notionalCap" => 100000.0,
        "maxLeverage" => 10.0, "maintenanceMarginRate" => 0.01,
        "maintAmtNotional" => 0.0, "minNotional" => 0.0))
    cc = CurrencyCash(exc, "BTC", 0.0)
    po = Instances.Position{Long, ExchangeID{:mocktest}, Isolated}(
        asset=da, min_size=0.001, cash=cc, cash_committed=cc,
        tiers=[[tier1]], this_tier=[tier1])

    # Default status is PositionClose
    @test Instances.isopen(po) == false
    @test po.status[] == Instances.PositionClose()

    # Open → Close transition succeeds (default is close)
    Instances._status!(po, Instances.PositionOpen())
    @test Instances.isopen(po) == true

    # Close → Open transition
    Instances._status!(po, Instances.PositionClose())
    @test Instances.isopen(po) == false

    # Open → Open should error
    Instances._status!(po, Instances.PositionOpen())
    @test_throws AssertionError Instances._status!(po, Instances.PositionOpen())
end

# =============================================================
# 22. _roundlev
# =============================================================
@testset "_roundlev" begin
    da = parse(Derivative, "BTC/USDT:USDT")
    tier1 = LeverageTier(Dict(
        "tier" => 1, "notionalFloor" => 0.0, "notionalCap" => 100000.0,
        "maxLeverage" => 10.0, "maintenanceMarginRate" => 0.01,
        "maintAmtNotional" => 0.0, "minNotional" => 0.0))
    cc = CurrencyCash(exc, "BTC", 0.0)
    po = Instances.Position{Long, ExchangeID{:mocktest}, Isolated}(
        asset=da, min_size=0.001, cash=cc, cash_committed=cc,
        tiers=[[tier1]], this_tier=[tier1])

    # Normal leverage within bounds, rounded to 2 decimal places (RoundToZero)
    @test Instances._roundlev(po, 5.0) == 5.0
    @test Instances._roundlev(po, 5.6789) ≈ 5.67
    # Clamped to maxleverage (10.0)
    @test Instances._roundlev(po, 20.0) == 10.0
    # Clamped to min leverage (1.0)
    @test Instances._roundlev(po, 0.5) == 1.0
end

# =============================================================
# 23. nondust for MarginInstance
# =============================================================
@testset "nondust for MarginInstance" begin
    da = parse(Derivative, "BTC/USDT:USDT")
    tier_key = (Symbol(exc.id), "BTC/USDT:USDT")
    tier1 = LeverageTier(Dict(
        "tier" => 1, "notionalFloor" => 0.0, "notionalCap" => 100000.0,
        "maxLeverage" => 10.0, "maintenanceMarginRate" => 0.01,
        "maintAmtNotional" => 0.0, "minNotional" => 0.0))
    Exchanges._TIER_CACHES[tier_key] = ([tier1], time() * 1000)
    limits = (leverage=(min=1.0, max=10.0), amount=(min=1e-8, max=1e8),
              price=(min=1e-8, max=1e8), cost=(min=10.0, max=1e8))
    precision = (amount=1e-8, price=1e-8)
    fees = (taker=0.01, maker=0.01, min=0.01, max=0.01)
    data = SortedDict{TimeFrame,DataFrame}(tf"1m" => DataFrame())
    ii = Instances.InstrumentInstance(da, data, exc, Isolated(); limits=limits, precision=precision, fees=fees)

    # No position → returns 0
    longpos = Instances.position(ii, Long())
    shortpos = Instances.position(ii, Short())
    @test Instances.nondust(ii, 50000.0, Long()) == 0.0
    @test Instances.nondust(ii, 50000.0, Short()) == 0.0

    # Add cash to position and verify nondust
    # cost.min = 10.0, so 0.0001 BTC * 50000 * 1.0 = 5.0 < 10.0 → dust
    Instances.Instruments.add!(Instances.cash(longpos), 0.0001)
    @test Instances.nondust(ii, 50000.0, Long()) == 0.0

    # 0.001 BTC * 50000 * 1.0 = 50.0 > 10.0 → not dust
    Instances.Instruments.add!(Instances.cash(longpos), 0.001)
    @test Instances.nondust(ii, 50000.0, Long()) > 0.0
end

# =============================================================
# 24. Typed attrs and pushtrade! (2nd-round Task 1)
# =============================================================
@testset "Typed attrs and pushtrade!" begin
    using .Instances.OrderTypes: Trade, Order, MarketOrder, Buy, Long

    limits = (leverage=(min=1.0, max=10.0), amount=(min=1e-8, max=1e8),
              price=(min=1e-8, max=1e8), cost=(min=1e-8, max=1e8))
    precision = (amount=1e-8, price=1e-8)
    fees = (taker=0.01, maker=0.01, min=0.01, max=0.01)
    data = SortedDict{TimeFrame,DataFrame}(tf"1m" => DataFrame())
    ii = Instances.InstrumentInstance(a, data, exc, NoMargin(); limits=limits, precision=precision, fees=fees)

    # attr!/attr/hasattr on the flexible Dict{Symbol,Any}
    @test Instances.attr!(ii, :mykey, 42) == 42
    @test Instances.attr(ii, :mykey) == 42
    @test Instances.hasattr(ii, :mykey)
    @test !Instances.hasattr(ii, :absent)

    # typed accessor returns a concrete type (not Any)
    vt = Instances.attr(ii, Int, :mykey)
    @test vt == 42
    @test vt isa Int

    # typed accessor with default + convert
    @test Instances.attr(ii, Int, :absent, 0) == 0
    @test Instances.attr(ii, Float64, :mykey) == 42.0
    @test Instances.attr(ii, Float64, :mykey) isa Float64

    # pushtrade! appends to history (typed barrier)
    eid = Instances.exchangeid(exc)
    o = Order(a, eid, MarketOrder{Buy}; price=DFT(50000.0), amount=1.0, date=_Dates.DateTime(2024, 1, 1))
    t = Trade(o; date=_Dates.DateTime(2024, 1, 1), amount=1.0, price=DFT(50000.0),
              fees=0.01, size=50000.0, lev=1.0, entryprice=DFT(50000.0), fees_base=0.0)
    @test isempty(Instances.trades(ii))
    Instances.pushtrade!(ii, t)
    @test length(Instances.trades(ii)) == 1
    @test Instances.trades(ii)[end] === t
end
