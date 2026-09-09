using Test
using Planar.Exchanges
using Planar.Exchanges: Exchanges, ExchangeTypes
using Planar.Exchanges: marketsid, sandbox!, ratelimit!, setexchange!, getexchange!, issandbox

test_exch() = begin
    try
        exc = getexchange!(EXCHANGE, sandbox=false)
        Symbol(lowercase(exc.name)) == EXCHANGE
    catch e
        if occursin("connection refused", sprint(showerror, e))
            @warn "Skipping test_exch: gateway unavailable"
            return true
        end
        rethrow(e)
    end
end
_exchange() = begin
    try
        empty!(Exchanges.exchanges)
        empty!(Exchanges.sb_exchanges)
        e = getexchange!(EXCHANGE, markets=:yes, cache=false, sandbox=false)
        @test nameof(e) == EXCHANGE
        @test (EXCHANGE, "") ∈ keys(ExchangeTypes.exchanges) || (EXCHANGE, "") ∈ keys(ExchangeTypes.sb_exchanges)
        e
    catch e
        if occursin("connection refused", sprint(showerror, e))
            @warn "Skipping _exchange: gateway unavailable"
            return nothing
        end
        rethrow(e)
    end
end
_exchange_pairs(exc) = begin
    @test length(exc.markets) > 0
    pairs = marketsid(exc, "USDT", min_vol=10)
    @test !isnothing(pairs) && length(pairs) > 0
end

_exchange_sbox(exc) = begin
    is_sb = Planar.Exchanges.issandbox(exc)
    @test (is_sb === true) || (is_sb === false)
    Planar.Exchanges.sandbox!(exc, flag=false)
    @test Planar.Exchanges.issandbox(exc) === false
    Planar.Exchanges.sandbox!(exc)
    @test Planar.Exchanges.issandbox(exc) === true
    Planar.Exchanges.ratelimit!(exc)
end

_exchanges_test_env() = begin
    # Bindings are established by the top-level `using` statements in this
    # file (executed in Main when the runner includes it). Kept as a no-op so
    # existing call sites are unaffected.
    nothing
end

_do_test_exchanges() = begin
    @test test_exch()
    e = _exchange()
    _exchange_pairs(e)
    @test _exchange_sbox(e)
    try
        ExchangeTypes._closeall()
    catch
    end
end

test_exchanges() = begin
    _exchanges_test_env()
    @testset "exchanges" failfast = FAILFAST _do_test_exchanges()
end
