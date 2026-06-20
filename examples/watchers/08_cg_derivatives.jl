#!/usr/bin/env julia

# examples/watchers/08_cg_derivatives.jl -- cg_derivatives_watcher
#
# Polls CoinGecko derivatives for a given exchange.
# View type: Dict{Derivative, CgSymDerivative}.
#
# Run:  cd /project && julia --project=Watchers examples/watchers/08_cg_derivatives.jl

using Watchers
using Watchers.WatchersImpls: cg_derivatives_watcher

# -- Watcher construction ------------------------------------------
try
    global w = cg_derivatives_watcher("binance_futures")
    println("cg_derivatives_watcher created:  name=$(w.name)")
catch e
    @warn "cg_derivatives_watcher failed (likely network)" exception = e
    w = nothing
end

println(raw"""
cg_derivatives_watcher(exc_name)

  exc_name: CoinGecko derivatives exchange identifier
             ("binance_futures", "bybit", "dydx", ...)

  Access:
      w.view  # Dict{Derivative, CgSymDerivative}
""")
