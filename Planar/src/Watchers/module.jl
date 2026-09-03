using PlanarCore.Fetch: Fetch
using PlanarCore.Fetch.Data
using PlanarCore.Fetch.Misc
using PlanarCore.Ccxt
using Rocket
using PlanarCore.Data: rangeafter
using PlanarCore.Data.DataStructures: CircularBuffer
using PlanarCore.Data.DataFrames: DataFrame
using PlanarCore.Misc
using PlanarCore.Misc.TimeTicks
using PlanarCore.Misc.Lang: Option, safewait, safenotify, @lget!, Lang
using PlanarCore.Misc: after, truncate_file

@doc """ Attempts to fetch data for a watcher

$(TYPEDSIGNATURES)

This function tries to fetch data for a given watcher. It locks the watcher, updates the last fetch time, and attempts to fetch data. If the fetch is successful, it returns `true`, otherwise it logs the error and returns `false`. It also handles stopping the watcher if needed.
"""
function _tryfetch(w)::Bool
    result = @lock w begin
        res = try
            _fetch!(w, _val(w))
        catch e
            e
        end::Union{Bool,Exception}
        w.last_fetch = now()
        res
    end
    if w._stop
        try
            isstopped(w) || stop!(w)
            flush!(w)
        catch e
            logerror(w, e, catch_backtrace())
        end
        prev_w = pop!(WATCHERS, w.name, missing)
        if !ismissing(prev_w) && isstarted(prev_w)
            stop!(w)
        end
    end
    if result isa Exception
        logerror(w, result, catch_backtrace())
        false
    elseif result isa Bool
        result
    else
        logerror(w, ErrorException("Fetch result is not a bool ($(w.name))"), catch_backtrace())
        false
    end
end

function _handle_fetch_result(w, result)
    try
        if result
            w.attempts = 0
            w.has.process && process!(w)
            w.has.flush && flush!(w; force=false, sync=false)
        else
            w.attempts += 1
        end
    catch err
        logerror(w, err, catch_backtrace())
    end
end

@doc "Sets up the Rocket.jl reactive fetch pipeline using interval observable."
function _setup_fetch_pipeline!(w)
    interval_ms = round(w.interval.fetch, Second, RoundUp).value * 1000
    obs = Rocket.interval(interval_ms)
    pipeline = obs |> Rocket.map(Bool, _ -> _tryfetch(w))
    subscription = Rocket.subscribe!(pipeline, Rocket.lambda(
        on_next = result -> _handle_fetch_result(w, result),
        on_error = err -> logerror(w, err, catch_backtrace()),
    ))
    w[:fetch_subscription] = subscription
end

@doc "Tears down the Rocket.jl fetch pipeline subscription."
function _teardown_fetch_pipeline!(w)
    sub = get(w.attrs, :fetch_subscription, nothing)
    if !isnothing(sub)
        Rocket.unsubscribe!(sub)
        delete!(w.attrs, :fetch_subscription)
    end
end

@doc """ Checks the appropriateness of the flush interval

$(TYPEDSIGNATURES)

This function checks if the flush interval is greater than the time it would take to drop an element from the buffer (calculated as the product of the fetch interval and the buffer capacity). If the flush interval is too high, a warning is issued.
"""
function _check_flush_interval(flush_interval, fetch_interval, cap)
    if cap > 1
        drop_time = cap * fetch_interval
        if flush_interval > drop_time
            @warn "Flush interval ($flush_interval) is too high, buffer element would be dropped in $drop_time."
        end
    end
end

@doc "The single entry in the buffer"
BufferEntry(T) = NamedTuple{(:time, :value),Tuple{DateTime,T}}
@doc "The flags that control which operations are performed by the watcher"
const HasFunction = NamedTuple{(:load, :process, :flush),NTuple{3,Bool}}
@doc "The interval parameters for the watcher"
const Interval = NamedTuple{(:timeout, :fetch, :flush),NTuple{3,Millisecond}}
@doc "The execution variables for the watcher"
const Exec = NamedTuple{
    (:threads, :fetch_lock, :buffer_lock, :errors),
    Tuple{Bool,SafeLock,SafeLock,CircularBuffer{Tuple{Any,Vector}}},
}
@doc "The capacity parameters for the watcher"
const Capacity = NamedTuple{(:buffer, :view),Tuple{Int,Int}}
@doc "The flags that control which operations are notified by the watcher"
const Beacon = NamedTuple{(:fetch, :process, :flush),NTuple{3,Any}}

@doc """ Watchers manage data, they pull from somewhere, keep a cache in memory, and optionally flush periodically to persistent storage.

$(FIELDS)

A `Watcher` is a mutable struct that manages data. It pulls data from a source, keeps a cache in memory, and optionally flushes the data to persistent storage periodically. The struct contains fields for managing the buffer, scheduling fetch operations, and handling fetch failures.
"""
@kwdef mutable struct Watcher{T}
    "A CircularBuffer of the watcher type parameter"
    const buffer::CircularBuffer{BufferEntry(T)}
    "The name is used for dispatching"
    const name::String
    "Flags that show which callbacks are enabled between `load`, `process` and `flush`"
    const has::HasFunction
    "The interval parameters for the watcher"
    const interval::Interval
    "Controls the size of the buffer and the processed container"
    const capacity::Capacity
    "Conditions notified on successful fetch, process and flush events"
    const beacon::Beacon
    "The execution variables for the watcher"
    const _exec::Exec
    "The watcher type parameter"
    const _val::Val
    "Flag to stop the watcher"
    _stop = false
    "A Timer object used to schedule fetch operations for a watcher (deprecated, use fetch_subscription)"
    _timer::Option{Timer} = nothing
    "Tracks how many consecutive fails have occurred in case of fetching failure"
    attempts::Int = 0
    "The most recent time a fetch operation failed"
    last_fetch::DateTime = DateTime(0)
    "The most recent time the flush function was called"
    last_flush::DateTime = DateTime(0)
    "Additional attributes for the watcher"
    attrs::Dict{Symbol,Any} = Dict{Symbol,Any}()
end
const WATCHERS = Misc.ConcurrentCollections.ConcurrentDict{String,Watcher}()

@doc """ Instantiate a watcher.

$(TYPEDSIGNATURES)

This function creates a new watcher with the specified parameters.
It checks the flush interval, initializes the watcher, loads data if necessary, and sets a timer for the watcher if the `start` parameter is `true`.
It also ensures that the `_fetch!` function is applicable for the watcher.


!!! warning "asyncio vs threads"
    BuyOrSell `_fetch!` and `_flush!` callbacks assume non-blocking asyncio like behaviour. If instead your functions require \
    high computation, pass `threads=true`, you will have to ensure thread safety.
"""
function _watcher(
    T::Type,
    name::String,
    val::Val=Val(Symbol(name));
    start=true,
    load=true,
    process=false,
    flush=false,
    threads=false,
    fetch_timeout=Second(5),
    fetch_interval=Second(30),
    flush_interval=Second(360),
    buffer_capacity=100,
    view_capacity=1000,
    attrs=Dict{Symbol,Any}(),
)
    flush && _check_flush_interval(flush_interval, fetch_interval, buffer_capacity)
    haskey(attrs, :last_processed) || (attrs[:last_processed] = nothing)
    @debug "new watcher: $name"
    w = Watcher{T}(;
        buffer=CircularBuffer{BufferEntry(T)}(buffer_capacity),
        name=String(name),
        has=HasFunction((load, process, flush)),
        interval=Interval((fetch_timeout, fetch_interval, flush_interval)),
        capacity=Capacity((buffer_capacity, view_capacity)),
        beacon=(;
            fetch=Rocket.Subject(Any),
            process=Rocket.Subject(Any),
            flush=Rocket.Subject(Any),
        ),
        _exec=Exec((
            threads, SafeLock(), SafeLock(), CircularBuffer{Tuple{Any,Vector}}(10)
        )),
        _val=val,
        attrs,
    )
    @assert applicable(_fetch!, w, _val(w)) "`_fetch!` function not declared for `Watcher` \
        with id $(w.name) (It must accept a `Watcher` as argument, and return a boolean)."
    w = finalizer(close, w)
    @debug "_init $name"
    _init!(w, _val(w))
    logfile = get(attrs, :logfile, nothing)
    if !isnothing(logfile)
        maxlines = get(attrs, :logfile_maxlines, 10000)
        @debug "truncating logfile" logfile maxlines
        truncate_file(logfile, maxlines)
    end
    @debug "_load for $name? $(w.has.load)"
    w.has.load && _load!(w, _val(w))
    w.last_flush = now() # skip flush on start
    @debug "setting up fetch pipeline for $name"
    start && _setup_fetch_pipeline!(w)
    @debug "watcher $name initialized!"
    w
end

@doc """ Instantiate a watcher and add it to the global watchers list.

$(TYPEDSIGNATURES)

This function creates a new watcher with the specified parameters and adds it to the global `WATCHERS` list. If a watcher with the same name already exists in the list, it replaces the old watcher with the new one.
"""
function watcher(T::Type, name::String, args...; kwargs...)
    prev_w = pop!(WATCHERS, name, missing)
    if !ismissing(prev_w)
        close(prev_w)
        @warn "Replacing watcher $name with new instance."
    end
    WATCHERS[name] = _watcher(T, name, args...; kwargs...)
end

@doc "Close all watchers."
_closeall() = begin
    @debug "watchers: closing all watchers" n_watchers = length(collect(values(WATCHERS)))
    asyncmap(close, values(WATCHERS))
    @debug "watchers: closed all watchers" n_watchers = length(collect(values(WATCHERS)))
    # Only clear cache if WatchersImpls is loaded
    if isdefined(@__MODULE__, :WatchersImpls)
        empty!(WatchersImpls.OHLCV_CACHE)
    end
end

include("errors.jl")
include("defaults.jl")
include("functions.jl")

export Watcher, watcher, isstale, default_loader, default_flusher
export default_process, default_init, default_get
export pushnew!, pushstart!, start!, stop!, isstarted, isstopped, process!, load!, init!, average_ohlcv_watcher

include("apis/coinmarketcap.jl")
include("apis/coingecko.jl")
include("apis/coinpaprika.jl")
include("apis/dbnomics.jl")
include("apis/frankfurter.jl")
include("apis/fred.jl")
include("apis/alpha_vantage.jl")
include("apis/newsdata.jl")
include("apis/blockchain.jl")
include("apis/defillama.jl")
include("apis/glassnode.jl")
using .BlockchainAPI: tvl, stablecoins, stablecoin_chart, supply_ratio, active_addresses, holders_profit, large_movements
include("impls/impls.jl")
using .WatchersImpls: iswatchfunc, ccxt_tickers_watcher, ccxt_ohlcv_watcher, ccxt_ohlcv_candles_watcher, ccxt_orderbook_watcher, cg_ticker_watcher, cg_derivatives_watcher, cp_markets_watcher, cp_twitter_watcher, dbnomics_watcher, alpha_vantage_watcher, newsdata_watcher, defillama_tvl_watcher, defillama_stablecoins_watcher, defillama_supply_ratio_watcher, glassnode_active_addresses_watcher, glassnode_holders_profit_watcher, glassnode_large_movements_watcher
export iswatchfunc, ccxt_tickers_watcher, ccxt_ohlcv_watcher, ccxt_ohlcv_candles_watcher, ccxt_orderbook_watcher, cg_ticker_watcher, cg_derivatives_watcher, cp_markets_watcher, cp_twitter_watcher, dbnomics_watcher, alpha_vantage_watcher, newsdata_watcher, defillama_tvl_watcher, defillama_stablecoins_watcher, defillama_supply_ratio_watcher, glassnode_active_addresses_watcher, glassnode_holders_profit_watcher, glassnode_large_movements_watcher
export DefiLlama, Glassnode, BlockchainAPI, tvl, stablecoins, supply_ratio, stablecoin_chart, active_addresses, holders_profit, large_movements
# Set up cleanup after all modules are loaded
atexit(_closeall)
