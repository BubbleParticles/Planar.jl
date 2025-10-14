#!/usr/bin/env julia

import Pkg

using Planar
@environment!

if "--help" in ARGS || "-h" in ARGS
    println("""
    Usage: run.jl [--planar <planar_path>] [--config <config_path>]

    This script runs multiple strategies in background mode.

    Options:
      --planar <planar_path>   Path to the Planar project to activate (default: PlanarDev)
                              Recommended options: Planar, PlanarDev
      --config <config_path>   Path to the strategies.toml file (default: strategies.toml in script directory)
      -h, --help               Show this help message

    Description:
      The script loads strategies defined in the config array and starts each one in background mode.
      It monitors the strategies and restarts any that stop running.

    Example:
      julia run.jl --planar PlanarDev --config /path/to/strategies.toml
      julia run.jl --config ./strategies.toml
    """)
    exit(0)
end

planar_path = "PlanarDev"
config_path = joinpath(@__DIR__, "strategies.toml")
for (i, arg) in enumerate(ARGS)
    if arg == "--planar" && i < length(ARGS)
        planar_path = ARGS[i+1]
    elseif arg == "--config" && i < length(ARGS)
        config_path = ARGS[i+1]
    end
end
project = "$(ENV["HOME"])/dev/Planar.jl/$planar_path"
Pkg.activate(project)

mode = Live()
sandbox = false
@info "strategy run mode $mode"
import TOML

toml_data = TOML.parsefile(config_path)
config = [
    (;
        name=Symbol(s["name"]),
        exchange=Symbol(s["exchange"]),
        account=s["account"],
        env=Dict{Symbol,String}([(Symbol(k), v) for (k, v) in s["env"]])
    ) for s in toml_data["strategy"]
]

strats = st.Strategy[]

function set_env(env)
    for (k, v) in pairs(env)
        ENV[string(k)] = string(v)
    end
end

function start_strat(s)
    try
        start!(s, foreground=false, with_stdout=false)
    catch e
        @error "can't start strategy" exception = e
    end
end

for c in config
    @info "loading strategy $(c.name)"
    set_env(c.env)
    s = st.strategy(c.name; mode, sandbox, c.exchange, c.account)
    start_strat(s)
    push!(strats, s)
end

monitor = @async while true
    for s in strats
        if !isrunning(s)
            start_strat(s)
        end
    end
    sleep(5)
end
@info "monitor task" monitor
@info "strategies array" strats
