#!/usr/bin/env julia

# use with strategies.service

import Pkg
# path of planar project
project = "$(ENV["HOME"])/dev/Planar.jl/PlanarDev"
Pkg.activate(project)

using Planar
@environment!

# runmode for all strategies
mode = Live()
sandbox = false
@info "strategy run mode $mode"

# set the strategies you want to run
config  = [
    (; name=:MyStrat, exchange=:myexchange, account="")
]

strats = st.Strategy[]

function start_strat(s)
    try
        start!(s, foreground=false)
    catch e
        @error "can't start strategy" exception = e
    end
end

for c in config
    @info "loading strategy $(c.name)"
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
