#!/usr/bin/env julia

using Planar
@environment!

if "--help" in ARGS || "-h" in ARGS
    println("""
    Usage: run_single.jl <strategy_name> [mode]

    This script runs a single strategy in foreground mode.

    Arguments:
      <strategy_name>   Name of the strategy to run (required)
      [mode]            Mode to run: Sim, Paper, or Live (default: Paper)
                        (case-insensitive, e.g. 'sim', 'paper', 'live' are accepted)

    Options:
      -h, --help        Show this help message

    Example:
      julia run_single.jl MyStrategy sim
    """)
    exit(0)
end

strat_name = Symbol(get(ARGS, 1, ""))
strat_mode = let mode = get(ARGS, 2, "Paper") |> titlecase
    if !isnothing(match(r"sim"i, mode))
        Sim()
    elseif !isnothing(match(r"paper"i, mode))
        Paper()
    else
        Live()
    end
end
if strat_name == Symbol()
    error("no strategy name provided")
end
@info "loading strategy $strat_name"
@info "starting in $strat_mode mode"
s = st.strategy(strat_name; sandbox=false)

start!(s, foreground=true)
