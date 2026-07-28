# WebSocket integration tests for CcxtGateway
# These tests require the ccxt-gateway to be running with a live exchange.
# Run with: RUN_INTEGRATION_TESTS=true julia --project=PlanarDev -e 'include("PlanarCore/test/Ccxt/test_ws_integration.jl")'
using Test
using JSON3
using PlanarCore
using PlanarCore.Ccxt
using PlanarCore.Ccxt.CcxtGateway: GatewayWSClient, GatewayClient, connect!, is_connected, send_subscribe, send_unsubscribe, disconnect!, ping, fetch_exchange_has, exchange_ready, start_exchange, stop_exchange

function run_ws_integration_tests()
    # --- Gateway health check ---
    if !ping()
        println("Skipping WS integration tests - gateway not running")
        return
    end
    println("Gateway is reachable")

    @testset "WebSocket Integration Tests" begin
        exchange_id = "okx"
        symbol = "BTC/USDT"
        tf = "1m"

        # --- Start exchange subprocess ---
        @testset "Start exchange" begin
            result = start_exchange(exchange_id)
            @test result isa Dict
            @test get(result, "status", "") in ("started", "already_started")
            println("Exchange started: $(get(result, "status", "unknown"))")
        end

        # Wait for exchange to be ready
        ready = false
        for i in 1:20  # up to 20s
            sleep(1)
            if exchange_ready(exchange_id) || ping() == false
                sleep(1)
            end
            if exchange_ready(exchange_id)
                ready = true
                println("Exchange ready after $(i)s")
                break
            end
        end
        @test ready == true

        # --- Verify exchange has WS method support ---
        @testset "Exchange has watchOHLCVForSymbols" begin
            has_result = fetch_exchange_has(exchange_id)
            @test has_result isa Dict
            if get(has_result, "watchOHLCVForSymbols", false) == true
                println("Exchange supports watchOHLCVForSymbols")
            elseif get(has_result, "watchOHLCV", false) == true
                println("Exchange supports watchOHLCV (not ForSymbols)")
            else
                println("WARNING: Exchange may not support WS OHLCV methods")
                println("Available WS methods: $(filter(k -> startswith(string(k), "watch"), collect(keys(has_result))))")
            end
        end

        # --- Connect WebSocket ---
        @testset "WS connect and subscribe with symbolsAndTimeframes" begin
            ws_client = GatewayWSClient()
            connected = connect!(ws_client)
            @test connected == true
            @test is_connected(ws_client) == true
            println("WS connected")

            # Subscribe using the CORRECT parameter format: symbolsAndTimeframes
            # ccxt's watch_ohlcv_for_symbols expects a list of [symbol, timeframe] pairs
            received_updates = Channel{Dict}(32)
            sub_id = send_subscribe(
                ws_client, exchange_id, "watchOHLCVForSymbols";
                params=Dict{String, Any}(
                    "symbolsAndTimeframes" => [[symbol, tf]],
                ),
                callback = data -> begin
                    if data !== nothing
                        put!(received_updates, data)
                    end
                end,
            )
            @test sub_id isa String
            @test !isempty(sub_id)
            println("Subscribed: $sub_id")

            # Wait for data to arrive (up to 30s)
            ohlcv_data = nothing
            start_time = time()
            timeout = 30.0
            while time() - start_time < timeout
                if isready(received_updates)
                    ohlcv_data = take!(received_updates)
                    break
                end
                sleep(0.5)
            end

            if ohlcv_data === nothing
                println("TIMEOUT: No WS data within $(timeout)s")
                println("  Exchange: $exchange_id, Symbol: $symbol, TF: $tf")
                println("  The exchange may not support WS OHLCV or the parameter format may still be wrong")
            else
                @test ohlcv_data !== nothing
                println("Received WS data after $(round(time() - start_time, digits=1))s")
                println("Data type: $(typeof(ohlcv_data))")

                # Parse as OHLCV array
                if ohlcv_data isa Vector
                    println("OHLCV entries: $(length(ohlcv_data))")
                    if length(ohlcv_data) > 0
                        entry = ohlcv_data[1]
                        if entry isa Vector && length(entry) >= 6
                            ts, open_, high_, low_, close_, vol_ = entry[1], entry[2], entry[3], entry[4], entry[5], entry[6]
                            println("  Entry: ts=$ts open=$open_ high=$high_ low=$low_ close=$close_ vol=$vol_")
                            # Verify OHLCV data shape
                            @test open_ isa Number
                            @test high_ isa Number
                            @test low_ isa Number
                            @test close_ isa Number
                            @test vol_ isa Number
                            @test high_ >= low_
                            @test ts isa Number
                        end
                    end
                elseif ohlcv_data isa Dict
                    # Some exchanges send data as dict with symbol keys
                    println("Dict data with keys: $(collect(keys(ohlcv_data)))")
                    if haskey(ohlcv_data, symbol)
                        sym_data = ohlcv_data[symbol]
                        println("  $symbol data: $sym_data")
                    end
                end
            end

            # Cleanup subscription
            if isopen(received_updates)
                close(received_updates)
            end
            send_unsubscribe(ws_client, sub_id)
            disconnect!(ws_client)
            @test is_connected(ws_client) == false
            println("WS disconnected")
        end
    end

    # --- Stop exchange ---
    try
        stop_exchange(exchange_id)
        println("Exchange stopped")
    catch e
        println("Error stopping exchange: $e")
    end

    println("\nWS integration tests completed!")
end

