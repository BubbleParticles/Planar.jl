#!/usr/bin/env julia

# examples/watchers/10_cp_twitter.jl -- cp_twitter_watcher
#
# Polls CoinPaprika Twitter activity for the given coin symbols.
# View type: Dict{String, Vector{CpTweet}}.
#
# Run:  cd /project && julia --project=Watchers examples/watchers/10_cp_twitter.jl

using Watchers
using Watchers.WatchersImpls: cp_twitter_watcher
using Watchers.Misc.TimeTicks

# -- Watcher construction ------------------------------------------
try
    global w = cp_twitter_watcher(["BTC", "ETH"], Minute(5))
    println("cp_twitter_watcher created:  name=$(w.name)")
catch e
    @warn "cp_twitter_watcher failed (likely network or API issue)" exception = e
    w = nothing
end

println(raw"""
cp_twitter_watcher(syms, interval=Minute(5))

  syms:  ticker symbols ("BTC", "ETH" -- resolved via cp.idbysym)
  interval: POSITIONAL argument (second positional, default 5 min)

  Access:
      w.view  # Dict{String, Vector{CpTweet}}
""")
