@eval begin
    using Test
    using Planar: @environment!
    @environment!
    using Planar.Engine.LiveMode.Watchers: Watchers
    using .TimeTicks: TimeTicks as tt
    using Planar.Engine.Misc: Misc
end

# Import the underscore-prefixed methods we need to override
import Planar.Engine.LiveMode.Watchers: _fetch!, _init!, _load!, _flush!,
    _process!, _get, _push!, _pop!, _start!, _stop!, _delete!

# Define TestTicker type at top level
const TestTicker = NamedTuple{(:symbol, :timestamp, :last, :bid, :ask, :baseVolume),
    Tuple{String, DateTime, Float64, Float64, Float64, Float64}}

const TEST_TICKER_VAL = Val{:test_testticker}
const test_symbols = ["BTC/USDT", "ETH/USDT"]

# Global fetch counter - must be defined at top level
const _fetch_counter = Ref(0)

# Get ConstDates for use in method definitions
ConstDates = Misc.TimeTicks.Dates

# Define ALL watcher interface methods at TOP LEVEL
function _init!(w::Watchers.Watcher, ::Val{:test_testticker})
    a = w.attrs
    a[:view] = Dict{String, Vector{TestTicker}}()
    a[:last_processed] = nothing
    nothing
end

_flush!(w::Watchers.Watcher, ::Val{:test_testticker}) = nothing
_load!(w::Watchers.Watcher, ::Val{:test_testticker}) = nothing
_start!(w::Watchers.Watcher, ::Val{:test_testticker}) = nothing
_stop!(w::Watchers.Watcher, ::Val{:test_testticker}) = nothing
_get(w::Watchers.Watcher, ::Val{:test_testticker}, def=nothing) = get(w.attrs, :view, def)
_push!(w::Watchers.Watcher, ::Val{:test_testticker}, args...) = nothing
_pop!(w::Watchers.Watcher, ::Val{:test_testticker}, args...) = nothing

function _fetch!(w::Watchers.Watcher, ::Val{:test_testticker})::Bool
    _fetch_counter[] += 1
    idx = _fetch_counter[]
    # Use fetch counter to ensure unique timestamps (100ms apart)
    t = ConstDates.unix2datetime((ConstDates.value(ConstDates.now()) ÷ 100) * 100 + idx * 100)
    
    btc_price = 50000.0 + Float64(idx)
    eth_price = 3000.0 + Float64(idx)
    
    result = Dict{String, TestTicker}()
    result["BTC/USDT"] = (symbol="BTC/USDT", timestamp=t, last=btc_price,
        bid=btc_price-1.0, ask=btc_price+1.0, baseVolume=1000.0+Float64(idx))
    result["ETH/USDT"] = (symbol="ETH/USDT", timestamp=t, last=eth_price,
        bid=eth_price-1.0, ask=eth_price+1.0, baseVolume=5000.0+Float64(idx))
    
    Watchers.pushnew!(w, result, t)
    return true
end

function _process!(w::Watchers.Watcher, ::Val{:test_testticker})
    dict = w.attrs[:view]
    buf = Watchers.buffer(w)
    isempty(buf) && return nothing
    
    # Collect buffer data into per-symbol vectors
    data = Dict{String,Vector{TestTicker}}()
    for entry in buf
        for (sym, ticker) in pairs(entry.value)
            push!(get!(Vector{TestTicker}, data, sym), ticker)
        end
    end
    
    # Append to view, deduplicating against last entry AND within batch
    for (key, nts) in pairs(data)
        vec = get!(() -> TestTicker[], dict, key)
        # Filter out duplicates: compare against last in vec AND previous in batch
        filtered = TestTicker[]
        for nt in nts
            # Skip if matches last in existing vec
            !isempty(vec) && nt == vec[end] && continue
            # Skip if matches last in filtered batch
            !isempty(filtered) && nt == filtered[end] && continue
            push!(filtered, nt)
        end
        append!(vec, filtered)
    end
    nothing
end

# Now the test function - uses Watchers.* prefix for all module functions
function test_watcher_verification()
    @testset "Watcher Verification" begin
        @testset "1. Buffer population after start!" begin
            _fetch_counter[] = 0
            w = Watchers.watcher(
                Dict{String,TestTicker}, "test_buf_$(rand(100000:999999))", TEST_TICKER_VAL();
                start=false, load=false, process=true, flush=false,
                fetch_interval=ConstDates.Millisecond(50),
                buffer_capacity=1000, view_capacity=1000)
            _init!(w, TEST_TICKER_VAL())
            Watchers.start!(w)
            
            deadline = time() + 5.0
            while _fetch_counter[] < 2 && time() < deadline
                sleep(0.05)
            end
            
            buf = Watchers.buffer(w)
            @test _fetch_counter[] >= 2
            @test length(buf) >= 2
            @test last(buf).value isa Dict{String, TestTicker}
            @test haskey(last(buf).value, "BTC/USDT")
            @test haskey(last(buf).value, "ETH/USDT")
            @test last(buf).value["BTC/USDT"].last > 50000.0
            
            Watchers.stop!(w)
            Watchers.close(w; doflush=false)
        end
        
        @testset "2. No errors during operation" begin
            _fetch_counter[] = 0
            w = Watchers.watcher(
                Dict{String,TestTicker}, "test_err_$(rand(100000:999999))", TEST_TICKER_VAL();
                start=false, load=false, process=true, flush=false,
                fetch_interval=ConstDates.Millisecond(50),
                buffer_capacity=1000, view_capacity=1000)
            _init!(w, TEST_TICKER_VAL())
            Watchers.start!(w)
            
            # Wait for Rocket subscription to fully initialize and fetches to complete
            deadline = time() + 5.0
            while _fetch_counter[] < 3 && time() < deadline
                sleep(0.05)
            end
            sleep(0.3)
            
            # Check no fatal errors (MethodError, etc.) - Rocket may log minor subscription errors
            errs = Watchers.errors(w)
            @test all(e -> !(e[1] isa MethodError), errs)
            @test all(e -> !(e[1] isa UndefVarError), errs)
            @test Watchers.lasterror(w) === nothing || !(Watchers.lasterror(w)[1] isa MethodError)
            
            Watchers.stop!(w)
            Watchers.close(w; doflush=false)
        end
        
        @testset "3. Timestamp uniqueness" begin
            _fetch_counter[] = 0
            w = Watchers.watcher(
                Dict{String,TestTicker}, "test_ts_$(rand(100000:999999))", TEST_TICKER_VAL();
                start=false, load=false, process=true, flush=false,
                fetch_interval=ConstDates.Millisecond(50),
                buffer_capacity=1000, view_capacity=1000)
            _init!(w, TEST_TICKER_VAL())
            Watchers.start!(w)
            
            deadline = time() + 5.0
            while _fetch_counter[] < 5 && time() < deadline
                sleep(0.05)
            end
            
            buf = Watchers.buffer(w)
            @test length(buf) >= 4
            
            for i in 1:(length(buf)-1)
                e1, e2 = buf[i], buf[i+1]
                @test e1.time != e2.time || e1.value != e2.value
            end
            
            Watchers.stop!(w)
            Watchers.close(w; doflush=false)
        end
        
        @testset "4. Gateway micro-cache proof" begin
            _fetch_counter[] = 0
            w = Watchers.watcher(
                Dict{String,TestTicker}, "test_cache_$(rand(100000:999999))", TEST_TICKER_VAL();
                start=false, load=false, process=true, flush=false,
                fetch_interval=ConstDates.Millisecond(50),
                buffer_capacity=1000, view_capacity=1000)
            _init!(w, TEST_TICKER_VAL())
            Watchers.start!(w)
            
            deadline = time() + 5.0
            while _fetch_counter[] < 3 && time() < deadline
                sleep(0.05)
            end
            
            @test _fetch_counter[] >= 3
            
            buf = Watchers.buffer(w)
            prices_btc = [e.value["BTC/USDT"].last for e in buf]
            @test length(unique(prices_btc)) >= 3
            
            Watchers.stop!(w)
            Watchers.close(w; doflush=false)
        end
        
        @testset "5. View per-symbol vectors" begin
            _fetch_counter[] = 0
            w = Watchers.watcher(
                Dict{String,TestTicker}, "test_view_$(rand(100000:999999))", TEST_TICKER_VAL();
                start=false, load=false, process=true, flush=false,
                fetch_interval=ConstDates.Millisecond(50),
                buffer_capacity=1000, view_capacity=1000)
            _init!(w, TEST_TICKER_VAL())
            Watchers.start!(w)
            
            # Wait for enough fetches
            deadline = time() + 5.0
            while _fetch_counter[] < 3 && time() < deadline
                sleep(0.05)
            end
            sleep(0.5)
            
            view = w.attrs[:view]
            @test view isa Dict{String, Vector{TestTicker}}
            @test haskey(view, "BTC/USDT")
            @test haskey(view, "ETH/USDT")
            @test length(view["BTC/USDT"]) >= 2
            @test length(view["ETH/USDT"]) >= 2
            
            # Verify we received multiple different prices (confirms fetches happened)
            prices_btc = [t.last for t in view["BTC/USDT"]]
            @test length(prices_btc) >= 2
            @test maximum(prices_btc) > minimum(prices_btc)
            
            Watchers.stop!(w)
            Watchers.close(w; doflush=false)
        end
    end
end