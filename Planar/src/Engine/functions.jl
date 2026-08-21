import .LiveMode.Watchers.Fetch: fetch_ohlcv, propagate_ohlcv!, update_ohlcv!
import .Processing.Data: load_ohlcv
using .Exchanges: exchangeid, account

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
    @sync for ii in s.universe
        @async try
            exc = exchange(ii)
            sym = raw(ii)
            v = fetch_ohlcv(exc, s.timeframe, sym, from=-2000)
            data = get(v, sym, nothing)
            if isnothing(data)
                @error "fetch_ohlcv!: no data returned" ii asset=sym
                return
            end
            ii.data[s.timeframe] = data.data
            propagate_ohlcv!(ii.data, raw(ii), exc)
        catch e
            @error "fetch_ohlcv!: failed to fetch data" ii asset=raw(ii) exception = (
                e, catch_backtrace()
            )
        end
    end
end
function update_ohlcv!(s::Strategy; kwargs...)
    tf = s.timeframe
    @sync for ii in s.universe
        @async try
            exc = exchange(ii)
            sym = raw(ii)
            update_ohlcv!(ohlcv(ii, tf), sym, exc, tf; kwargs...)
            propagate_ohlcv!(ii.data, sym, exc)
        catch e
            @error "update_ohlcv!: failed to update data" ii asset=sym exception = (
                e, catch_backtrace()
            )
        end
    end
end
