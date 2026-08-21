using PlanarCore.Lang: @lget!, Option
using PlanarCore.TimeTicks
using PlanarCore.TimeTicks: now
using PlanarCore.Misc
using ..Watchers
import ..Watchers:
    _fetch!,
    _init!,
    _load!,
    _flush!,
    _process!,
    _get
using PlanarCore.Data
using PlanarCore.Data.DFUtils: appendmax!
using PlanarCore.Fetch.Processing
using PlanarCore.Data.DataFrames: DataFrame
using ..AlphaVantage: AlphaVantage as av

const AvTick = @NamedTuple begin
    symbol::Symbol
    timestamp::DateTime
    open::Float64
    high::Float64
    low::Float64
    close::Float64
    volume::Int64
    previous_close::Option{Float64}
    change::Option{Float64}
    change_percent::Option{String}
end

const AvTickerVal = Val{:alpha_vantage}

@doc """ Create a `Watcher` instance that tracks real-time quotes for symbols from Alpha Vantage.

Symbols should be standard ticker symbols (e.g., ["AAPL", "GOOGL", "MSFT"]).
"""
function alpha_vantage_watcher(syms::AbstractVector{String}; 
    interval=Second(720),
    start=true,
    load=true,
    process=false,
    flush=false,
    threads=false,
    fetch_timeout=Second(5),
    fetch_interval=interval,
    flush_interval=Second(3600),
    buffer_capacity=100,
    view_capacity=1000,
    kwargs...)
    attrs = Dict{Symbol,Any}()
    sort!(syms)
    attrs[:symbols] = syms
    attrs[:key] = join(("av_ticker", string.(syms)...), "_")
    attrs[:serialized] = true
    attrs[:names] = Symbol.(syms)
    watcher_type = NamedTuple{tuple(attrs[:names]...),NTuple{length(syms),AvTick}}
    wid = string(AvTickerVal.parameters[1], "-", hash(syms))
    watcher(
        watcher_type,
        wid,
        AvTickerVal();
        start=start,
        load=load,
        process=process,
        flush=flush,
        threads=threads,
        fetch_timeout=fetch_timeout,
        fetch_interval=fetch_interval,
        flush_interval=flush_interval,
        buffer_capacity=buffer_capacity,
        view_capacity=view_capacity,
        attrs,
    )
end
alpha_vantage_watcher(syms::Vararg{String}; kwargs...) = alpha_vantage_watcher([syms...]; kwargs...)

function _fetch!(w::Watcher, ::AvTickerVal)
    symbols = w[:symbols]
    names = w[:names]
    
    parsed_quotes = Dict{Symbol,AvTick}()
    
    for sym in symbols
        try
            json = av.fetch_daily(sym; outputsize="compact")
            
            ts_data = av.parse_daily_response(json)
            if !isnothing(ts_data) && !isempty(ts_data)
                # Get the most recent entry
                dates = collect(keys(ts_data))
                latest_date = maximum(dates)
                latest = ts_data[latest_date]
                
                # Alpha Vantage daily format: "1. open", "2. high", "3. low", "4. close", "5. volume"
                open_val = parse(Float64, latest["1. open"])
                high_val = parse(Float64, latest["2. high"])
                low_val = parse(Float64, latest["3. low"])
                close_val = parse(Float64, latest["4. close"])
                volume_val = parse(Int64, latest["5. volume"])
                
                dt = DateTime(string(latest_date))
                
                parsed_quotes[Symbol(sym)] = AvTick((
                    Symbol(sym),
                    dt,
                    open_val,
                    high_val,
                    low_val,
                    close_val,
                    volume_val,
                    nothing,
                    nothing,
                    nothing,
                ))
            end
        catch e
            @error "alpha_vantage: failed to fetch quote" symbol=sym exception=e
            continue
        end
    end
    
    if isempty(parsed_quotes)
        @warn "alpha_vantage: no quotes returned" symbols
        return false
    end
    
    # Build the named tuple in the correct order
    value = NamedTuple{tuple(names...)}(
        [get(parsed_quotes, name, AvTick((name, DateTime(0), 0.0, 0.0, 0.0, 0.0, 0, nothing, nothing, nothing))) for name in names]
    )
    
    pushnew!(w, value)
    true
end

function _av_ticker_append_buffer(dict, buf, maxlen)
    data = @collect_buffer_data buf Symbol AvTick
    @append_dict_data dict data maxlen
end

_init!(w::Watcher, ::AvTickerVal) = default_init(w, Dict{Symbol,DataFrame}())
_process!(w::Watcher, ::AvTickerVal) = default_process(w, _av_ticker_append_buffer)