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
    (; name=:SurgeV4, exchange=:phemex, account="1")
]

strats = st.Strategy[]

for c in config
    @info "loading strategy $(c.name)"
    s = st.strategy(c.name; mode, sandbox, c.exchange, c.account)
    start!(s, foreground=false)
    push!(strats, s)
end

monitor = @async while true
    for s in strats
        if !isrunning(s)
            try
                start!(s, foreground=false)
            catch e
                @error "can't re-start strategy" exception = e
            end
        end
    end
    sleep(5)
end
