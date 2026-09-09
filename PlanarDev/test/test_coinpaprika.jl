using Test

@eval begin
    using .Planar.Engine.LiveMode.Watchers.CoinPaprika
    using .Planar.Engine.Instruments
    using .Planar.Engine.TimeTicks
    using .CoinPaprika.JSON3
    using .Planar.Engine.Data: Candle
    const cpr = CoinPaprika
    const JSON3 = CoinPaprika.JSON3
end

function test_coinpaprika()
    invokelatest(() -> @testset "coinpaprika" begin
        @test test_ratelimit()
        @test test_twitter()
        @test test_cp_exchanges()
        # Live API: network failures skip instead of passing silently.
        try
            @test (unix2datetime(cpr.glob()["last_updated"]) > now() - Day(1))
            @test "btc-bitcoin" ∈ keys(cpr.loadcoins!())
        markets = cpr.coin_markets("eth-ethereum")
        @test markets isa Dict
        @test cpr.coin_ohlcv("xmr-monero") isa Candle
        catch e
            @test_skip "CoinPaprika live fetch failed: $e"
        end
        @test test_cp_markets()
        @test test_tickers()
        @test cpr.ticker("btc-bitcoin") isa Dict{String,Float64}
        betas = cpr.betas()
        @test betas isa NamedTuple
        @test length(betas.coins) == length(betas.betas)
        @test cpr.hourly("btc-bitcoin").timestamp[begin] > now() - Day(1)
    end)
end

function test_twitter()
    tw = cpr.twitter("btc-bitcoin")
    tw isa JSON3.Array && length(tw) > 25 && occursin("bitcoin", string(tw))
end

function test_ratelimit()
    prev = cpr.query_stack[]
    try
        cpr.coin_ohlcv("btc-bitcoin")
        cpr.query_stack[] = 1
        start = now()
        cpr.coin_ohlcv("btc-bitcoin")
        return cpr.query_stack[] == 0 &&
            now() - start < Second(1) &&
            (cpr.addcalls!(100); cpr.query_stack[] == 100)
    finally
        cpr.query_stack[] = prev
    end
end

function test_cp_exchanges()
    excs = cpr.coin_exchanges("btc-bitcoin")
    "binance" in keys(excs)
end

function test_cp_markets()
    excs = cpr.loadexchanges!()
    one = "binance" ∈ keys(excs)
    mkt = cpr.markets("binance")
    one && "BTC/USDT:Spot" ∈ keys(mkt)
end

function test_tickers()
    tkrs = cpr.tickers()
    "btc-bitcoin" in keys(tkrs) && tkrs isa Dict{String,Dict{String,Float64}}
end
