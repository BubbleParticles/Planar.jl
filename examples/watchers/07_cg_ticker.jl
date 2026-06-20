#!/usr/bin/env julia

# examples/watchers/07_cg_ticker.jl -- cg_ticker_watcher
#
# Polls CoinGecko /coins/markets for the given symbols.
# View type: NamedTuple with one CgTick field per symbol.
#
# Symbols can be tickers ("BTC", "ETH") or CoinGecko IDs when byid=true.
# Run:  cd /project && julia --project=Watchers examples/watchers/07_cg_ticker.jl

using Watchers
using Watchers.WatchersImpls: cg_ticker_watcher
using Watchers.Misc.TimeTicks

# -- Watcher construction ------------------------------------------
try
    global w = cg_ticker_watcher(["BTC", "ETH"]; interval = Minute(5))
    println("cg_ticker_watcher created:  name=$(w.name)")
catch e
    @warn "cg_ticker_watcher failed (likely network)" exception = e
    w = nothing
end

println(raw"""
cg_ticker_watcher(syms; byid=false, interval=Second(360))

  syms:  ticker symbols ("BTC") or CoinGecko IDs ("bitcoin") when byid=true
  interval: poll interval (default 360s)

  Access:
      w.view  # NamedTuple{(:BTC, :ETH), Tuple{CgTick, CgTick}}
""")
