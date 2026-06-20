#!/usr/bin/env julia

# examples/watchers/04_ohlcv_tickers.jl — ccxt_ohlcv_tickers_watcher
#
# Builds OHLCV candles by polling fetchTickers and using the chosen
# price source. View type: same as ccxt_tickers_watcher.
#
# Prerequisites: CcxtGateway running on localhost:8999
# Run:  cd /project && julia --project=Watchers examples/watchers/04_ohlcv_tickers.jl

using Watchers
using Watchers.WatchersImpls: ccxt_ohlcv_tickers_watcher
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
    global w = ccxt_ohlcv_tickers_watcher(
        exchange;
        syms         = ["BTC/USDT", "ETH/USDT"],
        timeframe    = tf"5m",
        price_source = :last,
        n_jobs       = 4,
        start        = false,
    )
    println("✓ ohlcv_tickers_watcher created:  name=$(w.name)")
else
    w = nothing
end

println(raw"""
ccxt_ohlcv_tickers_watcher(exc::Exchange;
    price_source   = :last,
    timeframe      = tf"1m",
    diff_volume    = true,
    n_jobs         = ratelimit_njobs(exc),
    callback       = Returns(nothing),
    load_timeframe = default_load_timeframe(timeframe),
    syms           = …)

  price_source:  :last | :vwap | :bid | :ask
  syms:  restrict tracked symbols (default: all markets)

Usage:
    start!(w)
    fetch!(w)
    load!(w, "BTC/USDT")
    stop!(w)
""")
