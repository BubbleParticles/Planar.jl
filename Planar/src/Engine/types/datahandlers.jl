import .Data: propagate_ohlcv!
using .Data.DFUtils: copysubs!
using .LiveMode: cached_ohlcv!

@doc """[`load_universe!`](@ref) all the instances with given timeframes data...

$(TYPEDSIGNATURES)
"""
function load_universe!(ac::InstrumentCollection, tfs...; kwargs...)
    @eachrow ac.data fill!(:instance, tfs...; kwargs...)
end

function Misc.swapkeys(dict::AbstractDict; parse_args=(fiatnames,))
    swap_func(k) = begin
        a = parse(AbstractInstrument, k, parse_args...)
        (a.bc, a.qc)
    end
    swapkeys(dict, NTuple{2,Symbol}, swap_func)
end

function _seedfill!(ii::InstrumentInstance, src_dict)
    pd = get(src_dict, (ii.asset.bc, ii.asset.qc), nothing)
    if !isnothing(pd)
        for tf in keys(ii.data)
            data = ohlcv_dict(ii)
            new_data = resample(pd, tf)
            try
                empty!(data[tf])
                append!(data[tf], new_data)
            catch e
                e isa InterruptException && rethrow(e)
                @error "_seedfill!: resample/append failed" ii asset=raw(ii) tf exception=(e, catch_backtrace())
                data[tf] = new_data
            end
        end
    end
end

@doc """Replaces the data of the asset instances with `src` which should be a mapping. Used for backtesting.

$(TYPEDSIGNATURES)

The `stub_universe!` function takes the following parameters:

- `ac`: an InstrumentCollection object which encapsulates a collection of assets.
- `src`: The mapping, should be a pair `TimeFrame => Dict{String, PairData}`.
- `fromfiat` (optional, default is true): a boolean that indicates whether the assets are priced in fiat currency. If true, the assets are priced in fiat currency.

The function replaces the OHLCV data of the assets in the `ac` collection with the data from the `src` mapping. This is useful for backtesting trading strategies.

Example:
```julia
using PlanarDownloadTool.BinanceData as bn
using Strategies
using Exchanges
setexchange!(:binanceusdm)
cfg = Config(Symbol(exc.id))
strat = strategy!(:Example, cfg)
data = bn.binanceload()
stub_universe!(strat.universe, data)
```
"""
function stub_universe!(ac::InstrumentCollection, src; fromfiat=true)
    parse_args = fromfiat ? (fiatnames,) : ()
    src_dict = swapkeys(src; parse_args)
    for ii in ac.data.instance
        pd = get(src_dict, (ii.asset.bc, ii.asset.qc), nothing)
        isnothing(pd) && continue
        @debug "stub" ii = raw(ii)
        for tf in keys(ii.data)
            data = ohlcv_dict(ii)
            new_data = resample(pd, tf)
            try
                empty!(data[tf])
                append!(data[tf], new_data)
            catch e
                e isa InterruptException && rethrow(e)
                @error "stub_universe!: resample/append failed" ii asset=raw(ii) tf exception=(e, catch_backtrace())
                data[tf] = new_data
            end
        end
    end
end


function propagate_ohlcv!(ii::InstrumentInstance)
    # from `Fetch` module
    propagate_ohlcv!(ii.data, ii.asset.raw, ii.exchange)
end

propagate_ohlcv!(s::LiveStrategy) = begin
    foreach(propagate_ohlcv!, universe(s))
    cached_ohlcv!(s)
end
propagate_ohlcv!(s::Strategy) = foreach(propagate_ohlcv!, universe(s))


"""
    purge_data!(s::Strategy, sym::AbstractString; purge=true)

Explicitly purge cached OHLCV/Zarr data for `sym` after `removeasset!`.
No-op by default on remove; call this when audit retention is not needed.
"""
function purge_data!(s::Strategy, sym; purge=true)
    purge || return nothing
    try
        eid = exchangeid(s)
        tf = s.timeframe
        # clear in-memory
        ii = try asset_bysym(s, sym) catch; nothing end
        if !isnothing(ii)
            try empty!(ohlcv(ii, tf)) catch; end
        end
        # clear cache entry if present
        try
            cached_ohlcv!(eid, ohlcvmethod(s), period(tf), string(sym))
            # overwrite with empty DataFrame in cache layer if supported
        catch e
            e isa InterruptException && rethrow(e)
            @error "purge_data!: cache clear failed" sym exception=(e, catch_backtrace())
        end
    catch e
        @warn "purge_data! failed" sym exception=(e, catch_backtrace())
    end
    return nothing
end

