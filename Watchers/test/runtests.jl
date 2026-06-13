module WatchersTests

using Test
using Watchers
using Watchers: HasFunction, Interval, Capacity, Beacon, BufferEntry, Exec
using Watchers: _check_flush_interval, _notimpl, WATCHERS, logerror, lasterror, errors
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
end

end
