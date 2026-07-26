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
        @test (EXCHANGE, "") ∈ keys(ExchangeTypes.exchanges) || (exc_sym, "") ∈ keys(ExchangeTypes.sb_exchanges)
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
    try
        ExchangeTypes._closeall()
    catch
    end
end

test_exchanges() = begin
    _exchanges_test_env()
    @testset "exchanges" failfast = FAILFAST _do_test_exchanges()
end
