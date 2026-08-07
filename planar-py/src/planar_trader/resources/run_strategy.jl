#!/usr/bin/env julia
# run_strategy.jl — bundled with the `planar-trader` pip package.
#
# Loads a strategy by name from the current project (user/planar.toml) and runs
# it in the requested mode. Mirrors scripts/run_single.jl in the Planar.jl repo.

using Planar
@environment!

const USAGE = """\
Usage: run_strategy.jl <strategy> [options]

Runs a Planar strategy from the current project directory.

Arguments:
  <strategy>               Strategy name (as registered under [sources] in
                           user/planar.toml)

Options:
  --mode <sim|paper|live>  Execution mode (default: sim)
  --exchange <id>          Exchange id (e.g. binance, binanceusdm)
  --sandbox                Use the exchange sandbox (default)
  --no-sandbox             Use the production exchange
  --account <name>         Exchange account
  -h, --help               Show this help
"""

function parse_args(args)
    name = nothing
    mode = "sim"
    exchange = nothing
    sandbox = true
    account = ""
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--mode"
            i += 1
            mode = lowercase(args[i])
        elseif a == "--exchange"
            i += 1
            exchange = Symbol(args[i])
        elseif a == "--sandbox"
            sandbox = true
        elseif a == "--no-sandbox"
            sandbox = false
        elseif a == "--account"
            i += 1
            account = args[i]
        elseif a == "-h" || a == "--help"
            println(USAGE)
            exit(0)
        elseif startswith(a, "-")
            error("unknown option: $a\n\n$USAGE")
        elseif name === nothing
            name = Symbol(a)
        else
            error("unexpected argument: $a\n\n$USAGE")
        end
        i += 1
    end
    isnothing(name) && (println(USAGE); exit(1))
    return (; name, mode, exchange, sandbox, account)
end

function main()
    opts = parse_args(ARGS)
    strat_mode = let m = opts.mode
        occursin("sim", m) ? Sim() :
            occursin("paper", m) ? Paper() : Live()
    end

    kwargs = Dict{Symbol,Any}(:sandbox => opts.sandbox)
    isnothing(opts.exchange) || (kwargs[:exchange] = opts.exchange)
    isempty(opts.account) || (kwargs[:account] = opts.account)

    @info "loading strategy" name = opts.name mode = strat_mode
    s = st.strategy(opts.name; kwargs...)
    if strat_mode isa Sim
        # Backtests run in-process; the one-arg form builds the Context.
        start!(s)
    else
        start!(s; foreground = true)
    end

    # Compact results report (best-effort; not all modes expose every metric).
    try
        println("── results ──")
        println("orders filled : ", ect.tradescount(s))
        println("final balance : ", st.current_total(s))
    catch e
        @debug "results report unavailable" exception = e
    end
end

main()
