using ..SimMode
using ..SimMode: Misc, Strategies, sml
using ..Strategies
using ..Strategies.Exchanges: Exchanges as exs, Instruments as im, Data
using ..Misc
using ..Misc.TimeTicks
using ..Misc.Lang
using ..Data: Data as da, Cache as ca
using ..Data.DataFrames: DataFrame
import ..Data: seeddata!
using CSV: CSV as CSV
using Pkg: Pkg

const PROJECT_PATH = try
    @something Base.ACTIVE_PROJECT[] Pkg.project().path
catch
    pkgdir(@__MODULE__)
end
const OHLCV_FILE_PATH = joinpath(PROJECT_PATH, "test", "stubs", "ohlcv.csv")

include("stub_strategy.jl")

function read_ohlcv()
    try
        CSV.read(OHLCV_FILE_PATH, DataFrame)
    catch e
        e isa InterruptException && rethrow(e)
        @error "stubs: read_ohlcv failed" exception=(e, catch_backtrace())
        rethrow(e)
    end
end

function stubscache_path()
    try
        proj = Pkg.project()
        @something get(ENV, "PLANAR_STUBS_PATH", nothing) joinpath(dirname(something(proj.path, PROJECT_PATH)), "test", "stubs")
    catch e
        e isa InterruptException && rethrow(e)
        @debug "stubs: stubscache_path fallback" exception=(e, catch_backtrace())
        env = get(ENV, "PLANAR_STUBS_PATH", nothing)
        isnothing(env) ? joinpath(PROJECT_PATH, "test", "stubs") : env
    end
end

function save_stubtrades(ii)
    ca.save_cache(
        "trades_stub_$(ii.asset.bc).jls", ii.history; cache_path=stubscache_path()
    )
end

# Strategy can't be saved because it has a module property and modules can't be deserialized
# function save_strategy(s)
#     ca.save_cache("strategy_stub_$(nameof(s))", s; cache_path=stubscache_path())
# end
# function load_strategy(name)
#     ca.load_cache("strategy_stub_$(name)"; cache_path=stubscache_path())
# end

function load_stubtrades(ii)
    try
        ca.load_cache("trades_stub_$(ii.asset.bc).jls"; cache_path=stubscache_path(), raise=false)
    catch e
        e isa InterruptException && rethrow(e)
        @error "stubs: load_stubtrades failed for $(ii.asset.bc)" exception=(e, catch_backtrace())
        nothing
    end
end

function load_stubtrades!(ii)
    try
        trades = load_stubtrades(ii)
        isnothing(trades) || append!(ii.history, trades)
    catch e
        e isa InterruptException && rethrow(e)
        @error "stubs: load_stubtrades! failed for $(ii.asset.bc)" exception=(e, catch_backtrace())
    end
end

@doc "Generates trades and saves them to the stubs shed."
function gensave_trades(n=10_000; s, dosave=true)
    try
        for ii in s.universe
            sml.synth_stub!(ii, n)
        end
    catch e
        e isa InterruptException && rethrow(e)
        @error "stubs: synth_stub! failed" exception=(e, catch_backtrace())
        rethrow(e)
    end
    try
        SimMode.start!(s; doreset=true)
    catch e
        e isa InterruptException && rethrow(e)
        @error "stubs: SimMode.start! in gensave_trades failed" exception=(e, catch_backtrace())
        rethrow(e)
    end
    if dosave
        for ii in s.universe
            try
                save_stubtrades(ii)
            catch e
                e isa InterruptException && rethrow(e)
                @error "stubs: save_stubtrades failed for $(ii.asset.bc)" exception=(e, catch_backtrace())
            end
        end
    end
end

function do_stub!(s::Strategy, n=10_000; trades=true)
    try
        for ii in s.universe
            sml.synth_stub!(ii, n)
        end
    catch e
        e isa InterruptException && rethrow(e)
        @error "stubs: synth_stub! in do_stub! failed" exception=(e, catch_backtrace())
        rethrow(e)
    end
    if trades
        for ii in s.universe
            try
                load_stubtrades!(ii)
            catch e
                e isa InterruptException && rethrow(e)
                @error "stubs: load_stubtrades! failed for $(ii.asset.bc)" exception=(e, catch_backtrace())
            end
        end
    end
    s
end

function stub_strategy(mod=StubStrategy, args...; dostub=true, cfg=Config(), kwargs...)
    s = try
        Strategies.strategy(mod, cfg; kwargs...)
    catch e
        e isa InterruptException && rethrow(e)
        @error "stubs: strategy construction failed" exception=(e, catch_backtrace())
        rethrow(e)
    end
    @assert s isa Strategy
    if dostub
        try
            Stubs.do_stub!(s)
        catch e
            e isa InterruptException && rethrow(e)
            @error "stubs: do_stub! in stub_strategy failed" exception=(e, catch_backtrace())
            rethrow(e)
        end
    end
    s
end

if get(ENV, "CCXT_GATEWAY_DISABLE", "") != "true"
@preset let
    cfg = Config()
    try
        @precomp let
            try
                s = stub_strategy(; cfg)
                gensave_trades(; s, dosave=true)
            catch e
                e isa InterruptException && rethrow(e)
                @debug "stubs: gensave_trades failed, retrying dostub=false" exception=(e, catch_backtrace())
                s = stub_strategy(; cfg, dostub=false)
                while any(isempty(ii.history) for ii in s.universe)
                    gensave_trades(; s, dosave=true)
                end
                for ii in s.universe
                    save_stubtrades(ii)
                end
                try
                    stub_strategy(; cfg, dostub=true)
                catch e2
                    e2 isa InterruptException && rethrow(e2)
                    if e2 isa UndefVarError
                        stub_strategy(; dostub=false)
                        @debug "stubs: " exception=(e2, catch_backtrace())
                    else
                        rethrow(e2)
                    end
                end
            end
        end
    catch e
        e isa InterruptException && rethrow(e)
        @debug "Stubs precompile workload skipped" exception=(e, catch_backtrace())
    end
end
end
