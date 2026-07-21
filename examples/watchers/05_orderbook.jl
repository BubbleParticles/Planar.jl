#!/usr/bin/env julia

# examples/watchers/05_orderbook.jl -- ccxt_orderbook_watcher
#
# Fetches order book snapshots for a single symbol.
# View type: DataFrame (bid/ask price and amount columns).
#
# Prerequisites: CcxtGateway running on localhost:8999
# Run:  cd /project && julia --project=Watchers examples/watchers/05_orderbook.jl

using Watchers
using Watchers.WatchersImpls: ccxt_orderbook_watcher
using Watchers.Misc.TimeTicks

# -- Exchange setup (requires CcxtGateway) -------------------------
ccxt_available = false
try
    using Watchers.Fetch.Exchanges: Exchange
    global exchange = Exchange("binance")
    global ccxt_available = true
    println("Connected to CcxtGateway.")
catch e
    @warn "CcxtGateway unavailable -- example shown as reference." exception = e
end

# -- Watcher construction ------------------------------------------
if ccxt_available
    try
        global w = ccxt_orderbook_watcher(
            exchange, "BTC/USDT";
            level    = 1,       # 1=L1, 2=L2, 3=L3
            interval = Second(1),
        )
        global w
        println("orderbook_watcher created:  name=$(w.name)")
    catch e
        @warn "orderbook_watcher failed (needs exchange with order book support)" exception = e
        global w = nothing
    end
else
    global w = nothing
end

println(raw"""
ccxt_orderbook_watcher(exc::Exchange, sym;
    level    = L1,
    interval = Second(1))

  level:  1 (L1 top-of-book) | 2 (L2 full depth) | 3 (L3 w/ order ids)
  sym:  single trading pair

NOTE: This watcher auto-starts.
Access the latest snapshot:
    last(w.view)
""")
