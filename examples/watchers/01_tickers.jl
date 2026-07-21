#!/usr/bin/env julia

# examples/watchers/01_tickers.jl — ccxt_tickers_watcher
#
# Creates a Watcher that fetches ticker data for one or more symbols.
# View type: Dict{String,CcxtTicker} (symbol → CcxtTicker NamedTuple).
#
# Prerequisites: CcxtGateway running on localhost:8999
# Run:  cd /project && julia --project=Watchers examples/watchers/01_tickers.jl

using Watchers
using Watchers.WatchersImpls: ccxt_tickers_watcher
using Watchers.Misc.TimeTicks

# ── Exchange setup (requires CcxtGateway) ──────────────────────────
ccxt_available = false
try
    using Watchers.Fetch.Exchanges: Exchange
    global exchange = Exchange("binance")
    global ccxt_available = true
    println("✓ Connected to CcxtGateway.")
catch e
    @warn "CcxtGateway unavailable — example shown as reference." exception = e
end

# ── Watcher construction ──────────────────────────────────────────
if ccxt_available
    global w = ccxt_tickers_watcher(
        exchange;
        syms     = ["BTC/USDT", "ETH/USDT"],
        interval = Second(5),
        start    = false,
        process  = true,
        flush    = false,
    )
    println("✓ ticker_watcher created:  name=$(w.name)")
else
    w = nothing
end

println(raw"""
ccxt_tickers_watcher(exc::Exchange;
    syms     = keys(exc.markets),
    interval = Second(5),
    start    = true,
    process  = false,
    buffer_capacity = 100,
    view_capacity   = 2000,
    iswatch  = nothing)

  syms:  one or more trading pairs ("BTC/USDT", …)
  start: set false to defer start!()

Usage:
    start!(w)
    fetch!(w)
    w.view           # Dict{String,CcxtTicker}
    stop!(w)
""")
