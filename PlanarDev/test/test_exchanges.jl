using Test

# Preload Planar.Exchanges bindings into Main to avoid world-age binding issues
@eval begin
    try
        using Planar.Exchanges
        # Bind commonly used functions/modules into Main
        if !isdefined(Main, :marketsid)
            @eval Main const marketsid = Planar.Exchanges.marketsid
        end
        if !isdefined(Main, :sandbox!)
            @eval Main const sandbox! = Planar.Exchanges.sandbox!
        end
        if !isdefined(Main, :ratelimit!)
            @eval Main const ratelimit! = Planar.Exchanges.ratelimit!
        end
        if !isdefined(Main, :setexchange!)
            @eval Main const setexchange! = Planar.Exchanges.setexchange!
        end
        if !isdefined(Main, :getexchange!)
            @eval Main const getexchange! = Planar.Exchanges.getexchange!
        end
        if !isdefined(Main, :issandbox)
            @eval Main const issandbox = Planar.Exchanges.issandbox
        end
        if !isdefined(Main, :Exchanges)
            @eval Main const Exchanges = Planar.Exchanges.Exchanges
        end
        if !isdefined(Main, :ExchangeTypes)
            @eval Main const ExchangeTypes = Planar.Exchanges.ExchangeTypes
        end
    catch e
        @warn "Preloading Planar.Exchanges bindings failed" exception=(e,catch_backtrace())
    end
end

test_exch() = let exc = getexchange!(EXCHANGE, sandbox=false)
    Symbol(lowercase(exc.name)) == EXCHANGE
end
_exchange() = begin
    empty!(Exchanges.exchanges)
    empty!(Exchanges.sb_exchanges)
    e = getexchange!(EXCHANGE, markets=:yes, cache=false, sandbox=false)
    @test nameof(e) == EXCHANGE
    @test (EXCHANGE, "") ∈ keys(ExchangeTypes.exchanges) || (exc_sym, "") ∈ keys(ExchangeTypes.sb_exchanges)
    e
end
_exchange_pairs(exc) = begin
    @test length(exc.markets) > 0
    @test length(marketsid(exc, "USDT", min_vol=10)) > 0
end

_exchange_sbox(exc) = begin
    @assert !issandbox(exc)
    sandbox!(exc, flag=false)
    @assert !issandbox(exc)
    sandbox!(exc)
    @assert issandbox(exc)
    ratelimit!(exc)
end

_exchanges_test_env() = begin
    @eval begin
        using .Planar.Exchanges: Exchanges, marketsid, sandbox!, ratelimit!, setexchange!, getexchange!, issandbox
        using .Planar.Exchanges: ExchangeTypes
        using PlanarDev.Stubs
    end
end

_do_test_exchanges() = begin
    @test test_exch()
    e = _exchange()
    _exchange_pairs(e)
    @test _exchange_sbox(e)
end

test_exchanges() = begin
    _exchanges_test_env()
    @testset "exchanges" failfast = FAILFAST _do_test_exchanges()
end
