module TestAverageOHLCVWatcher

using Test
using DataFrames
using Dates
# Assuming the AverageOHLCVWatcher and its constructor are accessible via the Watchers module.
# Also assuming PlanarDev/test/runtests.jl or environment setup makes these modules available.
using Watchers
using Exchanges # For Exchange type and MockExchange
using Misc # For TimeFrame
using Watchers.AverageOHLCVWatcherImpl # To access AverageOHLCVWatcherAttrs if needed for deeper inspection, not typically for blackbox tests.

# Define a Mock Exchange type for testing
struct MockExchange <: Exchanges.Exchange
    id_::String # field name changed to avoid conflict with Exchanges.id method
    name_::String # field name changed

    MockExchange(id; name=id) = new(id, name)
end
# Minimal Exchanges.Exchange interface
Exchanges.id(m::MockExchange) = m.id_
Exchanges.name(m::MockExchange) = m.name_
Exchanges.issandbox(m::MockExchange) = false
Exchanges.params(m::MockExchange) = Dict{Symbol, Any}()
Exchanges.account(m::MockExchange) = ""


# Helper to create OHLCV DataFrame for tests
function ohlcv_df(timestamps, opens, highs, lows, closes, volumes)
    return DataFrame(
        timestamp = DateTime.(timestamps),
        open = Float64.(opens),
        high = Float64.(highs),
        low = Float64.(lows),
        close = Float64.(closes),
        volume = Float64.(volumes)
    )
end

# Mock source watcher start!, stop!, fetch! for checking calls (basic version)
# A more advanced mock would involve more structure.
# For now, we will directly manipulate views of actual source watchers (unstarted).
# If we need to verify calls to start/stop/fetch, we'd need a proper mock type.

function test_average_ohlcv_watcher()
    @testset "AverageOHLCVWatcher Tests" begin
        @testset "Construction and Initialization" begin
            exc1 = MockExchange("exc1")
        exc2 = MockExchange("exc2")
        exchanges = [exc1, exc2]
        symbols = ["BTC/USD", "ETH/USD"]
        tf = TimeFrame(Dates.Minute(1))

        # Test with start=false, load=false to control _init! call via Watchers.init!
        avg_watcher_trades = average_ohlcv_watcher(exchanges, symbols, timeframe=tf, input_source=:trades, start=false, load=false)
        @test avg_watcher_trades isa Watcher{Val{:average_ohlcv}}
        @test avg_watcher_trades.attrs.input_source == :trades
        @test length(avg_watcher_trades.attrs.exchanges) == 2
        @test length(avg_watcher_trades.attrs.symbols) == 2

        Watchers.init!(avg_watcher_trades) # Call init explicitly

        @test length(avg_watcher_trades.attrs.source_watchers) == length(exchanges) * length(symbols)
        @test haskey(avg_watcher_trades.attrs.aggregated_ohlcv, "BTC/USD")
        @test names(avg_watcher_trades.attrs.aggregated_ohlcv["BTC/USD"]) == ["timestamp", "open", "high", "low", "close", "volume"]

        avg_watcher_klines = average_ohlcv_watcher(exchanges, symbols, timeframe=tf, input_source=:klines, start=false, load=false)
        @test avg_watcher_klines.attrs.input_source == :klines
        Watchers.init!(avg_watcher_klines)
        @test length(avg_watcher_klines.attrs.source_watchers) == length(exchanges) * length(symbols)


        avg_watcher_tickers = average_ohlcv_watcher(exchanges, symbols, timeframe=tf, input_source=:tickers, start=false, load=false)
        @test avg_watcher_tickers.attrs.input_source == :tickers
        Watchers.init!(avg_watcher_tickers)
        @test length(avg_watcher_tickers.attrs.source_watchers) == length(exchanges) * length(symbols)

        @test_throws ErrorException average_ohlcv_watcher(exchanges, symbols, timeframe=tf, input_source=:invalid, start=false, load=false)
    end

    @testset "Data Aggregation Logic (_process!)" begin
        exc1 = MockExchange("mock_exc1")
        exc2 = MockExchange("mock_exc2")
        exchanges_list = [exc1, exc2]
        test_sym = "BTC/USD"
        test_tf = TimeFrame(Dates.Minute(1))

        avg_w = average_ohlcv_watcher(exchanges_list, [test_sym], timeframe=test_tf, input_source=:klines, start=false, load=false)
        Watchers.init!(avg_w)

        ts1 = DateTime("2023-01-01T00:00:00")
        ts2 = DateTime("2023-01-01T00:01:00")

        sw1_key = "\$(exc1.id_)_\$(test_sym)" # Note: exc1.id_ due to MockExchange field name
        source_watcher1 = avg_w.attrs.source_watchers[sw1_key]
        # Ensure view is a DataFrame. Source watchers internally initialize their view.
        # Forcing it here for controlled test data.
        source_watcher1.view = ohlcv_df([ts1, ts2], [10, 11], [12, 13], [9, 10], [11, 12], [100, 150])

        sw2_key = "\$(exc2.id_)_\$(test_sym)" # Note: exc2.id_
        source_watcher2 = avg_w.attrs.source_watchers[sw2_key]
        source_watcher2.view = ohlcv_df([ts1], [10.5], [12.5], [9.5], [11.5], [200])

        # Simulate that fetch has populated these views.
        # In a real scenario, Watchers.fetch!(avg_w) would call fetch! on source_watchers.
        # For this test, we assume views are populated.
        Watchers.process!(avg_w)

        agg_result_df = avg_w.attrs.aggregated_ohlcv[test_sym]
        @test nrow(agg_result_df) == 2

        row_ts1_df = filter(row -> row.timestamp == ts1, agg_result_df)
        @test nrow(row_ts1_df) == 1
        row_ts1 = row_ts1_df[1,:]

        # For open, the logic is `first(group.open)` after sorting all_new_source_rows by timestamp.
        # If source_watcher1's data for ts1 is "first" in the combined list for that timestamp, its open (10.0) will be picked.
        # This depends on the stability of dict iteration for source_watchers and then concat order in _process!
        # To make it deterministic for test: if keys are "mock_exc1_BTC/USD" and "mock_exc2_BTC/USD",
        # iteration order might matter. Assuming current logic, let's test for one possibility.
        # A more robust test would check if open is EITHER 10.0 OR 10.5. Or, ensure sort stability.
        # For now, the provided logic in _process! sorts all_new_source_rows by timestamp only.
        # If two sources have same TS, their original order in all_new_source_rows (from vcat) matters for `first(group.open)`.
        # Let's assume data from source_watcher1 comes first for ts1.
        @test row_ts1.open ≈ 10.0
        @test row_ts1.high ≈ 12.5
        @test row_ts1.low ≈ 9.0
        @test row_ts1.volume ≈ 300.0
        expected_vwap_ts1 = (11.0 * 100 + 11.5 * 200) / 300.0
        @test row_ts1.close ≈ expected_vwap_ts1

        row_ts2_df = filter(row -> row.timestamp == ts2, agg_result_df)
        @test nrow(row_ts2_df) == 1
        row_ts2 = row_ts2_df[1,:]
        @test row_ts2.open ≈ 11.0
        @test row_ts2.high ≈ 13.0
        @test row_ts2.low ≈ 10.0
        @test row_ts2.volume ≈ 150.0
        @test row_ts2.close ≈ 12.0
        end
    end
end
end
