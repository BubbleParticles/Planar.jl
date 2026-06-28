#!/usr/bin/env julia

# examples/watchers/02_ohlcv_trades.jl — ccxt_ohlcv_watcher
#
# Builds OHLCV candles from the exchange trade feed (ONE symbol per instance).
# View type: Vector{CcxtTrade}.
#
# For multi-symbol OHLCV use ccxt_ohlcv_candles_watcher or
# ccxt_ohlcv_tickers_watcher.
#
# Prerequisites: CcxtGateway running + market data for the symbol.
# Run:  cd /project && julia --project=Watchers examples/watchers/02_ohlcv_trades.jl

using Watchers
using Watchers.WatchersImpls: ccxt_ohlcv_watcher
using Watchers.Misc.TimeTicks
using Exchanges

# ── Exchange setup (requires CcxtGateway) ──────────────────────────
ccxt_available = false
try
    using Watchers.Fetch.Exchanges: Exchange
    global exchange = getexchange!(:binance)
    global ccxt_available = true
    println("✓ Connected to CcxtGateway.")
catch e
    @warn "CcxtGateway unavailable — example shown as reference." exception = e
end

# ── Watcher construction ──────────────────────────────────────────
if ccxt_available
    try
        global w = ccxt_ohlcv_watcher(
            exchange, "BTC/USDT";
            timeframe = tf"1m",
            interval  = Second(5),
            start     = false,
            quiet     = true,
        )
        println("✓ ohlcv_trades_watcher created:  name=$(w.name)")
    catch e
        @warn "ohlcv_trades_watcher needs exchange markets loaded (stub has none)" exception = e
        global w = nothing
    end
else
    global w = nothing
end

println(raw"""
ccxt_ohlcv_watcher(exc::Exchange, sym;
    timeframe,
    interval       = Second(5),
    quiet          = true,
    start          = false,
    iswatch        = nothing,
    load_timeframe = default_load_timeframe(timeframe),
    load_path      = nothing)

  sym:  single trading pair ("BTC/USDT")
  timeframe:  tf"1m", tf"5m", tf"1h", …

On construction this watcher calls _load! to fast-forward candles,
which requires the exchange to have the symbol's market data.
""")
