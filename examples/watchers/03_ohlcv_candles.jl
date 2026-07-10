#!/usr/bin/env julia

# examples/watchers/03_ohlcv_candles.jl — ccxt_ohlcv_candles_watcher
#
# Fetches OHLCV candle data for multiple symbols from exchange APIs.
# View type: Dict{String,DataFrame} (symbol → OHLCV DataFrame).
#
# Prerequisites: CcxtGateway running on localhost:8999
# Run:  cd /project && julia --project=Watchers examples/watchers/03_ohlcv_candles.jl

using Watchers
using Watchers.WatchersImpls: ccxt_ohlcv_candles_watcher
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
    global w = ccxt_ohlcv_candles_watcher(
        exchange, ["BTC/USDT", "ETH/USDT", "SOL/USDT"];
        timeframe = tf"1m",
        n_jobs    = 4,
        start     = false,
    )
    println("✓ ohlcv_candles_watcher created:  name=$(w.name)")
else
    w = nothing
end
if ccxt_available
    # Start: spawns the fetch pipeline (REST polling) and, when supported,
    # a supplementary websocket handler. The view is populated on the first
    # tick (history) and kept up to date on subsequent ticks.
    start!(w)
    println("✓ ohlcv_candles_watcher started: history will be fetched shortly")
    # Give the first ticks time to fetch (binance rate-limits 3 symbols).
    sleep(10)
    for (sym, df) in w.view
        println("  $sym: $(isempty(df) ? "no data yet" : size(df, 1)) rows")
    end
end

println(raw"""
ccxt_ohlcv_candles_watcher(exc::Exchange, syms;
    timeframe       = tf"1m",
    logfile         = nothing,
    buffer_capacity = 100,
    view_capacity   = …,
    n_jobs          = ratelimit_njobs(exc),
    callback        = (df, sym) -> println("$sym updated: $(nrow(df)) rows"),
    load_timeframe  = default_load_timeframe(timeframe),
    load_path       = nothing)

  syms:  one or more trading pairs
  n_jobs:  concurrent fetch tasks (default: exchange rate-limit dependent)

Callback fires on every update per symbol:
    callback = (df, sym) -> println("$sym updated: $(size(df,1)) rows")
""")
