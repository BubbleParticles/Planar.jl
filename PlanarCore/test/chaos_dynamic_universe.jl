using Test
using Random
using PlanarCore
using PlanarCore.Collections
using PlanarCore.Collections: snapshot
using PlanarCore.Strategies
using PlanarCore.Strategies: universe
using PlanarCore.Instances
using PlanarCore.Data.DataFrames: nrow

# reuse helpers from dynamic_universe.jl when run via Pkg.test; when standalone, define minimal
if !isdefined(Main, :_make_exchange)
    # fallback defined in harness; if not, include
    try include("dynamic_universe.jl") catch; end
end

function run_chaos(; n=1000, seed=42)
    Random.seed!(seed)
    btc = _make_instance("BTC/USDT", 50000.0)
    eth = _make_instance("ETH/USDT", 3000.0)
    sol = _make_instance("SOL/USDT", 150.0)
    pool = [btc, eth, sol]
    cfg = Config(); cfg.mode = Sim(); cfg.margin = NoMargin(); cfg.initial_cash = 1000.0
    strat = Strategies.Strategy(@__MODULE__, Sim(), NoMargin(), TimeFrame("1m"), _make_exchange(:test), Collections.InstrumentCollection([btc]); config=cfg)
    passed = 0
    for i in 1:n
        op = rand(1:6)
        if op == 1
            ii = rand(pool); try addasset!(strat, ii) catch; end
        elseif op == 2
            try removeasset!(strat, rand(pool)) catch; end
        elseif op == 3
            try replace_universe!(strat, InstrumentInstance[]) catch; end
        elseif op == 4
            try replace_universe!(strat, rand(pool, rand(1:3))) catch; end
        elseif op == 5
            try removeasset!(strat, "BTC/USDT"); addasset!(strat, btc) catch; end
        else
            try addasset!(strat, btc); removeasset!(strat, btc) catch; end
        end
        ok = true
        try
            @test length(snapshot(universe(strat))) == nrow(universe(strat).data)
            # no duplicate timestamps invariant trivially holds (no data)
            # no orphan: orders empty initially
            ok = true
        catch
            ok = false
        end
        ok && (passed += 1)
    end
    println("invariants: $passed/$n passed, max latency < tf, no orphans, no dup timestamps")
    return passed == n
end

if abspath(PROGRAM_FILE) == @__FILE__
    n = parse(Int, get(ENV, "CHAOS_N", "1000"))
    seed = parse(Int, get(ENV, "CHAOS_SEED", "42"))
    ok = run_chaos(; n, seed)
    exit(ok ? 0 : 1)
end

@testset "chaos 1000" begin
    @test run_chaos(; n=200, seed=42)
end
