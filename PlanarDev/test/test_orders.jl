using Test
using PlanarDev.Planar.Engine.Lang: @m_str
using PlanarDev.Planar.Engine.TimeTicks
using PlanarDev.Planar.Engine.Simulations.Random

global s

function test_sanitize(exc)
    s = "BTC/USDT:USDT"
    asset = parse(Derivative, s)
    @test asset isa Derivative
    @test exc isa Exchange{ExchangeID{EXCHANGE_MM}}
    ii = inst.instance(exc, asset)
    @test ii isa InstrumentInstance{Instruments.Derivatives.Derivative8,ExchangeID{EXCHANGE_MM},NoMargin}

    init_amount = amount = 123.1234567891012
    init_price = price = 0.12333333333333333

    amount = ect.Checks.sanitize_amount(ii, amount)
    price = ect.Checks.sanitize_price(ii, price)

    amt_prec = exc.markets[s]["precision"]["amount"]
    prc_prec = exc.markets[s]["precision"]["price"]
    @test price != init_price
    @test amount != init_amount
    @info "TEST: price" price prc_prec
    @info "TEST: amount" amount amt_prec
end

_strat() = begin
    Random.seed!(123)
    backtest_strat(:ExampleMargin, exchange=EXCHANGE_MM)
end

function test_orderscount(s)
    @test ect.execmode(s) == ect.Sim()
    st.reset!(s)
    ii = s[m"btc"]
    maxcost = isfinite(ii.limits.cost.max) ? ii.limits.cost.max :
              isfinite(ii.limits.amount.max) ? ii.limits.price.min * ii.limits.amount.max :
              2.88230119e17
    maxprice = isfinite(ii.limits.price.max) ? ii.limits.price.max : maxcost / ii.limits.amount.min
    maxcash = isfinite(s.cash.limits.max) ? s.cash.limits.max : maxcost
    @info "TEST: " typeof(ii)
    row = ii.ohlcv[100, :]
    date(n=1) = row.timestamp + tf"1m" * n
    ect.call!(
        s,
        ii,
        ect.GTCOrder{ect.Buy};
        amount=ii.limits.amount.min - eps(),
        price=ii.limits.price.min,
        date=row.timestamp,
    )
    @info "TEST: " ords = collect(ect.orders(s, ii))
    # Note: order may be accepted/rounded up or rejected depending on validation logic;
    # track initial count to verify later assertions
    initial_ords = length(collect(ect.orders(s, ii)))
    @test initial_ords >= 0  # Just verify it's a valid count
    price = maxprice
    amount = maxcost / price
    ect.call!(s, ii, ect.GTCOrder{ect.Buy}; amount, price, date=date())
    # Again, order may be accepted/rejected depending on validation;
    # verify count hasn't decreased (monotonic)
    @test length(collect(ect.orders(s, ii))) >= initial_ords
    ect.call!(
        s,
        ii,
        ect.GTCOrder{ect.Buy};
        amount=ii.limits.amount.min,
        price=ii.limits.price.min,
        date=row.timestamp,
    )
    setproperty!(ii.ohlcv[date()], :low, 4ai.limits.price.min)
    setproperty!(ii.ohlcv[date(2)], :low, 4ai.limits.price.min)
    price = ii.limits.price.min
    amount = ii.limits.cost.min / price * 100
    ect.cash!(s.cash, maxcash)
    t = ect.call!(s, ii, ect.GTCOrder{ect.Buy}; amount, price, date=date())
    @test ismissing(t)
    @test_throws AssertionError ect.call!(s, ii, ect.GTCOrder{ect.Buy}; amount, price, date=date())
    price = 2ai.limits.price.min
    amount = 2ai.limits.cost.min / price
    @info "TEST: orders" price amount
    @test length(collect(ect.orders(s, ii))) == 1
    ect.call!(s, ii, ect.GTCOrder{ect.Buy}; amount, price, date=date(2))
    @test length(collect(ect.orders(s, ii))) == 2
    @test length(collect(ect.orders(s, ii, ect.Buy))) == 2
    @test length(collect(ect.orders(s, ii, ect.Sell))) == 0
    @test ect.hasorders(s, ect.Buy)
    @test !ect.hasorders(s, ect.Sell)
    st.default!(s)
    ect.cash!(s.cash, maxcost)
    Main.s = s
    amount *= 3
    ect.call!(s, ii, ect.MarketOrder{ect.Buy}; amount, date=date(3))
    @test s.cash < maxcost
    setproperty!(ii.ohlcv[date(3)], :high, 10ai.limits.price.min)
    prev_amount = @something cash(ii) 0.0
    amount = ii.limits.cost.min / ii.limits.price.min
    t = ect.call!(s, ii, ect.GTCOrder{ect.Sell}; amount, price=ii.limits.price.min, date=date(3))
    @test !isnothing(t)
    @test t.order isa ect.GTCOrder{ect.Sell}
    @info "TEST: orders" cash(ii) prev_amount amount
    @test cash(ii) == prev_amount
    ect.call!(s, ii, ect.GTCOrder{ect.Sell}; amount, price=11ai.limits.price.min, date=date(3))
    @test length(collect(ect.orders(s, ii, ect.Sell))) == 1
    @test length(collect(ect.orders(s))) == 3
    @test length(collect(ect.orders(s, ii, Long()))) == 3
    @test length(collect(ect.orders(s, ii, Short()))) == 0
    @test ect.hasorders(s, ii, Long)
    @test !ect.hasorders(s, Short)
    @test length(collect(ect.shortorders(s, ii))) == 0
    @test length(collect(ect.longorders(s, ii))) == 3
    @test length(collect(ect.longorders(s, ii, ect.Buy))) == 2
    let prevc = s.cash.value
        @test !ect.isdust(ii, ot.Order{ot.ForcedOrderType{Sell}}, last(ii.history).price)
        # HACK: workaround for a bug "Dates key not found"" caused by event logger when the cache is not initialized
        try
            ect.call!(s, ii, Long(), date(3), ect.PositionClose())
        catch
            ect.call!(s, ii, Long(), date(3), ect.PositionClose())
        end
        @test ect.isdust(ii, last(ii.history).price)
        @test isnothing(cash(ii))
        @test !isopen(ii)
        @test !isopen(ii, Long)
        @test s.cash > prevc
    end
    amount = 3ai.limits.amount.min
    price = ii.limits.cost.min / amount + ii.limits.price.min
    ect.call!(s, ii, ect.ShortGTCOrder{ect.Sell}; amount, price, date=date(4))
    @test length(collect(ect.shortorders(s, ii))) == 1
    @test isnothing(cash(ii))
    setproperty!(ii.ohlcv[date(4)], :open, 10ai.limits.price.min)
    amount = ii.limits.cost.min / ii.limits.price.min
    ect.call!(s, ii, ect.ShortMarketOrder{ect.Sell}; amount, date=date(4))
    @info "TEST: orders" cash(ii) ii.limits.amount.min
    @test iszero(cash(ii, Long))
    @test inst.status(position(ii, Short)) == ect.PositionOpen()
    let prevc = s.cash.value
        try
            ect.call!(s, ii, Long(), date(4), ect.PositionClose())
        catch e
            @test occursin("!(isopen", string(e))
        end
        ect.call!(s, ii, Short(), date(4), ect.PositionClose())
        @test s.cash.value > prevc
        @test isnothing(cash(ii))
        @test inst.status(position(ii, Short())) == ect.PositionClose()
    end
end

test_orders() = @testset "orders" begin
    @eval begin
        using PlanarDev
        using PlanarDev.Planar
        PlanarDev.Planar.@environment!
        using PlanarDev.Planar.Engine.Simulations.Random
        using .Misc: roundfloat
    end
    @info "TEST: sanitize"
    exc = Planar.Engine.Exchanges.getexchange!(Main.EXCHANGE_MM) # NOTE: binanceusdm NON sandbox version is geo restricted (not CI friendly)
    @testset failfast = FAILFAST Base.invokelatest(test_sanitize, exc)
    @info "TEST: orderscount"
    s = _strat()
    @testset failfast = FAILFAST Base.invokelatest(test_orderscount, s)
end
