#!/usr/bin/env julia
# Test WebSocket subscription for watchOHLCV[ForSymbols] independently of the watcher pipeline.
#
# Tests three subscription methods in order:
#   1. watchOHLCVForSymbols with symbolsAndTimeframes pairs
#   2. watchOHLCV (singular) with individual [symbol, timeframe] pair
#
# Usage:
#   julia --project=PlanarDev scripts/test_ws_ohlcv.jl
#
# Or in REPL:  include("scripts/test_ws_ohlcv.jl")

using Ccxt.CcxtGateway: default_client, default_ws_client, connect!, send_subscribe,
    send_unsubscribe, is_connected, start_exchange
using Base: UUID

const EXCHANGE_ID = "binance"
const SYMBOLS = ["BTC/USDT", "ETH/USDT"]
const TIMEFRAME = "1m"
const RUNTIME_SECONDS = 30

function subscribe_and_listen(ws, method, params, label)
    println("\n" * "-"^60)
    println("Testing: $(EXCHANGE_ID).$method $label")
    println("-"^60)

    msg_count = Ref(0)
    start_time = time()

    sub_id = send_subscribe(
        ws, EXCHANGE_ID, method;
        params=params,
        callback = data -> begin
            msg_count[] += 1
            elapsed = round(time() - start_time; digits=1)
            if data === nothing
                println("  [$elapsed s] #$(msg_count[]): nothing")
            else
                T = typeof(data)
                summary = if data isa Union{Dict, JSON3.Object}
                    ks = join(collect(keys(data)), ", ")
                    "Dict{$(length(data))} keys=[$ks]"
                elseif data isa AbstractVector
                    "Vector{$(length(data))}"
                else
                    string(data)
                end
                println("  [$elapsed s] #$(msg_count[]): $T — $summary")
                if data isa Union{Dict, JSON3.Object}
                    for (tf, candles) in data
                        if candles isa AbstractVector && !isempty(candles)
                            println("    TF=$tf: $(length(candles)) candles, first=$(candles[1])")
                        end
                    end
                end
            end
        end,
    )

    if sub_id === nothing
        println("  ✗ Subscription failed (nil)")
        return false
    end
    println("  ✓ Subscribed, id=$sub_id")

    # Listen
    for sec in 1:RUNTIME_SECONDS
        sleep(1)
        if msg_count[] > 0
            rate = round(msg_count[] / sec; digits=2)
            print("\r  Received $(msg_count[]) messages ($rate msg/s)   ")
        else
            print("\r  Waiting... 0 messages ($sec/$(RUNTIME_SECONDS)s)")
        end
    end
    println()

    # Cleanup
    println("  Unsubscribing...")
    send_unsubscribe(ws, sub_id)

    elapsed = round(time() - start_time; digits=1)
    if msg_count[] > 0
        println("  ✓ $(msg_count[]) messages in $(elapsed)s")
        return true
    else
        println("  ✗ 0 messages in $(elapsed)s")
        return false
    end
end

function main()
    println("="^60)
    println("WS OHLCV Test — $(EXCHANGE_ID)")
    println("="^60)

    # 1. Start exchange subprocess
    println("\n[1] Starting exchange subprocess...")
    result = start_exchange(default_client(), EXCHANGE_ID)
    println("  → $result")

    # 2. Connect WS
    println("\n[2] Connecting WebSocket...")
    ws = default_ws_client()
    ok = connect!(ws)
    if !ok
        println("  ✗ connect! failed")
        return false
    end
    println("  ✓ Connected")

    results = Bool[]

    # --- Test A: watchOHLCVForSymbols with symbolsAndTimeframes (pairs) ---
    push!(results, subscribe_and_listen(
        ws, "watchOHLCVForSymbols",
        Dict{String,Any}(
            "symbolsAndTimeframes" => [[sym, TIMEFRAME] for sym in SYMBOLS],
        ),
        "(pairs format)",
    ))

    # --- Test B: watchOHLCV (singular) with one symbol ---
    push!(results, subscribe_and_listen(
        ws, "watchOHLCV",
        Dict{String,Any}(
            "symbolsAndTimeframes" => [["BTC/USDT", TIMEFRAME]],
        ),
        "(single symbol via symbolsAndTimeframes)",
    ))

    # --- Summary ---
    println("\n" * "="^60)
    println("Summary:")
    for (i, r) in enumerate(results)
        labels = ["A: watchOHLCVForSymbols pairs", "B: watchOHLCV single"]
        println("  $(labels[i]) — $(r ? "✓ WORKS" : "✗ SILENT")")
    end
    println("="^60)

    any(results) || (println("All tests failed. Check gateway log."); return false)
    return true
end

success = main()
if !success
    exit(1)
end
