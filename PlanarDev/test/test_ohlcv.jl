using Test


_test_ohlcv_exc(exc) = begin
    pair = "ETH/USDT" in keys(exc.markets) ? "ETH/USDT" : "ETH/USDT:USDT"
    timeframe = "5m"
    count = 500
    o = Planar.Engine.LiveMode.Watchers.Fetch.fetch_ohlcv(exc, timeframe, [pair]; from=-count, progress=false)
    @test pair ∈ keys(o)
    pd = o[pair]
    @test pd isa Planar.Engine.Data.PairData
    @test pd.name == pair
    @test pd.tf == timeframe
    @test pd.z isa Planar.Engine.Data.ZArray
    @test names(pd.data) == String.(Planar.Engine.Data.OHLCV_COLUMNS)
    @test size(pd.data)[1] > (count / 10 * 9) # if its less there is something wrong
    lastcandle = pd.data[end, :][1]
    @test Planar.Engine.Processing.islast(lastcandle, timeframe) || Planar.Engine.TimeTicks.now() - lastcandle.timestamp < s.timeframe
end

_test_ohlcv() = begin
    # if one exchange does not succeeds try on other exchanges
    # until one succeeds
    for e in unique((Main.EXCHANGE, Main.EXCHANGE_MM, :kucoin, :phemex, :binance))
        @debug "TEST: test_ohlcv" exchange = e
        exc = Planar.Engine.Exchanges.getexchange!(e)
        Planar.Engine.Exchanges.setexchange!(exc)
        _test_ohlcv_exc(exc)
    end
end

test_ohlcv() = @testset "ohlcv" begin
    @eval begin
        using .Planar.Engine.LiveMode.Watchers.Fetch
        using .Fetch.Exchanges
        using .Planar.Engine.Data: OHLCV_COLUMNS, ZArray, PairData
        using .Planar.Engine.Processing: islast
        using .Planar.Engine.TimeTicks
    end
    Base.invokelatest(_test_ohlcv)
end
