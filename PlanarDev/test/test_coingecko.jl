using Test
using Planar.Engine.LiveMode.Watchers.CoinGecko
using Planar.Engine.Instruments
using Planar.Engine.TimeTicks
using Planar.Engine.Misc.Lang
using .Planar.Engine.TimeTicks: @dateformat_str
using Planar.Engine.Instruments.Derivatives: @d_str
using Planar.Engine.TimeTicks
using Planar.Engine.TimeTicks.Dates: format

const cg = CoinGecko

function test_coingecko()
    Planar.Engine.LiveMode.Watchers._closeall()
    invokelatest(() -> @testset failfast = FAILFAST "coingecko" begin
        @test cg.RATE_LIMIT[] isa Period
        cg.RATE_LIMIT[] = Millisecond(1 * 1000)
        @info "TEST: cg ping"
        ping_ok = try
            cg.ping()
        catch e
            @warn "coingecko ping failed, skipping coingecko tests" exception=e
            false
        end
        if !ping_ok
            @test_skip "coingecko unavailable (ping failed with 401/403)"
            return
        end
        @test ping_ok
        @info "TEST: cg rate limit"
        @test coingecko_ratelimit()
        @info "TEST: cg ids"
        @test occursin("eth", cg.idbysym("eth"))
        @test "ethereum" in cg.idbysym("eth", false)
        @info "TEST: cg price"
        @test coingecko_price()
        @info "TEST: cg load"
        @test length(cg.loadcoins!()) > 0
    end)
end

function coingecko_ratelimit()
    cg.ping()
    start = now()
    cg.ping()
    now() - start > cg.RATE_LIMIT[]
end

function coingecko_price()
    v = cg.price(["bitcoin", "ethereum"])
    "last_updated_at" ∈ keys(v["bitcoin"]) && "usd" ∈ keys(v["ethereum"])
end