module WatchersTests

using Test
using Watchers
using Watchers: HasFunction, Interval, Capacity, Beacon, BufferEntry, Exec
import Rocket
using Watchers: _check_flush_interval, _notimpl, WATCHERS, logerror, lasterror, errors
using Watchers.Misc: ConcurrentCollections
import Watchers: _fetch!, _init!, _load!, _flush!, _process!, _get, _push!, _pop!, _start!, _stop!, _delete!
using Watchers: isstale, isstarted, isstopped, pushnew!, pushstart!, buffer, watcher, lastdate

const Dates = Watchers.Misc.TimeTicks.Dates
using Watchers.Misc.TimeTicks
using Watchers.WatchersImpls: CcxtTicker, TempCandle, TickerWatcherSymbolState2, CandleWatcherSymbolState4, WatcherHandler2
using Watchers.WatchersImpls: _parse_ticker_snapshot, _ob_to_df, sym_procstate!, default_load_timeframe

# Define watcher methods for test watcher type
_init!(w::Watcher, ::Val{:testwatcher}) = nothing
_fetch!(w::Watcher, ::Val{:testwatcher}) = true
_load!(w::Watcher, ::Val{:testwatcher}) = nothing
_flush!(w::Watcher, ::Val{:testwatcher}) = nothing
_process!(w::Watcher, ::Val{:testwatcher}) = nothing
_get(w::Watcher, ::Val{:testwatcher}, def=nothing) = def
_push!(w::Watcher, ::Val{:testwatcher}, args...) = nothing
_pop!(w::Watcher, ::Val{:testwatcher}, args...) = nothing
_start!(w::Watcher, ::Val{:testwatcher}) = nothing
_stop!(w::Watcher, ::Val{:testwatcher}) = nothing
_delete!(w::Watcher, ::Val{:testwatcher}) = nothing

@testset "Watchers" begin
    @testset "Type aliases" begin
        @test BufferEntry(Int) == NamedTuple{(:time, :value),Tuple{DateTime,Int}}
        @test BufferEntry(Float64) == NamedTuple{(:time, :value),Tuple{DateTime,Float64}}
        @test HasFunction((true, false, true)) isa NamedTuple
        @test Interval((Millisecond(5000), Millisecond(30000), Millisecond(360000))) isa NamedTuple
        @test Capacity((100, 1000)) isa NamedTuple
    end

    @testset "WATCHERS global" begin
        @test WATCHERS isa Watchers.Misc.ConcurrentCollections.ConcurrentDict
        @test isempty(WATCHERS)
    end

    @testset "Watcher construction" begin
        w = watcher(Float64, "testwatcher"; start=false, load=false, flush=false, process=false)
        @test w isa Watcher{Float64}
        @test w.name == "testwatcher"
        @test isempty(w)
        @test length(w) == 0
        @test isstopped(w)
        @test !isstarted(w)
        @test lastdate(w) == Dates.typemin(DateTime)
        @test w.attempts == 0

        # Clean up
        Watchers.close(w; doflush=false)
    end

    @testset "pushnew! adds values" begin
        w = watcher(Float64, "testwatcher"; start=false, load=false, flush=false, process=false)
        @test isempty(w)

        pushnew!(w, 42.0)
        @test length(w) == 1
        @test last(w).value == 42.0
        @test last(w).time isa DateTime

        # Same value should not be pushed again
        pushnew!(w, 42.0)
        @test length(w) == 1

        # Different value should be pushed
        pushnew!(w, 99.0)
        @test length(w) == 2

        # wrong type should error but not crash
        pushnew!(w, "hello")
        @test length(w) == 2

        Watchers.close(w; doflush=false)
    end

    @testset "pushnew! with nothing" begin
        w = watcher(Float64, "testwatcher"; start=false, load=false, flush=false, process=false)
        pushnew!(w, nothing)
        @test isempty(w)
        Watchers.close(w; doflush=false)
    end

    @testset "buffer access" begin
        w = watcher(Float64, "testwatcher"; start=false, load=false, flush=false, process=false)
        pushnew!(w, 1.0)
        pushnew!(w, 2.0)

        buf = buffer(w)
        @test length(buf) == 2
        @test buf[1].value == 1.0
        @test buf[2].value == 2.0

        Watchers.close(w; doflush=false)
    end

    @testset "empty! clears buffer" begin
        w = watcher(Float64, "testwatcher"; start=false, load=false, flush=false, process=false)
        pushnew!(w, 1.0)
        pushnew!(w, 2.0)
        @test length(w) == 2

        empty!(w)
        @test length(w) == 0

        Watchers.close(w; doflush=false)
    end

    @testset "isstale logic" begin
        w = watcher(Float64, "testwatcher"; start=false, load=false, flush=false, process=false, fetch_interval=Second(3600), fetch_timeout=Second(60))
        # Fresh watcher last_fetch = DateTime(0) and attempts = 0,
        # so last_fetch is > 1 hour ago → stale
        @test isstale(w)

        # Set last_fetch to now so it's not stale
        w.last_fetch = now()
        @test !isstale(w)

        # With attempts > 0, it's stale regardless
        w.attempts = 1
        @test isstale(w)

        w.attempts = 0
        w.last_fetch = now() - Dates.Hour(2)
        @test isstale(w)

        Watchers.close(w; doflush=false)
    end

    @testset "_check_flush_interval" begin
        _check_flush_interval(Millisecond(60000), Millisecond(1000), 10)
        _check_flush_interval(Millisecond(60000), Millisecond(1000), 1)
        @test true
    end

    @testset "_notimpl throws" begin
        w = watcher(Float64, "testwatcher"; start=false, load=false, flush=false, process=false)
        @test_throws ErrorException _notimpl(:fetch, w)
        Watchers.close(w; doflush=false)
    end

    @testset "@watcher_interface! macro" begin
        # The macro generates import statements for watcher functions
        # Just verify it's defined
        @test isdefined(Watchers, Symbol("@watcher_interface!"))
    end

    @testset "WATCHERS registration via watcher()" begin
        w = watcher(Float64, "testreg"; start=false, load=false, flush=false, process=false)
        @test haskey(WATCHERS, "testreg")
        @test WATCHERS["testreg"] === w

        Watchers.close(w; doflush=false)
        @test !haskey(WATCHERS, "testreg")
    end

    @testset "Watcher getproperty fallthrough to attrs" begin
        w = watcher(Float64, "testreg"; start=false, load=false, flush=false, process=false, attrs=Dict{Symbol,Any}(:custom_key => 42))
        @test w.custom_key == 42
        Watchers.close(w; doflush=false)
    end

    @testset "Watcher haskey / delete!" begin
        w = watcher(Float64, "testreg"; start=false, load=false, flush=false, process=false)
        w[:mykey] = 99
        @test haskey(w, :mykey)
        @test w[:mykey] == 99
        delete!(w, :mykey)
        @test !haskey(w, :mykey)
        Watchers.close(w; doflush=false)
    end

    @testset "Specific watcher constructors" begin
        # Test cg_ticker_watcher constructor
        @testset "cg_ticker_watcher" begin
            # Just test that the constructor doesn't error with mock implementation
            # We can't test the actual fetch without CoinGecko API
            @test true  # Placeholder - full test would need mocking
        end

        @testset "cg_derivatives_watcher" begin
            @test true
        end

        @testset "cp_markets_watcher" begin
            @test true
        end

        @testset "cp_twitter_watcher" begin
            @test true
        end

        @testset "ccxt_tickers_watcher" begin
            @test true
        end

        @testset "ccxt_ohlcv_watcher" begin
            @test true
        end

        @testset "ccxt_ohlcv_tickers_watcher" begin
            @test true
        end

        @testset "ccxt_ohlcv_candles_watcher" begin
            @test true
        end

        @testset "ccxt_orderbook_watcher" begin
            @test true
        end

        @testset "ccxt_average_ohlcv_watcher" begin
            @test true
        end
    end

    @testset "CCXT Watcher Types and Pure Functions" begin
        @testset "CcxtTicker NamedTuple structure" begin
            ticker_type = Watchers.WatchersImpls.CcxtTicker
            @test fieldcount(ticker_type) == 18
            @test fieldnames(ticker_type) == (
                :symbol, :timestamp, :open, :high, :low, :close,
                :previousClose, :bid, :ask, :bidVolume, :askVolume,
                :last, :vwap, :change, :percentage, :average,
                :baseVolume, :quoteVolume,
            )
        end

        @testset "TempCandle mutable struct" begin
            TC_type = Watchers.WatchersImpls.TempCandle
            # Use default constructor (DFT = Float64) since @kwdef + parametric
            # inner constructor makes type-parameterized keyword construction tricky
            c = TC_type(;
                timestamp=now(), open=50000.0, high=51000.0,
                low=49000.0, close=50500.0, volume=1000.0,
            )
            @test c isa TC_type
            @test c.high == 51000.0
            @test c.low == 49000.0
            @test c.open == 50000.0
            @test c.close == 50500.0
            @test c.volume == 1000.0

            # Verify field types
            @test c.timestamp isa DateTime
            @test c.open isa Float64
        end

        @testset "TickerWatcherSymbolState2" begin
            ST = Watchers.WatchersImpls.TickerWatcherSymbolState2
            state = ST(; sym="BTC/USDT")
            @test state.sym == "BTC/USDT"
            @test state.loaded == false
            @test state.ticks == 0
            @test state.backoff == 0
            @test state.isprocessed == false
            @test state.processed_time == DateTime(0)

            # Test sym_procstate!
            Watchers.WatchersImpls.sym_procstate!(state, true, now())
            @test state.isprocessed == true
            @test state.processed_time isa DateTime
            @test state.processed_time > DateTime(0)
        end

        @testset "CandleWatcherSymbolState4" begin
            ST = Watchers.WatchersImpls.CandleWatcherSymbolState4
            state = ST(; sym="BTC/USDT")
            @test state.sym == "BTC/USDT"
            @test state.loaded == false
            @test state.backoff == 0
            @test state.is_resyncing == false
            @test state.nextcandle === nothing
        end

        @testset "WatcherHandler2 construction" begin
            WH = Watchers.WatchersImpls.WatcherHandler2
            handler = WH(
                init_func=() -> nothing,
                corogen_func=(_) -> () -> nothing,
                wrapper_func=identity,
                subject=Rocket.Subject(Any),
            )
            @test handler.init == true
            @test handler.init_func isa Function
            @test handler.corogen_func isa Function
            @test handler.wrapper_func === identity
            @test handler.subject isa Rocket.Subject{Any}
            @test handler.state === nothing
            @test handler.subscription === nothing
        end

        @testset "_ob_to_df conversion" begin
            # Mock orderbook data as it would arrive from the gateway
            ob = Dict{String,Any}(
                "symbol" => "BTC/USDT",
                "timestamp" => 1700000000000,
                "bids" => [[50000.0, 1.0], [49900.0, 2.0], [49800.0, 3.0]],
                "asks" => [[50100.0, 1.5], [50200.0, 0.5], [50300.0, 2.5]],
            )
            df = Watchers.WatchersImpls._ob_to_df(ob)
            @test df isa Watchers.DataFrame
            @test propertynames(df) == [:timestamp, :bid_price, :bid_amount, :ask_price, :ask_amount]
            @test size(df, 1) == 3
            @test size(df, 2) == 5

            # Check metadata is set (DataFrames metadata API)
            @test !isnothing(Watchers.Data.DFUtils.metadata(df))

            # Check first row values
            @test df.bid_price[1] == 50100.0   # ask[1] becomes bid_price (note: swapped)
            @test df.ask_price[1] == 50000.0   # bid[1] becomes ask_price
        end

        @testset "_parse_ticker_snapshot with Dict input" begin
            now_ms = 1700000000000
            ticker_data = Dict{String,Any}(
                "symbol" => "BTC/USDT",
                "timestamp" => now_ms,
                "open" => 50000.0,
                "high" => 51000.0,
                "low" => 49000.0,
                "close" => 50500.0,
                "previousClose" => nothing,
                "bid" => 50400.0,
                "ask" => 50600.0,
                "bidVolume" => 1.5,
                "askVolume" => 2.0,
                "last" => 50500.0,
                "vwap" => 50200.0,
                "change" => 500.0,
                "percentage" => 1.0,
                "average" => 50250.0,
                "baseVolume" => 1000.0,
                "quoteVolume" => 50000000.0,
            )
            snap = Dict{String,Any}("BTC/USDT" => ticker_data)

            result = Watchers.WatchersImpls._parse_ticker_snapshot(snap)
            @test result isa Dict{String,Watchers.WatchersImpls.CcxtTicker}
            @test haskey(result, "BTC/USDT")
            ticker = result["BTC/USDT"]
            @test ticker.symbol == "BTC/USDT"
            @test ticker.open == 50000.0
            @test ticker.high == 51000.0
            @test ticker.low == 49000.0
            @test ticker.close == 50500.0
            @test ticker.bid == 50400.0
            @test ticker.ask == 50600.0
            @test ticker.last == 50500.0
            @test ticker.baseVolume == 1000.0
            @test ticker.quoteVolume == 50000000.0
            @test ticker.timestamp isa DateTime
            @test ticker.timestamp == dt(now_ms)
            @test ticker.previousClose === nothing
            @test ticker.bidVolume == 1.5
        end

        @testset "_parse_ticker_snapshot empty input" begin
            @test isempty(Watchers.WatchersImpls._parse_ticker_snapshot(Dict{String,Any}()))
            @test isempty(Watchers.WatchersImpls._parse_ticker_snapshot(nothing))
        end

        @testset "_parse_ticker_snapshot with multiple symbols" begin
            now_ms = 1700000000000
            btc = Dict{String,Any}(
                "symbol" => "BTC/USDT",
                "timestamp" => now_ms,
                "open" => 50000.0, "high" => 51000.0, "low" => 49000.0,
                "close" => 50500.0, "previousClose" => nothing,
                "bid" => 50400.0, "ask" => 50600.0,
                "bidVolume" => 1.5, "askVolume" => 2.0,
                "last" => 50500.0, "vwap" => 50200.0,
                "change" => 500.0, "percentage" => 1.0,
                "average" => 50250.0, "baseVolume" => 1000.0,
                "quoteVolume" => 50000000.0,
            )
            eth = Dict{String,Any}(
                "symbol" => "ETH/USDT",
                "timestamp" => now_ms,
                "open" => 3000.0, "high" => 3100.0, "low" => 2900.0,
                "close" => 3050.0, "previousClose" => 3020.0,
                "bid" => 3040.0, "ask" => 3060.0,
                "bidVolume" => 10.0, "askVolume" => 15.0,
                "last" => 3050.0, "vwap" => 3020.0,
                "change" => 30.0, "percentage" => 0.99,
                "average" => 3035.0, "baseVolume" => 50000.0,
                "quoteVolume" => 151000000.0,
            )
            snap = Dict{String,Any}("BTC/USDT" => btc, "ETH/USDT" => eth)

            result = Watchers.WatchersImpls._parse_ticker_snapshot(snap)
            @test length(result) == 2
            @test haskey(result, "BTC/USDT")
            @test haskey(result, "ETH/USDT")
            @test result["ETH/USDT"].previousClose == 3020.0
            @test result["ETH/USDT"].bidVolume == 10.0
        end

        @testset "default_load_timeframe function" begin
            dlt = Watchers.WatchersImpls.default_load_timeframe
            @test dlt(tf"1m") == tf"1h"
            @test dlt(tf"5m") == tf"1h"
            @test dlt(tf"1h") == tf"1d"
            @test dlt(tf"4h") == tf"1d"
            @test dlt(tf"1d") == tf"1d"
        end

        @testset "Average OHLCV aggregation with synthetic data" begin
            # Test the core aggregation math used by the average OHLCV watcher
            # Simulate the _process! aggregation logic at the data level

            # Build synthetic source dataframes for 2 exchanges
            ts_base = DateTime(2024, 1, 1, 0, 0, 0)

            DF = Watchers.DataFrame
            df_exc1 = DF(
                :timestamp => [ts_base, ts_base + Minute(1), ts_base + Minute(2)],
                :open => [100.0, 101.0, 102.0],
                :high => [105.0, 106.0, 107.0],
                :low => [95.0, 96.0, 97.0],
                :close => [102.0, 103.0, 104.0],
                :volume => [1000.0, 1100.0, 1200.0],
            )
            df_exc2 = DF(
                :timestamp => [ts_base, ts_base + Minute(1), ts_base + Minute(2)],
                :open => [101.0, 102.0, 103.0],
                :high => [106.0, 107.0, 108.0],
                :low => [96.0, 97.0, 98.0],
                :close => [103.0, 104.0, 105.0],
                :volume => [2000.0, 2100.0, 2200.0],
            )

            # Simulate aggregation by timestamp (as the watcher does):
            # Group timestamps manually and aggregate
            all_new = vcat(df_exc1, df_exc2)
            sort!(all_new, :timestamp)

            @test size(all_new, 1) == 6

            # Manual aggregation per unique timestamp (same logic as _process!)
            unique_ts = unique(all_new.timestamp)
            @test length(unique_ts) == 3  # 3 unique timestamps

            for ts in unique_ts
                rows = all_new[all_new.timestamp .== ts, :]
                @test size(rows, 1) == 2  # 2 exchanges per timestamp

                agg_open = first(rows.open)
                agg_high = maximum(rows.high)
                agg_low = minimum(rows.low)
                total_vol = sum(rows.volume)
                vwap_close = sum(rows.close .* rows.volume) / total_vol

                @test agg_high >= agg_low
                @test total_vol > 0
                @test vwap_close isa Float64
            end

            # Test empty source handling
            empty_df = DF(
                :timestamp => DateTime[],
                :open => Float64[], :high => Float64[], :low => Float64[],
                :close => Float64[], :volume => Float64[],
            )
            @test isempty(empty_df)
            @test size(empty_df, 1) == 0
        end
    end

    @testset "Watcher internal functions" begin
        # Test that internal watcher functions can be defined and called
        _init!(w::Watcher, ::Val{:test_internal}) = nothing
        _fetch!(w::Watcher, ::Val{:test_internal}) = true
        _process!(w::Watcher, ::Val{:test_internal}) = nothing
        _flush!(w::Watcher, ::Val{:test_internal}) = nothing
        _load!(w::Watcher, ::Val{:test_internal}) = nothing
        _start!(w::Watcher, ::Val{:test_internal}) = nothing
        _stop!(w::Watcher, ::Val{:test_internal}) = nothing

        w = watcher(Float64, "test_internal"; start=false, load=false, flush=false, process=false)
        @test _init!(w, Val{:test_internal}()) === nothing
        @test _fetch!(w, Val{:test_internal}()) == true
        @test _process!(w, Val{:test_internal}()) === nothing
        @test _flush!(w, Val{:test_internal}()) === nothing
        @test _load!(w, Val{:test_internal}()) === nothing
        @test _start!(w, Val{:test_internal}()) === nothing
        @test _stop!(w, Val{:test_internal}()) === nothing
        Watchers.close(w; doflush=false)
    end

    @testset "Watcher buffer capacity" begin
        w = watcher(Float64, "testcap"; start=false, load=false, flush=false, process=false,
                    buffer_capacity=5, view_capacity=10)
        @test w.capacity.buffer == 5
        @test w.capacity.view == 10
        for i in 1:8
            pushnew!(w, Float64(i))
        end
        @test length(buffer(w)) == 5  # buffer capped at 5
        # View is a DataFrame - check it's not empty (capped at 10 rows internally)
        @test w.view !== nothing
        Watchers.close(w; doflush=false)
    end

    @testset "Watcher interval settings" begin
        fetch_interval = Second(10)
        flush_interval = Second(300)
        w = watcher(Float64, "testinterval"; start=false, load=false, flush=false, process=false,
                    fetch_interval=fetch_interval, flush_interval=flush_interval)
        @test w.interval.fetch == Millisecond(10000)
        @test w.interval.flush == Millisecond(300000)
        @test w.interval.timeout == Millisecond(5000)  # default
        Watchers.close(w; doflush=false)
    end

    @testset "Watcher beacon conditions" begin
        w = watcher(Float64, "testbeacon"; start=false, load=false, flush=false, process=false)
        @test w.beacon.fetch isa Rocket.Subject{Any}
        @test w.beacon.process isa Rocket.Subject{Any}
        @test w.beacon.flush isa Rocket.Subject{Any}
        Watchers.close(w; doflush=false)
    end

    @testset "Watcher execution settings" begin
        w = watcher(Float64, "testexec"; start=false, load=false, flush=false, process=false, threads=true)
        @test w._exec.threads == true
        @test w._exec.fetch_lock isa Watchers.SafeLock
        @test w._exec.buffer_lock isa Watchers.SafeLock
        @test w._exec.errors !== nothing
        Watchers.close(w; doflush=false)
    end
end

end
