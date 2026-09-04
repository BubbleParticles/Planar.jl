import .LiveMode.Watchers.Fetch: fetch_ohlcv, propagate_ohlcv!, update_ohlcv!
import .Processing.Data: load_ohlcv
using .Collections: snapshot
using .Strategies: assets
using .Exchanges: exchangeid, account
using PlanarCore.Instances: raw, ohlcv

function fetch_ohlcv(
    s::Strategy;
    sandbox=false,
    tf=s.config.min_timeframe,
    pairs=(raw(a) for a in assets(s)),
    fetch_kwargs...,
)
    exc = getexchange!(exchangeid(s); sandbox, account=account(s))
    tf_str = string(tf)
    pairs_str = collect(pairs)
    fetch_ohlcv(exc, tf_str, pairs_str; fetch_kwargs...)
end

function load_ohlcv(
    s::Strategy; tf=s.config.min_timeframe, pairs=(raw(a) for a in assets(s))
)
    exc = exchange(s)
    tf_str = string(tf)
    pairs_str = collect(pairs)
    load_ohlcv!(s)
end

function fetch_ohlcv!(s::Strategy)
    snap = snapshot(s.universe)
    @sync for ii in snap
        errormonitor(@async try
            exc = exchange(ii)
            sym = raw(ii)
            v = fetch_ohlcv(exc, s.timeframe, sym, from=-2000)
            data = get(v, sym, nothing)
            if isnothing(data)
                @error "fetch_ohlcv!: no data returned" ii asset=sym
                return
            end
            # guard before propagate: ensure still in universe
            in_uni = any(x -> x === ii || string(raw(x)) == sym, snapshot(s.universe))
            if !in_uni
                @debug "fetch_ohlcv!: skipping propagate for removed asset" sym
                return
            end
            ii.data[s.timeframe] = data.data
            propagate_ohlcv!(ii.data, raw(ii), exc)
        catch e
            @error "fetch_ohlcv!: failed to fetch data" ii asset=try raw(ii) catch; "unknown" end exception = (
                e, catch_backtrace()
            )
        end)
    end
end
function update_ohlcv!(s::Strategy; kwargs...)
    tf = s.timeframe
    snap = snapshot(s.universe)
    @sync for ii in snap
        errormonitor(@async try
            exc = exchange(ii)
            sym = raw(ii)
            update_ohlcv!(ohlcv(ii, tf), sym, exc, tf; kwargs...)
            in_uni = any(x -> x === ii || string(raw(x)) == sym, snapshot(s.universe))
            if !in_uni
                @debug "update_ohlcv!: skipping propagate for removed asset" sym
                return
            end
            propagate_ohlcv!(ii.data, sym, exc)
        catch e
            @error "update_ohlcv!: failed to update data" ii asset=try raw(ii) catch; "unknown" end exception = (
                e, catch_backtrace()
            )
        end)
    end
end

