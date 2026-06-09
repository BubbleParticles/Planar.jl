module Runtests

using Test
using Collections
using Strategies
using Strategies.Instances.Exchanges.ExchangeTypes
using Strategies.Instances.Exchanges.ExchangeTypes: CcxtExchange, ExchangeID, ExcPrecisionMode
using Strategies.Instances.Exchanges.ExchangeTypes.OrderedCollections: OrderedSet
using Strategies.Instances.Misc: Config
using Strategies.Instances.Data.TimeTicks: TimeFrame, DateTime, TimeTicks, Period, Second, Minute
using Strategies.Instances.Data.DataFrames: DataFrame
using Strategies.Instances.Instruments: AbstractAsset, parse, raw, cash!
using Strategies.Instances.Misc: NoMargin, Sim
using Strategies.Instances: NoMarginInstance, AssetInstance, ohlcv
using Strategies.Instances.Data.DataStructures: SortedDict

function _make_exchange(name::Symbol)
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

const mock_exc = _make_exchange(:test)

function _make_ohlcv(price, n=10)
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

function _make_strategy(assets=[:BTC]; qc=:USDT, cash=10000.0, sandbox=true)
    a_list = [parse(AbstractAsset, string(sym, "/USDT")) for sym in assets]
    tf = TimeFrame("1m")
    ais = [
        AssetInstance(
            a, SortedDict(tf => _make_ohlcv(50000.0)), mock_exc, NoMargin();
            limits=(; leverage=(; min=1.0, max=100.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8)),
            precision=(; amount=8, price=2),
            fees=(; taker=0.001, maker=0.001, min=0.001, max=0.001),
        ) for a in a_list
    ]
    uni = Collections.AssetCollection(ais)
    cfg = Config(; qc=qc, initial_cash=cash, sandbox=sandbox)
    Strategies.Strategy(@__MODULE__, Sim(), NoMargin(), tf, mock_exc, uni; config=cfg)
end

@testset "Strategies" begin
    @testset "type aliases" begin
        @test Strategies.SimStrategy <: Strategies.AbstractStrategy
        @test Strategies.PaperStrategy <: Strategies.AbstractStrategy
        @test Strategies.LiveStrategy <: Strategies.AbstractStrategy
        @test Strategies.RTStrategy <: Strategies.AbstractStrategy
        @test Strategies.IsolatedStrategy <: Strategies.AbstractStrategy
        @test Strategies.CrossStrategy <: Strategies.AbstractStrategy
        @test Strategies.MarginStrategy <: Strategies.AbstractStrategy
        @test Strategies.NoMarginStrategy <: Strategies.AbstractStrategy
    end

    @testset "strategy construction" begin
        a_btc = parse(AbstractAsset, "BTC/USDT")
        a_eth = parse(AbstractAsset, "ETH/USDT")
        tf = TimeFrame("1m")
        data = SortedDict(tf => _make_ohlcv(50000.0))
        ai_btc = AssetInstance(
            a_btc, data, mock_exc, NoMargin();
            limits=(; leverage=(; min=1.0, max=100.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8)),
            precision=(; amount=8, price=2),
            fees=(; taker=0.001, maker=0.001, min=0.001, max=0.001),
        )
        ai_eth = AssetInstance(
            a_eth, data, mock_exc, NoMargin();
            limits=(; leverage=(; min=1.0, max=100.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8)),
            precision=(; amount=8, price=2),
            fees=(; taker=0.001, maker=0.001, min=0.001, max=0.001),
        )
        uni = Collections.AssetCollection([ai_btc, ai_eth])
        cfg = Config(; qc=:USDT, initial_cash=10000.0, sandbox=true)
        s = Strategies.Strategy(
            @__MODULE__, Sim(), NoMargin(), tf, mock_exc, uni; config=cfg,
        )
        @test s isa Strategies.SimStrategy
        @test s isa Strategies.NoMarginStrategy
        @test Strategies.issim(s)
        @test !Strategies.ispaper(s)
        @test !Strategies.islive(s)
        @test Symbol(Strategies.exchangeid(typeof(s))) == :test
        @test Strategies.nameof(s) == :Runtests
        @test Strategies.nameof(typeof(s)) == :Strategy
        @test Strategies.execmode(s) isa Sim
        @test Strategies.marginmode(s) isa NoMargin
        @test :config in propertynames(s)
        @test s.config === cfg
        sym = Symbol(s)
        @test sym isa Symbol
        instances = Strategies.instances(s)
        @test length(instances) == 2
    end

    @testset "assets and universe" begin
        s = _make_strategy([:BTC, :ETH])
        assets = Strategies.assets(s)
        @test assets isa AbstractVector
        @test length(assets) == 2
        @test parse(AbstractAsset, "BTC/USDT") in assets
        @test parse(AbstractAsset, "ETH/USDT") in assets
        @test parse(AbstractAsset, "SOL/USDT") ∉ assets

        ais = Strategies.universe(s).data.instance
        @test length(ais) == 2
        @test all(Strategies.inuniverse(ai, s) for ai in ais)

        @test Strategies.inuniverse(parse(AbstractAsset, "BTC/USDT"), s)
        @test !Strategies.inuniverse(parse(AbstractAsset, "SOL/USDT"), s)
    end

    @testset "attrs and symsdict" begin
        s = _make_strategy([:BTC])
        attrs = Strategies.attrs(s)
        @test attrs isa Dict
        @test haskey(attrs, :exc)

        syms = Strategies.symsdict(s)
        @test syms isa Dict{String,Union{Nothing,AssetInstance}}
        @test isempty(syms)

        result = Strategies.asset_bysym(s, "BTC/USDT")
        @test result isa AssetInstance

        # Second call hits cached path (methods.jl:344)
        result_cached = Strategies.asset_bysym(s, "BTC/USDT")
        @test result_cached isa AssetInstance
        @test result_cached === result

        result2 = Strategies.asset_bysym(s, "NONEXISTENT")
        @test result2 === nothing
    end

    @testset "throttle" begin
        s = _make_strategy([:BTC])
        t = Strategies.throttle(s)
        @test t isa TimeTicks.Dates.Second
        @test t == Second(5)
    end

    @testset "cash operations" begin
        s = _make_strategy([:BTC], cash=10000.0, qc=:USDT)
        @test Strategies.cash(s) == 10000.0
        @test Strategies.freecash(s) == 10000.0
    end

    @testset "interface actions" begin
        s = _make_strategy([:BTC])
        @test Strategies.call!(s, Strategies.WarmupPeriod()) == s.timeframe.period
        Strategies.call!(s, Strategies.StartStrategy())
        Strategies.call!(s, Strategies.StopStrategy())
        Strategies.call!(s, Strategies.ResetStrategy())
    end

    @testset "exchange accessors" begin
        s = _make_strategy([:BTC])
        @test Symbol(Strategies.exchangeid(s)) == :test
        @test Symbol(Strategies.exchangeid(typeof(s))) == :test
        @test Strategies.account(s) == ""
    end

    @testset "getproperty forwarding" begin
        s = _make_strategy([:BTC])
        @test s.config isa Config
        @test s.qc == :USDT
        @test s.sandbox == true
        @test s.timeframe isa TimeFrame
        # Access via config.attrs (methods.jl:218)
        attr_exc = s.exc
        @test attr_exc == Strategies.attrs(s)[:exc]
    end

    @testset "name and symbol" begin
        s = _make_strategy([:BTC])
        @test Strategies.nameof(s) == :Runtests
        @test Symbol(s) == :Runtests
        try
            str = string(s)
            @test str isa String
        catch
            @warn "string(s) skipped: gateway unavailable"
        end
    end

    @testset "lock" begin
        s = _make_strategy([:BTC])
        lock(s)
        @test Strategies.cash(s) == 10000.0
        unlock(s)
        @test true  # reached without error
    end

    @testset "internal helpers" begin
        s = _make_strategy([:BTC])

        # _setmax!
        d = Dict(:a => 1)
        @test Strategies._setmax!(d, :a, 5) == 5
        @test d[:a] == 5
        @test Strategies._setmax!(d, :a, 3) == 5
        @test d[:a] == 5

        # _sizehint!
        c = [1, 2, 3]
        siz = Dict{Symbol,Int}()
        @test Strategies._sizehint!(c, siz, :test) === c
        @test siz[:test] >= 3

        # sizehint! on strategy (no-op smoke test)
        Strategies.sizehint!(s)
        @test true

        # sizehint! inner loops with non-empty buyorders/sellorders
        E = typeof(mock_exc.id)
        ai = first(Strategies.instances(s))
        bo = SortedDict{Strategies.PriceTime, Strategies.ExchangeBuyOrder{E}, Strategies.BuyPriceTimeOrdering}(Strategies.BuyPriceTimeOrdering())
        s.buyorders[ai] = bo
        so = SortedDict{Strategies.PriceTime, Strategies.ExchangeSellOrder{E}, Strategies.SellPriceTimeOrdering}(Strategies.SellPriceTimeOrdering())
        s.sellorders[ai] = so
        Strategies.sizehint!(s)
        @test haskey(Strategies.attrs(s), :_sizes)
    end

    @testset "print helpers" begin
        s = _make_strategy([:BTC, :ETH])
        ai = first(Strategies.instances(s))

        # trades_count with empty history
        @test Strategies.trades_count(s) == 0

        # trades_count liquidations
        liq = Strategies.trades_count(s, Val(:liquidations))
        @test liq.trades == 0
        @test liq.liquidations == 0

        # trades_count positions
        pos = Strategies.trades_count(s, Val(:positions))
        @test pos.long == 0
        @test pos.short == 0
        @test pos.liquidations == 0

        # _count_trades with empty AI
        long, short, long_liq, short_liq = Strategies._count_trades(ai)
        @test long == 0
        @test short == 0
        @test long_liq == 0
        @test short_liq == 0

        # orders accessors
        @test Strategies.orders(s, Strategies.Buy) === s.buyorders
        @test Strategies.orders(s, Strategies.Sell) === s.sellorders
        @test Base.count(s, Strategies.Buy) == 0
        @test Base.count(s, Strategies.Sell) == 0

        # _ascash
        result = Strategies._ascash((100.0, :USDT))
        @test result isa Strategies.Instances.Instruments.Cash

        # show short form (gateway-free)
        buf = IOBuffer()
        Base.show(buf, s)
        str = String(take!(buf))
        @test startswith(str, ":")
        @test occursin("Runtests", str)

        # Base.count inner loop with non-empty buyorders
        E = typeof(mock_exc.id)
        bo = SortedDict{Strategies.PriceTime, Strategies.ExchangeBuyOrder{E}, Strategies.BuyPriceTimeOrdering}(Strategies.BuyPriceTimeOrdering())
        s.buyorders[ai] = bo
        @test Base.count(s, Strategies.Buy) == 0
    end

    @testset "current_total" begin
        s = _make_strategy([:BTC], cash=10000.0)
        # No holdings -> current_total == cash(s)
        @test Strategies.current_total(s) == 10000.0
        @test Strategies.current_total(s, Strategies.lasttrade_price_func) == 10000.0

        # With non-empty holdings -> loop body executes
        ai = first(Strategies.instances(s))
        cash!(ai, 100.0)
        push!(s.holdings, ai)
        tot = Strategies.current_total(s)
        @test tot > 10000.0

        # minmax_holdings with non-empty holdings
        mmh = Strategies.minmax_holdings(s)
        @test mmh.count == 1
        @test mmh.min isa Tuple
        @test mmh.max isa Tuple
    end

    @testset "config edge cases" begin
        # Quote currency mismatch warning (module.jl:111)
        # AIs are BTC/USDT but strategy qc is :ETH
        s_mismatch = _make_strategy([:BTC]; qc=:ETH)
        @test Strategies.cash(s_mismatch) isa Number
    end

    @testset "lasttrade and tradesedge" begin
        s = _make_strategy([:BTC])
        ai = first(Strategies.instances(s))
        tf = TimeFrame("1m")
        data = SortedDict(tf => _make_ohlcv(50000.0))

        # lasttrade_price_func with empty history
        price = Strategies.lasttrade_price_func(ai)
        @test price isa Real
        @test price > 0

        # lasttrade_date with empty history -> falls back to OHLCV end
        ts = Strategies.lasttrade_date(ai)
        @test ts isa DateTime

        # tradesedge with no trades -> (nothing, nothing)
        ft, lt = Strategies.tradesedge(s)
        @test ft === nothing
        @test lt === nothing

        # tradesedge(DateTime) with no trades -> error
        @test_throws Exception Strategies.tradesedge(DateTime, s)

        # tradesperiod with no trades -> error
        @test_throws Exception Strategies.tradesperiod(s)

        # lasttrade_func with no trades -> returns last
        func = Strategies.lasttrade_func(s)
        @test func === last
    end

    @testset "strategy id" begin
        s = _make_strategy([:BTC])
        sid = Strategies.id(s)
        @test sid isa String
        @test occursin("Runtests", sid)
        @test occursin("test", sid)
    end

    @testset "more interface actions" begin
        s = _make_strategy([:BTC])
        cfg = Strategies.Instances.Misc.Config(; qc=:USDT, initial_cash=10000.0, sandbox=true)

        @test Strategies.call!(Strategy, cfg, Strategies.LoadStrategy()) === nothing
        @test Strategies.call!(s, Strategies.ResetStrategy()) === nothing
        @test Strategies.call!(Strategy, Strategies.StrategyMarkets()) == String[]
        @test Strategies.call!(s, Strategies.StartStrategy()) === nothing
        @test Strategies.call!(s, Strategies.StopStrategy()) === nothing
    end

    @testset "candle helpers" begin
        s = _make_strategy([:BTC])
        ai = first(Strategies.instances(s))
        tf = TimeFrame("1m")

        # closeat/openat/highat/lowat/volumeat are generated by @define_candle_func
        df = ohlcv(ai)
        @test df isa DataFrame
        date = DateTime(2024, 1, 1, 0, 1, 0)  # second row
        @test Strategies.closeat(df, date) isa Number
        @test Strategies.openat(df, date) isa Number
        @test Strategies.highat(df, date) isa Number
        @test Strategies.lowat(df, date) isa Number
        @test Strategies.volumeat(df, date) isa Number

        # lasttrade_price_func via AI data (empty history -> uses last close)
        price = Strategies.lasttrade_price_func(ai)
        @test price isa Real
        @test price == df.close[end]
    end
end

end # module Runtests
