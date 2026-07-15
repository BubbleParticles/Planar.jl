#!/usr/bin/env julia

# examples/watchers/09_cp_markets.jl -- cp_markets_watcher
#
# Polls CoinPaprika markets for the given exchange ID.
# View type: Dict{String, CpTick}.
#
# Run:  cd /project && julia --project=Watchers examples/watchers/09_cp_markets.jl

using Watchers
using Watchers.WatchersImpls: cp_markets_watcher
using Watchers.Misc.TimeTicks

# -- Watcher construction ------------------------------------------
try
    global w = cp_markets_watcher("binance", Minute(5))
    println("cp_markets_watcher created:  name=$(w.name)")
    Watchers.fetch!(w)
    Watchers.process!(w)
    println("view: $(length(w.view)) symbols")
catch e
    @warn "cp_markets_watcher failed (likely network)" exception = e
    w = nothing
end

println(raw"""
cp_markets_watcher(exc_name, interval=Minute(3))

  exc_name: CoinPaprika exchange ID ("binance", "bybit-exchange", ...)
  interval: poll interval (second positional arg, default 3 min)

  Access:
      w.view  # Dict{String, CpTick}
""")
