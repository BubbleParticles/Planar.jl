using Test
using Planar.Exchanges
using Planar.Exchanges: Exchanges, ExchangeTypes
using Planar.Exchanges: marketsid, sandbox!, ratelimit!, setexchange!, getexchange!, issandbox

_is_gateway_down(e) = occursin("connection refused", sprint(showerror, e))

test_exch() = begin
    exc = getexchange!(EXCHANGE, sandbox=false)
    @test Symbol(lowercase(exc.name)) == EXCHANGE
    true
end
_exchange() = begin
    saved_exchanges = copy(Exchanges.exchanges)
    saved_sb = copy(Exchanges.sb_exchanges)
    try
        empty!(Exchanges.exchanges)
        empty!(Exchanges.sb_exchanges)
        e = getexchange!(EXCHANGE, markets=:yes, cache=false, sandbox=false)
        @test nameof(e) == EXCHANGE
        @test (EXCHANGE, "") ∈ keys(ExchangeTypes.exchanges) || (EXCHANGE, "") ∈ keys(ExchangeTypes.sb_exchanges)
        e
    finally
        merge!(Exchanges.exchanges, saved_exchanges)
        merge!(Exchanges.sb_exchanges, saved_sb)
    end
end
_exchange_pairs(exc) = begin
    @test length(exc.markets) > 0
    pairs = marketsid(exc, "USDT", min_vol=10)
    @test !isnothing(pairs) && length(pairs) > 0
end

_exchange_sbox(exc) = begin
    # _exchange() requests sandbox=false, so the initial state is pinned here.
    @test Planar.Exchanges.issandbox(exc) === false
    Planar.Exchanges.sandbox!(exc, flag=false)
    @test Planar.Exchanges.issandbox(exc) === false
    Planar.Exchanges.sandbox!(exc)
    @test Planar.Exchanges.issandbox(exc) === true
    Planar.Exchanges.ratelimit!(exc)
    # ratelimit! must not corrupt sandbox state
    @test Planar.Exchanges.issandbox(exc) === true
end

_exchanges_test_env() = begin
    # Bindings are established by the top-level `using` statements in this
    # file (executed in Main when the runner includes it). Kept as a no-op so
    # existing call sites are unaffected.
    nothing
end

_do_test_exchanges() = begin
    local e
    try
        @test test_exch()
        e = _exchange()
    catch err
        if _is_gateway_down(err)
            @test_skip "gateway unavailable — exchanges suite skipped"
            return nothing
        end
        rethrow(err)
    end
    _exchange_pairs(e)
    _exchange_sbox(e)
    @test e isa Exchanges.CcxtExchange
    try
        ExchangeTypes._closeall()
    catch err
        @warn "teardown _closeall failed" exception = (err, catch_backtrace())
    end
end
