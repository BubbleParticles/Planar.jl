using Test

function _test_markets(name=EXCHANGE, pair="BTC/USDT")
    exc = getexchange!(name)
    @test exc isa Exchanges.CcxtExchange
    @test nameof(exc) == name
    # without cache
    loadmarkets!(exc; cache=false)
    @test length(exc.markets) > 0
    @test haskey(exc.markets, "BTC/USDT")
    empty!(exchanges)
    exc = getexchange!(name)
    # with cache
    loadmarkets!(exc; cache=true)
    @test length(exc.markets) > 0
    @test haskey(exc.markets, "BTC/USDT")

test_markets() = begin
    try
        @eval using .Planar.Exchanges: loadmarkets!, exchanges, getexchange!, Exchanges, ExchangeTypes
        _test_markets()
        try
            ExchangeTypes._closeall()
        catch
        end
    catch e
        if occursin("connection refused", sprint(showerror, e))
            @warn "Skipping markets test: gateway unavailable"
        else
            rethrow(e)
        end
    end
end
