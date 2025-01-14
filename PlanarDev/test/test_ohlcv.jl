using Test


_test_ohlcv_exc(exc) = begin
    pair = "ETH/USDT" in keys(exc.markets) ? "ETH/USDT" : "ETH/USDT:USDT"
    timeframe = "5m"
    count = 500
    o = fetch_ohlcv(exc, timeframe, [pair]; from=-count, progress=false)
    @test pair ∈ keys(o)
    pd = o[pair]
    @test pd isa PairData
    @test pd.name == pair
    @test pd.tf == timeframe
    @test pd.z isa ZArray
    @test names(pd.data) == String.(OHLCV_COLUMNS)
    @test size(pd.data)[1] > (count / 10 * 9) # if its less there is something wrong
    lastcandle = pd.data[end, :][1]
    @test islast(lastcandle, timeframe) || now() - lastcandle.timestamp < s.timeframe
end

_test_ohlcv() = begin
    # if one exchange does not succeeds try on other exchanges
    # until one succeeds
    for e in unique((EXCHANGE, EXCHANGE_MM, :kucoin, :phemex, :binance))
        @debug "TEST: test_ohlcv" exchange = e
        exc = getexchange!(e)
        setexchange!(exc)
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
    _test_ohlcv()
end
