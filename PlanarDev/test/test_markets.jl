using Test

function _test_markets(name=EXCHANGE, pair="BTC/USDT")
    exc = getexchange!(name)
    @test exc isa Exchanges.CcxtExchange
    @test nameof(exc) == name
    @test length(exc.markets) > 0
    # without cache
    @test_nowarn loadmarkets!(exc; cache=false)
    empty!(exchanges)
    exc = getexchange!(name)
    # with cache
    @test_nowarn loadmarkets!(exc; cache=true)
end

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
