#!/usr/bin/env julia

# examples/watchers/06_average_ohlcv.jl -- ccxt_average_ohlcv_watcher
#
# Aggregates OHLCV across multiple exchanges. For each candle:
#   open:   first open across sources
#   high:   maximum high
#   low:    minimum low
#   close:  volume-weighted average price (VWAP) of closes
#   volume: sum of volumes
# View type: Dict{String,DataFrame} (target symbol to aggregated OHLCV).
#
# Prerequisites: CcxtGateway running on localhost:8999
# Run:  cd /project && julia --project=Watchers examples/watchers/06_average_ohlcv.jl

using Watchers
using Watchers.WatchersImpls: ccxt_average_ohlcv_watcher
using Watchers.Misc.TimeTicks

# -- Exchange setup (requires CcxtGateway) -------------------------
ccxt_available = false
try
    using Watchers.Fetch.Exchanges: Exchange
    global exchange_a = Exchange("binance")
    global exchange_b = Exchange("bybit")
    global ccxt_available = true
    println("Connected to CcxtGateway.")
catch e
    @warn "CcxtGateway unavailable -- example shown as reference." exception = e
end

# -- Watcher construction ------------------------------------------
if ccxt_available
    try
        global w = ccxt_average_ohlcv_watcher(
            [exchange_a, exchange_b],
            ["BTC/USDT", "ETH/USDT"];
            timeframe    = tf"1m",
            input_source = :tickers,
            n_jobs       = 4,
        )
        global w
        println("average_watcher created:  name=$(w.name)")
    catch e
        @warn "average_watcher failed (needs exchanges with markets)" exception = e
        global w = nothing
    end
else
    global w = nothing
end

println(raw"""
ccxt_average_ohlcv_watcher(exchanges::Vector{<:Exchange}, syms;
    timeframe      = tf"1m",
    input_source   = :tickers,
    symbol_mapping = Dict{String,Vector{String}}(),
    n_jobs         = 8,
    callback       = Returns(nothing),
    load_timeframe = default_load_timeframe(timeframe))

  input_source:  :tickers | :trades | :klines

  symbol_mapping includes extra source symbols in the aggregation:
      Dict("BTC/USDT" => ["BTC/USD", "BTC/USDC"])
""")
