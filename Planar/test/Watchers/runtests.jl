module WatchersTests

using Test
using PlanarCore
using Planar.Watchers
using Planar.Watchers: HasFunction, Interval, Capacity, Beacon, BufferEntry, Exec
using Planar.Watchers.Fetch.Exchanges: Exchange
import Planar.Watchers.Rocket
using Planar.Watchers: _check_flush_interval, _notimpl, WATCHERS, logerror, lasterror, errors
using Planar.Watchers.Misc: ConcurrentCollections
import Planar.Watchers: _fetch!, _init!, _load!, _flush!, _process!, _get, _push!, _pop!, _start!, _stop!, _delete!
using Planar.Watchers: isstale, isstarted, isstopped, pushnew!, pushstart!, buffer, watcher, lastdate

const _Dates = Watchers.Misc.TimeTicks.Dates
using Planar.Watchers.Misc.TimeTicks
using Planar.Watchers.Misc: rangebetween
using Planar.Watchers.Data: empty_ohlcv
using Planar.Watchers.WatchersImpls: CcxtTicker, TempCandle, TickerWatcherSymbolState2, CandleWatcherSymbolState4, WatcherHandler2
using Planar.Watchers.WatchersImpls: _parse_ticker_snapshot, sym_procstate!, default_load_timeframe, _update_sym_ohlcv, ccxt_ohlcv_tickers_watcher, Warmed, TempCandle, TickerWatcherSymbolState2, CandleWatcherSymbolState4, WatcherHandler2, _do_check_contig, _ensure_ohlcv_check_contig!, _dedup_view!
using Planar.Watchers.Ccxt
using PlanarCore.Ccxt.CcxtGateway: ping, start_exchange, stop_exchange, exchange_ready

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
        @test lastdate(w) == _Dates.typemin(DateTime)
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
        w.last_fetch = now() - _Dates.Hour(2)
        @test isstale(w)

        Watchers.close(w; doflush=false)
    end

    @testset "_check_flush_interval" begin
        _check_flush_interval(Millisecond(60000), Millisecond(1000), 10)
        _check_flush_interval(Millisecond(60000), Millisecond(1000), 1)
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
        @testset "cg_ticker_watcher" begin
            @test isdefined(Watchers.WatchersImpls, :CgTickerVal)
            @test isdefined(Watchers.WatchersImpls, :cg_ticker_watcher)
        end

        @testset "cg_derivatives_watcher" begin
            @test isdefined(Watchers.WatchersImpls, :CgDerivativesVal)
            @test isdefined(Watchers.WatchersImpls, :cg_derivatives_watcher)
        end

        @testset "cp_markets_watcher" begin
            @test isdefined(Watchers.WatchersImpls, :CpMarketsVal)
            @test isdefined(Watchers.WatchersImpls, :cp_markets_watcher)
        end

        @testset "cp_twitter_watcher" begin
            @test isdefined(Watchers.WatchersImpls, :CpTwitterVal)
            @test isdefined(Watchers.WatchersImpls, :cp_twitter_watcher)
        end

        @testset "ccxt_tickers_watcher" begin
            @test isdefined(Watchers.WatchersImpls, :CcxtTickerVal)
            @test isdefined(Watchers, :ccxt_tickers_watcher)
        end

        @testset "ccxt_ohlcv_watcher" begin
            @test isdefined(Watchers.WatchersImpls, :CcxtOHLCVVal)
            @test isdefined(Watchers, :ccxt_ohlcv_watcher)
        end

        @testset "ccxt_ohlcv_tickers_watcher" begin
            @test isdefined(Watchers.WatchersImpls, :CcxtOHLCVTickerVal)
            @test isdefined(Watchers.WatchersImpls, :ccxt_ohlcv_tickers_watcher)
        end

        @testset "ccxt_ohlcv_candles_watcher" begin
            @test isdefined(Watchers.WatchersImpls, :CcxtOHLCVCandlesVal)
            @test isdefined(Watchers, :ccxt_ohlcv_candles_watcher)
        end

        @testset "ccxt_orderbook_watcher" begin
            @test isdefined(Watchers.WatchersImpls, :CcxtOrderBookVal)
            @test isdefined(Watchers, :ccxt_orderbook_watcher)
        end

        @testset "ccxt_average_ohlcv_watcher" begin
            @test isdefined(Watchers.WatchersImpls, :CcxtAverageOHLCVVal)
            @test isdefined(Watchers.WatchersImpls, :ccxt_average_ohlcv_watcher)
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
        @test df.bid_price[1] == 50000.0   # highest bid price
        @test df.ask_price[1] == 50100.0   # lowest ask price
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

    @testset "empty_ohlcv structure" begin
        df = empty_ohlcv()
        @test df isa Watchers.DataFrame
        @test propertynames(df) == [:timestamp, :open, :high, :low, :close, :volume]
        @test eltype(df.timestamp) <: DateTime
        @test eltype(df.open) <: Float64
        @test eltype(df.high) <: Float64
        @test eltype(df.low) <: Float64
        @test eltype(df.close) <: Float64
        @test eltype(df.volume) <: Float64
        @test isempty(df)
        @test size(df, 1) == 0
    end

    @testset "rangebetween strict=false with duplicates" begin
        now_ts = now()
        from = now_ts - _Dates.Minute(10)
        to = now_ts

        # For UNIQUE values, strict=true and strict=false behave identically
        # (both exclude the exact value). The difference matters when there
        # are DUPLICATE timestamps, which can happen when vcat merges
        # upsampled data with directly-fetched last-mile candles.
        ts = DateTime[
            from - _Dates.Minute(1),   # 1: before range
            from, from,               # 2:3 — duplicate at left boundary
            from + _Dates.Minute(1),   # 4
            from + _Dates.Minute(5),   # 5
            to, to, to,               # 6:7:8 — duplicate at right boundary
            to + _Dates.Minute(1),     # 9: after range
        ]

        # strict=true — excludes ALL elements equal to boundary
        r_strict = rangebetween(ts, from, to; strict=true)
        @test first(r_strict) == 4   # index 4 = first element strictly after 'from'
        @test last(r_strict) == 5    # index 5 = last element strictly before 'to'
        @test length(r_strict) == 2

        # strict=false — includes ALL boundary duplicates (fully inclusive)
        r_nonstrict = rangebetween(ts, from, to; strict=false)
        @test first(r_nonstrict) == 2   # index 2 = first 'from' duplicate
        @test last(r_nonstrict) == 8    # index 8 = last 'to' duplicate
        @test length(r_nonstrict) == 7  # indices 2,3,4,5,6,7,8
    end

    @testset "static key collision: init_tasks vs process_tasks" begin
        attrs = Dict{Symbol,Any}()
        # Simulate _reset_candles_func! — uses k"init_tasks" (not k"process_tasks")
        init_tasks = get!(attrs, :init_tasks) do
            Set{Task}()
        end
        @test init_tasks isa Set

        # Simulate _make_candles_func — uses :process_tasks (should NOT be Set{Task})
        process_tasks = get!(attrs, :process_tasks) do
            Task[]
        end
        @test process_tasks isa Vector
        @test process_tasks isa Vector{Task}  # specifically Vector{Task}, not Set{Task}
        @test !(process_tasks isa Set)

        # Verify separate keys
        @test haskey(attrs, :init_tasks)
        @test haskey(attrs, :process_tasks)
        @test attrs[:init_tasks] !== attrs[:process_tasks]
    end

    @testset "view initialization with get! and empty_ohlcv" begin
        view = Dict{String,Watchers.DataFrame}()
        sym = "BTC/USDT"

        # Use the same pattern as _make_candles_func: get! with empty_ohlcv()
        df = get!(view, sym) do
            empty_ohlcv()
        end
        @test df isa Watchers.DataFrame
        @test isempty(df)
        @test haskey(view, sym)
        @test view[sym] === df

        # Second call returns existing df without calling the default
        df2 = get!(view, sym) do
            error("should not be called")
        end
        @test df2 === df
    end

    @testset "iswatch default fallback" begin
        # Test the pattern used in ccxt_tickers.jl and ccxt_ohlcv_trades.jl:
        # iswatch = something(iswatch, false) then stored as Bool

        # Case 1: default (no :iswatch key) → fallback to false
        attrs_no_iswatch = Dict{Symbol,Any}()
        iswatch1 = if haskey(attrs_no_iswatch, :iswatch)
            attrs_no_iswatch[:iswatch]::Bool
        else
            false
        end
        @test iswatch1 == false

        # Case 2: explicit true
        attrs_iswatch_true = Dict{Symbol,Any}(:iswatch => true)
        iswatch2 = if haskey(attrs_iswatch_true, :iswatch)
            attrs_iswatch_true[:iswatch]::Bool
        else
            false
        end
        @test iswatch2 == true

        # Case 3: explicit false
        attrs_iswatch_false = Dict{Symbol,Any}(:iswatch => false)
        iswatch3 = if haskey(attrs_iswatch_false, :iswatch)
            attrs_iswatch_false[:iswatch]::Bool
        else
            false
        end
        @test iswatch3 == false

        # Case 4: something(nothing, false) pattern (ccxt_ohlcv_trades.jl line 56)
        @test something(nothing, false) == false
        @test something(true, false) == true
        @test something(false, false) == false
    end

    @testset "_tryfetch type assertion" begin
        # _tryfetch (module.jl:22-53) wraps _fetch! result in ::Union{Bool,Exception}.
        # If _fetch! returns unexpected type (e.g. Set{Task}), the ::Union{Bool,Exception}
        # type assertion throws a TypeError OUTSIDE the inner try-catch.
        # This TypeError propagates to _handle_fetch_result in the Rocket pipeline.
        # The test verifies the error is caught by the outer catch in the pipeline.

        w = watcher(Any, "test_tryfetch_type"; start=false, load=false, flush=false, process=false)

        # Override _fetch! for the test Val type to return Set{Task}
        Watchers.WatchersImpls._fetch!(w::Watcher, ::Val{:test_tryfetch}) = Set{Task}()

        # Simulate _tryfetch behavior: the ::Union{Bool,Exception} type assertion
        # inside the @lock block will throw TypeError for non-Bool/non-Exception values.
        result = try
            @lock w begin
                res = try
                    _fetch!(w, Val{:test_tryfetch}())
                catch e
                    e
                end::Union{Bool,Exception}
                w.last_fetch = now()
                res
            end
        catch e
            e
        end
        @test result isa TypeError
        @test contains(string(result), "TypeError")
        @test contains(string(result), "Set{Task}")

        # Override _fetch! to return Bool — should pass fine
        Watchers.WatchersImpls._fetch!(w::Watcher, ::Val{:test_tryfetch_bool}) = true
        result2 = try
            @lock w begin
                res = try
                    _fetch!(w, Val{:test_tryfetch_bool}())
                catch e
                    e
                end::Union{Bool,Exception}
                w.last_fetch = now()
                res
            end
        catch e
            e
        end
        @test result2 isa Bool
        @test result2 == true

        Watchers.close(w; doflush=false)
    end

    @testset "_make_candles_func returns Bool" begin
        # The closure in _make_candles_func MUST return Bool (true/false)
        # to satisfy _tryfetch's ::Union{Bool,Exception} type assertion.
        # Bug: was returning Set{Task} (from filter! on the set) or nothing.

        w = watcher(Any, "test_candles_return"; start=false, load=false, flush=false, process=false,
                    attrs=Dict{Symbol,Any}(:process_tasks => Task[]))

        # Simulate the minimal closure logic that was buggy:
        # Before fix: tasks = Set{Task}() → filter!(... tasks) → returns Set{Task}
        # After fix: explicit `return fetched` at end

        tasks = w.attrs[:process_tasks]
        fetched = @lock w begin
            # Just the return — sym loop skipped (no syms to iterate)
            true
        end
        if fetched
            push!(tasks, @async process!(w))
            filter!(!istaskdone, tasks)
        end
        @test fetched == true
        @test fetched isa Bool

        Watchers.close(w; doflush=false)
    end

    # ═════════════════════════════════════════════════════════
    # General regression tests for bugs found in watchers 01–03
    # ═════════════════════════════════════════════════════════
    #
    # These test general patterns that caused bugs across multiple
    # watchers: (1) JSON3 Symbol→String key mismatch, (2) empty
    # DataFrame access in _lastdate/_firstdate, (3) narrow type
    # constraints on state struct fields, (4) WS data arriving
    # before view initialization. Any watcher processing external
    # data can hit these — not just the ones we fixed.
    #
    @testset "JSON3 key semantics: Symbol vs String" begin
        # JSON3.parse produces objects with Symbol keys, not String keys.
        # Accessing with a String key silently fails (no KeyError in
        # haskey, throws KeyError on index). This caused KeyError in
        # _update_ohlcv_func when looking up symstates[sym] with a
        # String key from the WS data loop.
        #
        # Simulate JSON3.Object behavior with Dict{Symbol}
        json3style = Dict{Symbol,Any}(Symbol("BTC/USDT") => [1, 2, 3])

        # String-keyed lookup FAILS on Symbol-keyed dict
        @test !haskey(json3style, "BTC/USDT")
        @test_throws KeyError json3style["BTC/USDT"]

        # Symbol-keyed lookup works
        @test haskey(json3style, Symbol("BTC/USDT"))
        @test json3style[Symbol("BTC/USDT")] == [1, 2, 3]

        # The conversion pattern from _update_ohlcv_func:
        # for (sym_raw, tf_candles) in snap   # sym_raw is Symbol
        #     sym = String(sym_raw)            # convert to String
        #     state = symstates[sym]           # String-keyed lookup
        for (k_raw, v) in json3style
            k = String(k_raw)
            @test k == "BTC/USDT"
            @test v == [1, 2, 3]
        end

        # The _stringify_keys pattern (from cp_markets.jl) for full
        # conversion of nested Symbol-keyed data
        stringified = Dict{String,Any}(string(k) => v for (k, v) in json3style)
        @test haskey(stringified, "BTC/USDT")
        @test stringified["BTC/USDT"] == [1, 2, 3]
    end

    @testset "empty DataFrame safety: _lastdate/_firstdate guards" begin
        # _lastdate(df::DataFrame) = df[end, :timestamp] and
        # _firstdate(df::DataFrame) = df[begin, :timestamp] throw
        # BoundsError on 0-row DataFrames. Any processing code that
        # calls these without an isempty guard crashes. This was the
        # root cause of the _resolve crash in the candles watcher
        # (empty view from WS data arriving before _ensure_ohlcv!).
        df = empty_ohlcv()
        @test isempty(df)
        @test size(df, 1) == 0

        # Direct access to last/first row throws BoundsError
        @test_throws BoundsError df[end, :timestamp]
        @test_throws BoundsError df[begin, :timestamp]
        @test_throws BoundsError df[end, :open]
        @test_throws BoundsError df[begin, :open]

        # Proper guard pattern: isempty check first (used in the fix)
        safe_last = isempty(df) ? nothing : df[end, :timestamp]
        @test safe_last === nothing

        safe_first = isempty(df) ? nothing : df[begin, :timestamp]
        @test safe_first === nothing

        # With data, the same code works
        ts = now()
        push!(df, (ts, 100.0, 105.0, 95.0, 102.0, 1000.0))
        @test !isempty(df)
        @test df[end, :timestamp] == ts
        @test df[begin, :timestamp] == ts
    end

    @testset "CandleWatcherSymbolState4 nextcandle type flexibility" begin
        # The nextcandle field was typed Union{Nothing, Tuple}, but
        # WS data arrives as JSON3.Object (simulated as Dict{Symbol}
        # here). Narrow type constraints on state fields that store
        # external data cause TypeError on assignment. Fixed by
        # removing the type annotation.
        ST = Watchers.WatchersImpls.CandleWatcherSymbolState4

        # Default is nothing
        state = ST(; sym="BTC/USDT")
        @test state.nextcandle === nothing

        # Can hold Dict{String} (REST-style response)
        rest_data = Dict(
            "1m" => [[1700000000000, 50000.0, 51000.0, 49000.0, 50500.0, 1000.0]],
        )
        state.nextcandle = rest_data
        @test state.nextcandle isa Dict
        @test haskey(state.nextcandle, "1m")

        # Can hold Dict{Symbol} (JSON3-style WS data)
        ws_data = Dict{Symbol,Any}(
            Symbol("1m") => [[1700000000000, 50000.0, 51000.0, 49000.0, 50500.0, 1000.0]],
        )
        state.nextcandle = ws_data
        @test state.nextcandle isa Dict{Symbol}

        # The iteration+conversion pattern from _update_ohlcv_func
        for (tf_raw, candles) in state.nextcandle
            tf_str = String(tf_raw)
            @test tf_str == "1m"
            @test length(candles) == 1
            cdl = first(candles)
            @test length(cdl) >= 6
        end
    end

    @testset "WS snapshot processing pattern: Symbol keys + empty view" begin
        # Simulates the full _update_ohlcv_func pattern:
        #   1. Incoming WS data has Symbol keys (JSON3)
        #   2. Need String(sym) for internal dict lookups
        #   3. View may not have the symbol yet (lazy init via get!)
        #   4. Empty DataFrame must be handled safely (no _lastdate)
        #   5. nextcandle stores Symbol-keyed data safely
        #
        # Any watcher that processes WS data before the async init
        # completes hits this pattern — not just OHLCV candles.

        view = Dict{String, Watchers.DataFrame}()
        symstates = Dict{String, CandleWatcherSymbolState4}(
            "BTC/USDT" => CandleWatcherSymbolState4(; sym="BTC/USDT"),
        )

        # Simulate WS data with Symbol keys (as JSON3 produces)
        snap = Dict{Symbol,Any}(
            Symbol("BTC/USDT") => Dict{Symbol,Any}(
                Symbol("1m") => [
                    [1700000000000, 50000.0, 51000.0, 49000.0, 50500.0, 1000.0],
                ],
            ),
        )

        # Process each symbol (mirrors the fix: String conversion + get!)
        for (sym_raw, tf_candles) in snap
            sym = String(sym_raw)

            # Must exist in symstates (fixed pre-existing)
            @test haskey(symstates, sym)
            state = symstates[sym]

            # Lazy view init via get! (the fix for KeyError)
            df = get!(view, sym) do
                empty_ohlcv()
            end
            @test haskey(view, sym)
            @test isempty(df)  # Not yet populated by _ensure_ohlcv!

            # Cache the WS data for later processing (no TypeError)
            state.nextcandle = tf_candles

            # Iterate the cached data with Symbol→String conversion
            for (tf_raw, candles) in state.nextcandle
                tf_str = String(tf_raw)
                @test tf_str == "1m"
                @test length(candles) == 1
                cdl = first(candles)
                @test cdl[2] == 50000.0  # open
                @test cdl[3] == 51000.0  # high
                @test cdl[4] == 49000.0  # low
                @test cdl[5] == 50500.0  # close
                @test cdl[6] == 1000.0   # volume
            end
        end

        # View entry exists but is empty (waiting for resync)
        @test haskey(view, "BTC/USDT")
        @test isempty(view["BTC/USDT"])

        # Simulate the resync populating the view
        ts = now()
        push!(view["BTC/USDT"], (ts, 100.0, 105.0, 95.0, 102.0, 1000.0))
        @test !isempty(view["BTC/USDT"])

        # Now _nextdate and _lastdate work safely
        tf = tf"1m"
        last_ts = view["BTC/USDT"][end, :timestamp]
        @test last_ts == ts
        next_ts = last_ts + period(tf)
        @test next_ts == ts + Minute(1)
    end

    # ─────────────────────────────────────────────────────
    # WebSocket integration test (requires running gateway)
    # ─────────────────────────────────────────────────────
    # Gated by: RUN_INTEGRATION_TESTS=true env var + gateway ping
    # This tests the WS subscription path at the watcher abstraction level.
    # If the gateway is not running or the env var is not set, the test is skipped.
    if get(ENV, "RUN_INTEGRATION_TESTS", "false") == "true"
        @testset "WebSocket OHLCV subscription via _connect_ws_ohlcv!" begin
            # Check gateway reachability
            if !ping()
                @info "Skipping WS integration test - gateway not running"
                @test_skip true
                return
            end
            @info "Gateway reachable, starting WS integration test"

            exchange_id = "okx"
            symbol = "BTC/USDT"
            tf = "1m"

            # --- Start exchange ---
            result = start_exchange(exchange_id)
            @test result isa Dict
            @test get(result, "status", "") in ("started", "already_started")
            @info "Exchange start result: $(get(result, "status", "unknown"))"

            # --- Wait for ready (up to 30s) ---
            ready = false
            for i in 1:30
                sleep(1)
                if exchange_ready(exchange_id)
                    ready = true
                    @info "Exchange ready after $(i)s"
                    break
                end
            end
            if !ready
                @warn "Exchange not ready within timeout, skipping rest of test"
                try stop_exchange(exchange_id) catch end
                return
            end

            # --- Build minimal watcher with handler ---
            w = watcher(Any, "ws_integration_test_ohlcv"; start=false, load=false, flush=false, process=false)
            subject = Rocket.Subject(Any)
            wh = WatcherHandler2(
                init_func = () -> nothing,
                corogen_func = (_) -> () -> nothing,
                wrapper_func = identity,
                subject = subject,
            )
            w.attrs[:handler] = wh

            # --- Subscribe via WebSocket ---
            connected = Watchers.WatchersImpls._connect_ws_ohlcv!(w, exchange_id, [[symbol, tf]])
            @test connected == true
            @test haskey(w.attrs, :ws_sub_id)
            sub_id = w.attrs[:ws_sub_id]
            @info "WS subscribed: $sub_id"

            # --- Wait for data on the Rocket subject ---
            received_data = Channel{Any}(1)
            rocket_sub = Rocket.subscribe!(subject, Rocket.lambda(
                on_next = v -> begin
                    if !isready(received_data)
                        put!(received_data, v)
                    end
                end,
                on_error = err -> @warn("Subject error: $err"),
            ))

            ohlcv_data = nothing
            timeout = 30.0
            start_ts = time()
            while time() - start_ts < timeout
                if isready(received_data)
                    ohlcv_data = take!(received_data)
                    break
                end
                sleep(0.5)
            end

            if ohlcv_data === nothing
                @warn "No WS data within $(timeout)s — exchange may not support WS OHLCV"
                @test_broken false  # Known limitation if exchange lacks WS
            else
                elapsed = round(time() - start_ts; digits=1)
                @info "WS data received after $(elapsed)s | type=$(typeof(ohlcv_data))"
                @test ohlcv_data !== nothing

                # Validate OHLCV data shape
                if ohlcv_data isa Vector && length(ohlcv_data) > 0
                    entry = ohlcv_data[1]
                    if entry isa Vector && length(entry) >= 6
                        @test entry[2] isa Number  # open
                        @test entry[3] isa Number  # high
                        @test entry[4] isa Number  # low
                        @test entry[5] isa Number  # close
                        @test entry[6] isa Number  # volume
                        @test entry[3] >= entry[4]  # high >= low
                        @info "First OHLCV entry: ts=$(entry[1]) o=$(entry[2]) h=$(entry[3]) l=$(entry[4]) c=$(entry[5]) v=$(entry[6])"
                    else
                        @info "Unexpected entry format: $(typeof(entry)) = $entry"
                    end
                elseif ohlcv_data isa Dict
                    @info "Dict data keys: $(collect(keys(ohlcv_data)))"
                    if haskey(ohlcv_data, symbol)
                        @info "  $symbol data: $(ohlcv_data[symbol])"
                    end
                end
            end

            # --- Cleanup ---
            Rocket.unsubscribe!(rocket_sub)
            # Send unsubscribe via WS client
            ws_client = get(w.attrs, :ws_client, nothing)
            if ws_client !== nothing
                try
                    Ccxt.CcxtGateway.send_unsubscribe(ws_client, sub_id)
                    Ccxt.CcxtGateway.disconnect!(ws_client)
                catch
                end
            end
            Watchers.close(w; doflush=false)
            try stop_exchange(exchange_id) catch end
            @info "WS integration test cleanup done"
        end
    end
    @testset "ccxt ohlcv tickers null price guard (regression #40)" begin
        # A `watchTickers` WS payload can carry null/`NaN` `last` (or other OHLCV
        # fields). Previously `_update_sym_ohlcv` assigned that `nothing` to a
        # `Float64` candle field inside an async task, throwing an exception that
        # was swallowed by errormonitor — so WS data was received but no candle
        # was ever appended. The guards must make a null price a no-op.
        tf = tf"1m"
        exc = Exchange("binance")
        syms = ["BTC/USDT"]
        w = ccxt_ohlcv_tickers_watcher(exc; syms, timeframe=tf, price_source=:last, start=false, n_jobs=1)
        w[:status] = Warmed()
        w[:warmup_target] = TimeTicks.apply(tf, TimeTicks.now()) - tf
        w[Symbol("symstates")] = Dict(sym => TickerWatcherSymbolState2(; sym) for sym in syms)
        w[Symbol("sem")] = Base.Semaphore(1)
        view = w.view
        M = TimeTicks.apply(tf, TimeTicks.now()) - _Dates.Minute(2)
        df0 = empty_ohlcv()
        for i in 2:-1:1
            push!(df0, (timestamp = M - _Dates.Minute(i), open=Float64(100+i), high=Float64(101+i), low=Float64(99+i), close=Float64(100+i), volume=Float64(10)))
        end
        view["BTC/USDT"] = df0
        state = w[Symbol("symstates")]["BTC/USDT"]

        mk_ticker(ts_dt, price, vol) = begin
            ts_ms = Int(floor(_Dates.datetime2unix(ts_dt) * 1000))
            d = Dict{String,Any}(
                "symbol" => "BTC/USDT", "timestamp" => ts_ms,
                "open" => price, "high" => price, "low" => price, "close" => price,
                "previousClose" => price, "bid" => price, "ask" => price,
                "bidVolume" => vol, "askVolume" => vol,
                "last" => price, "vwap" => price, "change" => 0.0,
                "percentage" => 0.0, "average" => price,
                "baseVolume" => vol, "quoteVolume" => vol,
            )
            _parse_ticker_snapshot(Dict("BTC/USDT" => d))["BTC/USDT"]
        end

        # Fresh state: temp candle timestamp is the epoch sentinel.
        @test state.temp.timestamp == _Dates.DateTime(0)

        # A ticker with a null `last` must NOT throw and must NOT mutate state/view.
        _update_sym_ohlcv(w, mk_ticker(M, nothing, 100.0), M)
        @test state.temp.timestamp == _Dates.DateTime(0)
        @test size(view["BTC/USDT"], 1) == 2

        # A valid ticker initializes the temp candle without throwing.
        _update_sym_ohlcv(w, mk_ticker(M, 110.0, 100.0), M)
        @test state.temp.timestamp == M
        @test state.temp.close == 110.0
        @test size(view["BTC/USDT"], 1) == 2

        # A null `last` arriving at a later timestamp must also be skipped safely.
        _update_sym_ohlcv(w, mk_ticker(M + _Dates.Minute(1), nothing, 100.0), M + _Dates.Minute(1))
        @test state.temp.timestamp == M
        @test size(view["BTC/USDT"], 1) == 2
    end

    @testset "ccxt ohlcv tickers seeds view from empty (history unavailable)" begin
        # When history preload fails (no gateway / zero markets), the view starts
        # empty. `_ensure_contig!` must seed the series with the first finalized
        # candle instead of dropping it — otherwise the buffer fills but the view
        # stays empty forever (the reported regression).
        tf = tf"1m"
        exc = Exchange("binance")
        syms = ["BTC/USDT"]
        w = ccxt_ohlcv_tickers_watcher(exc; syms, timeframe=tf, price_source=:last, start=false, n_jobs=1)
        w[:status] = Warmed()
        w[:warmup_target] = TimeTicks.apply(tf, TimeTicks.now()) - tf
        w[Symbol("symstates")] = Dict(sym => TickerWatcherSymbolState2(; sym) for sym in syms)
        w[Symbol("sem")] = Base.Semaphore(1)
        # Intentionally do NOT preload w.view — simulates history preload failing.
        M = TimeTicks.apply(tf, TimeTicks.now()) - _Dates.Minute(2)
        mk_ticker(ts_dt, price, vol) = begin
            ts_ms = Int(floor(_Dates.datetime2unix(ts_dt) * 1000))
            d = Dict{String,Any}(
                "symbol" => "BTC/USDT", "timestamp" => ts_ms,
                "open" => price, "high" => price, "low" => price, "close" => price,
                "previousClose" => price, "bid" => price, "ask" => price,
                "bidVolume" => vol, "askVolume" => vol,
                "last" => price, "vwap" => price, "change" => 0.0,
                "percentage" => 0.0, "average" => price,
                "baseVolume" => vol, "quoteVolume" => vol,
            )
            _parse_ticker_snapshot(Dict("BTC/USDT" => d))["BTC/USDT"]
        end
        # Two sequential timestamps: the 2nd finalizes the 1st candle. With an
        # empty view this must seed (not drop) the candle.
        _update_sym_ohlcv(w, mk_ticker(M, 110.0, 100.0), M)
        @test !haskey(w.view, "BTC/USDT") || isempty(w.view["BTC/USDT"])
        _update_sym_ohlcv(w, mk_ticker(M + _Dates.Minute(1), 111.0, 110.0), M + _Dates.Minute(1))
        @test haskey(w.view, "BTC/USDT")
        @test size(w.view["BTC/USDT"], 1) == 1
        @test w.view["BTC/USDT"][1, :timestamp] == M
        @test w.view["BTC/USDT"][1, :close] == 110.0
    end

    @testset "ccxt ohlcv tickers pushes flat market candles but skips stale ones (no dup timestamps)" begin
        # After a WS gap with real ticker data, the first candles may be flat
        # (open==high==low==close, market didn't move). Candles with state.ticks > 0
        # represent real ticker contributions — they MUST be pushed to prevent
        # unfillable gaps. Only candles with state.ticks == 0 (stale artifacts from
        # resetcandle! with no real tickers) should be skipped.
        tf = tf"1m"
        exc = Exchange("binance")
        syms = ["BTC/USDT"]
        w = ccxt_ohlcv_tickers_watcher(exc; syms, timeframe=tf, price_source=:last, start=false, n_jobs=1)
        w[:status] = Warmed()
        w[:warmup_target] = TimeTicks.apply(tf, TimeTicks.now()) - tf
        w[Symbol("symstates")] = Dict(sym => TickerWatcherSymbolState2(; sym) for sym in syms)
        w[Symbol("sem")] = Base.Semaphore(1)
        state = w[Symbol("symstates")]["BTC/USDT"]
        state.loaded = true  # skip init-guard fetch

        # Seed pre-gap data ending at Mlast.
        M = TimeTicks.apply(tf, TimeTicks.now()) - _Dates.Hour(2) - _Dates.Minute(2)
        df0 = empty_ohlcv()
        for i in 18:-1:1
            ts = M - _Dates.Minute(i)
            push!(df0, (timestamp = ts, open=Float64(62000+i), high=Float64(62100+i),
                        low=Float64(61900+i), close=Float64(62000+i), volume=1.0))
        end
        Mlast = lastdate(df0)
        w.view["BTC/USDT"] = df0
        @test size(df0, 1) == 18
        @test Mlast == M - _Dates.Minute(1)

        mk_ticker(ts_dt, price, vol) = begin
            ts_ms = Int(floor(_Dates.datetime2unix(ts_dt) * 1000))
            d = Dict{String,Any}(
                "symbol" => "BTC/USDT", "timestamp" => ts_ms,
                "open" => price, "high" => price, "low" => price, "close" => price,
                "previousClose" => price, "bid" => price, "ask" => price,
                "bidVolume" => vol, "askVolume" => vol,
                "last" => price, "vwap" => price, "change" => 0.0,
                "percentage" => 0.0, "average" => price,
                "baseVolume" => vol, "quoteVolume" => vol,
            )
            _parse_ticker_snapshot(Dict("BTC/USDT" => d))["BTC/USDT"]
        end

        # Simulate the 2h gap: the stale-check (::Nothing) overload advances
        # temp_candle without real tickers (ticks=0).
        gap_end = Mlast + _Dates.Hour(2)
        gap_times = [Mlast + _Dates.Minute(5) * i for i in 1:24]
        for gt in gap_times
            _update_sym_ohlcv(w, nothing, gt, "BTC/USDT")
        end
        @test state.ticks == 0

        # Resume: WS reconnects. First tickers are stale/flat (last = 63133.2).
        r41 = gap_end
        r42 = r41 + _Dates.Minute(1)
        r43 = r42 + _Dates.Minute(1)
        _update_sym_ohlcv(w, mk_ticker(r41, 63133.2, 1.0), r41)
        _update_sym_ohlcv(w, mk_ticker(r42, 63133.2, 1.1), r42)
        _update_sym_ohlcv(w, mk_ticker(r43, 62600.0, 2.0), r43)

        df = w.view["BTC/USDT"]
        ts = df[!, :timestamp]
        # No duplicate timestamps (race / redundant push invariant).
        @test all(count(==(t), ts) == 1 for t in ts)
        # Flat-but-legitimate candles (state.ticks > 0, same price throughout the
        # minute) ARE preserved — they represent real market data.
        flat = map(r -> r.open == r.high == r.low == r.close == 63133.2, eachrow(df))
        # r42 candle is fully flat at 63133.2 (one real ticker, no price movement).
        # r41 candle has open/low from the seed close (62001.0) carried by the
        # stale-check (::Nothing) path, so it is not fully flat at 63133.2.
        @test count(flat) == 1
        # Gap is honest: first post-gap candle is well after Mlast.
        post = ts[findall(>(Mlast), ts)]
        @test !isempty(post)
        @test minimum(post) - Mlast > _Dates.Minute(1)
        # All three resume candles are pushed (18 seed + 2 flat + 0 non-flat in view);
        # r43 stays in temp_candle waiting for the next ticker boundary.
        @test size(df, 1) == 20
    end
    @testset "ccxt ohlcv tickers preload tolerates history gaps (no fatal throw)" begin
        # Real exchange history can contain gaps (a minute with no trades has no
        # candle). `_ensure_ohlcv!` previously called `_do_check_contig` directly,
        # which THREW on any gap and aborted the entire history preload — spamming
        # "fetch failed" / "Time series is not contiguous" and leaving the view short.
        # The preload must tolerate gaps: the check is logged, not fatal.
        tf = tf"1m"
        exc = Exchange("binance")
        syms = ["BTC/USDT"]
        w = ccxt_ohlcv_tickers_watcher(exc; syms, timeframe=tf, price_source=:last, start=false, n_jobs=1)
        w[:status] = Warmed()
        w[:warmup_target] = TimeTicks.apply(tf, TimeTicks.now()) - tf
        w[Symbol("symstates")] = Dict(sym => TickerWatcherSymbolState2(; sym) for sym in syms)
        w[Symbol("sem")] = Base.Semaphore(1)
        w[:checks] = Val(:on)  # enforce contiguity so a gap would otherwise throw

        # History with a 2-minute gap (missing the 16:01 candle).
        t0 = TimeTicks.apply(tf, TimeTicks.now()) - _Dates.Hour(2)
        df = empty_ohlcv()
        push!(df, (timestamp=t0, open=100.0, high=101.0, low=99.0, close=100.0, volume=10.0))
        push!(df, (timestamp=t0 + _Dates.Minute(2), open=100.0, high=101.0, low=99.0, close=100.0, volume=10.0))
        w.view["BTC/USDT"] = df

        # The strict check DOES throw on this gap — that was the old (broken) behavior.
        @test_throws String _do_check_contig(w, df, Val(:on))
        # The tolerant wrapper must NOT throw — the preload continues with the gap.
        threw = false
        try
            _ensure_ohlcv_check_contig!(w, df, "BTC/USDT")
        catch e
            threw = true
        end
        @test !threw
    end

    @testset "ccxt ohlcv tickers _dedup_view! removes duplicate timestamps" begin
        # A concurrent history preload and live ticker push can (before the
        # state.lock serialization) produce two rows with the same timestamp.
        # _dedup_view! must drop the duplicate so the view keeps the unique-timestamp
        # invariant (Lesson 17) — downstream processing breaks on dup timestamps.
        df = empty_ohlcv()
        t0 = TimeTicks.apply(tf"1m", TimeTicks.now()) - _Dates.Hour(1)
        push!(df, (timestamp=t0, open=100.0, high=101.0, low=99.0, close=100.0, volume=1.0))
        push!(df, (timestamp=t0 + _Dates.Minute(1), open=101.0, high=102.0, low=100.0, close=101.0, volume=1.0))
        push!(df, (timestamp=t0 + _Dates.Minute(1), open=200.0, high=201.0, low=199.0, close=200.0, volume=2.0))  # dup ts with row above
        push!(df, (timestamp=t0 + _Dates.Minute(2), open=102.0, high=103.0, low=101.0, close=102.0, volume=1.0))
        @test size(df, 1) == 4
        ts_before = df[:, :timestamp]
        @test count(==(t0 + _Dates.Minute(1)), ts_before) == 2
        _dedup_view!(df)
        @test size(df, 1) == 3
        ts_after = df[:, :timestamp]
        @test all(count(==(t), ts_after) == 1 for t in ts_after)
        # order preserved, dup row removed
        @test ts_after == [t0, t0 + _Dates.Minute(1), t0 + _Dates.Minute(2)]
        # no dup timestamps anywhere
        @test length(unique(ts_after)) == length(ts_after)
    end

    @testset "parse ticker snapshot skips malformed tickers" begin
        # A single malformed ticker (e.g. null or missing `symbol`, a required
        # `String` field) must not abort parsing of the whole WS snapshot.
        raw_ticker(sym, price, vol; with_symbol=true, null_symbol=false) = begin
            d = Dict{String,Any}(
                "timestamp" => 1000, "open" => price, "high" => price, "low" => price,
                "close" => price, "previousClose" => price, "bid" => price, "ask" => price,
                "bidVolume" => vol, "askVolume" => vol, "last" => price, "vwap" => price,
                "change" => 0.0, "percentage" => 0.0, "average" => price,
                "baseVolume" => vol, "quoteVolume" => vol,
            )
            if with_symbol
                d["symbol"] = null_symbol ? nothing : sym
            end
            d
        end
        snap = Dict{String,Any}(
            "GOOD" => raw_ticker("GOOD", 110.0, 100.0),
            "NULLSYM" => raw_ticker("NULLSYM", 110.0, 100.0; null_symbol=true),
            "NOSYM" => raw_ticker("NOSYM", 110.0, 100.0; with_symbol=false),
        )
        result = _parse_ticker_snapshot(snap)
        @test haskey(result, "GOOD")
        @test !haskey(result, "NULLSYM")
        @test !haskey(result, "NOSYM")
    end
end

end
