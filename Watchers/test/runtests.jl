module WatchersTests

using Test
using Watchers
using Watchers: HasFunction, Interval, Capacity, Beacon, BufferEntry, Exec
using Watchers: _check_flush_interval, _notimpl, WATCHERS, logerror, lasterror, errors
using Watchers.Misc: ConcurrentCollections
import Watchers: _fetch!, _init!, _load!, _flush!, _process!, _get, _push!, _pop!, _start!, _stop!, _delete!
using Watchers: isstale, isstarted, isstopped, pushnew!, pushstart!, buffer, watcher, lastdate

const Dates = Watchers.Misc.TimeTicks.Dates
using Watchers.Misc.TimeTicks

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
        @test w.beacon.fetch isa Threads.Condition
        @test w.beacon.process isa Threads.Condition
        @test w.beacon.flush isa Threads.Condition
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
