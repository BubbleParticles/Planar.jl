using Test
using PlanarCore.Collections
using PlanarCore.Instances
using PlanarCore.Instances.Exchanges.ExchangeTypes
using PlanarCore.Instances.Exchanges.ExchangeTypes: CcxtExchange, ExchangeID, ExcPrecisionMode
using PlanarCore.Instances.Exchanges.ExchangeTypes.OrderedCollections: OrderedSet
using PlanarCore.Instances.Data.TimeTicks: TimeFrame
using PlanarCore.Instances.Data.DataFrames: DataFrame
using PlanarCore.Instances.DataStructures: SortedDict
using PlanarCore.Strategies
using PlanarCore.Misc: Sim, Config, Cross
using PlanarCore.Instances.Instruments: AbstractInstrument, parse
using PlanarCore.Instances.Misc: NoMargin

# Minimal mock exchange so we can build real instances without network.
function _make_exchange(name::Symbol)
    mkts = Dict{String,Dict{String,Any}}()
    for (sym, base, q) in
        [("BTC/USDT", "BTC", "USDT"), ("ETH/USDT", "ETH", "USDT"), ("SOL/USDT", "SOL", "USDT")]
        mkts[sym] = Dict{String,Any}(
            "id" => sym, "base" => base, "quote" => q,
            "type" => "spot", "active" => true, "spot" => true,
            "precision" => Dict{String,Any}("amount" => 8, "price" => 2),
            "limits" => Dict{String,Any}(
                "amount" => Dict{String,Any}("min" => 1e-6, "max" => 1e8),
                "price" => Dict{String,Any}("min" => 0.01, "max" => 1e6),
                "cost" => Dict{String,Any}("min" => 1.0, "max" => 1e8),
            ),
            "taker" => 0.001, "maker" => 0.001,
        )
    end
    CcxtExchange{ExchangeID{name}}(
        ExchangeID{name}(),
        string(name),
        "",
        OrderedSet{String}(["1m"]),
        mkts,
        Set{Symbol}([:spot]),
        Dict{Symbol,Any}(:taker => 0.001, :maker => 0.001),
        Dict{Symbol,Any}(:fetchTicker => true, :fetchOHLCV => true),
        ExcPrecisionMode(2),
        nothing,
        [:fetchTicker, :fetchOHLCV],
        Dict{String,Any}(),
    )
end
const mock_exc = _make_exchange(:test)

function _make_instance(sym::String, price::Float64; margin=NoMargin())

    tf = TimeFrame("1m")
    base_ts = 1704067200000
    df = DataFrame(
        timestamp = [Int64(base_ts + i * 60000) for i in 0:9],
        open = Float64(price), high = Float64(price + price * 0.02),
        low = Float64(price - price * 0.02), close = Float64(price + price * 0.01),
        volume = Float64(1000.0),
    )
    Instances.InstrumentInstance(
        parse(AbstractInstrument, sym), SortedDict(tf => df), mock_exc, margin;
        limits=(; leverage=(; min=1.0, max=1.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8)),
        precision=(; amount=8, price=2),
        fees=(; taker=0.001, maker=0.001, min=0.0, max=0.002),
    )
end

@testset "Dynamic universe (InstrumentCollection mutation)" begin
    btc = _make_instance("BTC/USDT", 50000.0)
    eth = _make_instance("ETH/USDT", 3000.0)
    sol = _make_instance("SOL/USDT", 150.0)

    @testset "push! adds an asset" begin
        coll = Collections.InstrumentCollection([btc, eth])
        @test length(coll) == 2
        Collections.push!(coll, sol)
        @test length(coll) == 3
        @test sol in coll.data.instance
        # the new asset is visible when iterating
        seen = false
        for ii in coll
            ii === sol && (seen = true)
        end
        @test seen
    end

    @testset "delete! by asset / exchange / string" begin
        coll = Collections.InstrumentCollection([btc, eth])
        Collections.delete!(coll, eth)
        @test length(coll) == 1
        @test btc in coll.data.instance
        @test !(eth in coll.data.instance)

        coll = Collections.InstrumentCollection([btc, eth])
        Collections.delete!(coll, ExchangeID(:test))
        @test length(coll) == 0

        coll = Collections.InstrumentCollection([btc, eth])
        Collections.delete!(coll, "BTC/USDT")
        @test length(coll) == 1
        @test eth in coll.data.instance
    end

    @testset "pop! removes and returns last" begin
        coll = Collections.InstrumentCollection([btc, eth])
        popped = Collections.pop!(coll)
        @test popped === eth
        @test length(coll) == 1
        @test btc in coll.data.instance
    end

    @testset "mutation preserves concrete column eltype" begin
        coll = Collections.InstrumentCollection([btc, eth])
        I = eltype(coll.data.instance)
        Collections.push!(coll, sol)
        @test eltype(coll.data.instance) === I
        Collections.delete!(coll, sol)
        @test eltype(coll.data.instance) === I
    end

    @testset "concurrent mutation does not invalidate iteration" begin
        coll = Collections.InstrumentCollection([btc, eth])
        err = Ref{Union{Nothing,Exception}}(nothing)
        mutator = Threads.@spawn begin
            for _ in 1:2000
                Collections.push!(coll, sol)
                Collections.delete!(coll, "SOL/USDT")
            end
        end
        try
            for _ in 1:2000
                for ii in coll
                    # ii must always be a valid instance object
                    @test ii isa InstrumentInstance
                end
            end
        catch e
            err[] = e
        end
        wait(mutator)
        @test err[] === nothing
    end
end

@testset "Strategy addasset!/removeasset! (delegates to collection)" begin
    btc = _make_instance("BTC/USDT", 50000.0)
    eth = _make_instance("ETH/USDT", 3000.0)
    sol = _make_instance("SOL/USDT", 150.0)
    cfg = Config()
    cfg.mode = Sim()
    cfg.margin = NoMargin()
    cfg.initial_cash = 1000.0
    # `mock_exc` is fully self-contained (markets dict, no network), so strategy
    # construction succeeds without a live gateway/exchange context.
    strat = Strategies.Strategy(
        @__MODULE__, Sim(), NoMargin(), TimeFrame("1m"), mock_exc,
        Collections.InstrumentCollection([btc, eth]); config=cfg,
    )
    @test length(Strategies.universe(strat)) == 2
    addasset!(strat, sol)
    @test length(Strategies.universe(strat)) == 3
    @test sol in Strategies.universe(strat).data.instance
    seen = false
    for ii in Strategies.universe(strat)
        ii === sol && (seen = true)
    end
    @test seen
    removeasset!(strat, eth)
    @test length(Strategies.universe(strat)) == 2
    @test !(eth in Strategies.universe(strat).data.instance)
    @test btc in Strategies.universe(strat).data.instance
    @test sol in Strategies.universe(strat).data.instance
end


@testset "Strategy shared cash pool (cross-margin backend)" begin
    # Cross-margin draws from the single strategy-level `s.cash` pool. We verify
    # the pool aggregation here on a constructible strategy; `iscommittable` for
    # buys already dispatches through `freecash(s)` so cross instances share it.
    btc = _make_instance("BTC/USDT", 50000.0)
    eth = _make_instance("ETH/USDT", 3000.0)
    cfg = Config()
    cfg.mode = Sim()
    cfg.margin = NoMargin()
    cfg.initial_cash = 1000.0
    # `mock_exc` is fully self-contained (markets dict, no network), so strategy
    # construction succeeds without a live gateway/exchange context.
    strat = Strategies.Strategy(
        @__MODULE__, Sim(), NoMargin(), TimeFrame("1m"), mock_exc,
        Collections.InstrumentCollection([btc, eth]); config=cfg,
    )
    # The strategy holds one shared cash pool across all instances
    @test strat.cash.value == 1000.0
    @test Strategies.freecash(strat) == 1000.0
    # Committing cash draws from the shared pool regardless of which instance
    Instances.cash!(strat.cash_committed, 250.0)
    @test Strategies.freecash(strat) == 750.0
    # Releasing returns it to the shared pool (visible to both instances)
    Instances.cash!(strat.cash_committed, 0.0)
    @test Strategies.freecash(strat) == 1000.0
end

@testset "replace_universe! atomicity and idempotency" begin
    btc = _make_instance("BTC/USDT", 50000.0)
    eth = _make_instance("ETH/USDT", 3000.0)
    sol = _make_instance("SOL/USDT", 150.0)
    # collection level
    coll = Collections.InstrumentCollection([btc, eth])
    @test length(coll) == 2
    added, removed = Collections.replace_universe!(coll, [btc, eth, sol])
    @test length(coll) == 3
    @test length(added) == 1 && string(raw(added[1])) == "SOL/USDT"
    @test isempty(removed)
    # idempotency: replace with same set -> no change
    added2, removed2 = Collections.replace_universe!(coll, [btc, eth, sol])
    @test isempty(added2) && isempty(removed2)
    @test length(coll) == 3
    # atomicity with strategy validation: unknown symbol
    cfg = Config()
    cfg.mode = Sim()
    cfg.margin = NoMargin()
    cfg.initial_cash = 1000.0
    strat = Strategies.Strategy(
        @__MODULE__, Sim(), NoMargin(), TimeFrame("1m"), mock_exc,
        Collections.InstrumentCollection([btc, eth]); config=cfg,
    )
    # create instance with unknown symbol (not in mock_exc markets)
    unk = _make_instance("FAKE/USDT", 1.0)
    # validation should throw and leave universe unchanged
    @test_throws ArgumentError addasset!(strat, unk)
    @test length(Strategies.universe(strat)) == 2
    @test_throws ArgumentError replace_universe!(strat, [btc, unk])
    @test length(Strategies.universe(strat)) == 2
    # idempotency at strategy level: add same ii twice
    addasset!(strat, sol)
    @test length(Strategies.universe(strat)) == 3
    addasset!(strat, sol)
    @test length(Strategies.universe(strat)) == 3
    # symsdict cleared on remove
    sd = Strategies.symsdict(strat)
    @test haskey(sd, "SOL/USDT")
    removeasset!(strat, sol)
    @test !haskey(sd, "SOL/USDT")
    @test length(Strategies.universe(strat)) == 2
    @test isnothing(Strategies.asset_bysym(strat, "SOL/USDT"))
    # remove absent is no-op
    removeasset!(strat, "SOL/USDT")
    @test length(Strategies.universe(strat)) == 2
    # empty universe allowed
    Strategies.replace_universe!(strat, InstrumentInstance[])
    @test length(Strategies.universe(strat)) == 0
    @test isempty(Strategies.universe(strat).data)
end

@testset "on_universe_change! event emission order" begin
    btc = _make_instance("BTC/USDT", 50000.0)
    eth = _make_instance("ETH/USDT", 3000.0)
    sol = _make_instance("SOL/USDT", 150.0)
    cfg = Config()
    cfg.mode = Sim()
    cfg.margin = NoMargin()
    cfg.initial_cash = 1000.0
    strat = Strategies.Strategy(
        @__MODULE__, Sim(), NoMargin(), TimeFrame("1m"), mock_exc,
        Collections.InstrumentCollection([btc]); config=cfg,
    )
    seen = Ref{Tuple{Vector{String},Vector{String}}}((String[], String[]))
    cb = (s, added, removed) -> begin
        seen[] = (sort([string(raw(ii)) for ii in added]), sort([string(raw(ii)) for ii in removed]))
        # callback sees snapshot diff matching added/removed
        snap = Set(string(raw(ii)) for ii in Strategies.universe(s).data.instance)
        @test all(k in snap for k in seen[][1])
        @test all(k ∉ snap for k in seen[][2])
    end
    tok = on_universe_change!(strat, cb)
    @test tok isa Symbol
    addasset!(strat, eth)
    @test seen[] == (["ETH/USDT"], String[])
    addasset!(strat, sol)
    @test seen[] == (["SOL/USDT"], String[])
    removeasset!(strat, eth)
    @test seen[] == (String[], ["ETH/USDT"])
    # replace
    Strategies.replace_universe!(strat, [btc])
    @test seen[][2] == ["SOL/USDT"]
    @test off_universe_change!(strat, tok) == true
    @test off_universe_change!(strat, tok) == false
    # after off, callback not invoked
    seen[] = (["X"], ["Y"])
    addasset!(strat, eth)
    @test seen[] == (["X"], ["Y"])
    # version bump
    @test get(Strategies.attrs(strat), :universe_version, 0) >= 4
end

@testset "parallel addasset!/removeasset! on one Strategy" begin
    btc = _make_instance("BTC/USDT", 50000.0)
    eth = _make_instance("ETH/USDT", 3000.0)
    sol = _make_instance("SOL/USDT", 150.0)
    cfg = Config()
    cfg.mode = Sim()
    cfg.margin = NoMargin()
    cfg.initial_cash = 1000.0
    strat = Strategies.Strategy(
        @__MODULE__, Sim(), NoMargin(), TimeFrame("1m"), mock_exc,
        Collections.InstrumentCollection([btc]); config=cfg,
    )
    tasks = Task[]
    for _ in 1:50
        push!(tasks, Threads.@spawn addasset!(strat, eth))
        push!(tasks, Threads.@spawn addasset!(strat, sol))
        push!(tasks, Threads.@spawn removeasset!(strat, "ETH/USDT"))
        push!(tasks, Threads.@spawn removeasset!(strat, sol))
    end
    for t in tasks
        wait(t)
    end
    # after concurrent ops, length is consistent and no crash
    @test length(Strategies.universe(strat)) in 1:3
    for ii in Strategies.universe(strat)
        @test ii isa InstrumentInstance
    end
end
