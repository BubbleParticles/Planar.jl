using ..Exchanges.Ccxt: CcxtGateway
using ..Exchanges: Exchange

@doc """Returns the trades-fetching gateway function for an exchange.

$(TYPEDSIGNATURES)

Tries the one-shot WS method (`fetchTradesWs`) first for lower latency and
falls back to REST (`fetchTrades`) on gateway failure — mirroring
`ohlcv_func_bykind`. Returns `nothing` when the exchange supports neither.
"""
function trades_func_bykind(exc::Exchange)
    first(exc, :fetchTradesWs, :fetchTrades)
end

@doc """Fetches real trades (the trades feed) for a pair from an exchange.

$(TYPEDSIGNATURES)

Paginates the exchange's `fetchTrades` `pages` times, `limit` trades per
page, starting from `since` (Unix-ms timestamp or `nothing`), through the
ccxt gateway. Per-page data arrives newest-first in ccxt's pagination; the
result is re-sorted oldest-first and de-duplicated on exact
`(timestamp, price, amount)` triples — same-millisecond trades are distinct
and kept.

Returns a `DataFrame` with columns `:timestamp` (`DateTime`), `:price`,
`:amount` — the schema consumed by `Instances.setticks!` for tick-by-tick
backtesting — or `nothing` when the exchange returns no trades.
"""
function fetch_trades(
    exc::Exchange,
    pair::AbstractString;
    since=nothing,
    limit=nothing,
    pages=1,
)
    fetch_func = trades_func_bykind(exc)
    isnothing(fetch_func) &&
        error("No trades fetch method available for exchange $(exc.name)")
    rows = Any[]
    for _ in 1:pages
        data = try
            fetch_func(pair, since, limit)
        catch e
            e isa InterruptException && rethrow(e)
            if CcxtGateway.isccxterror(e)
                @error "fetch_trades: gateway call failed" pair exception=(e, catch_backtrace())
                break
            else
                rethrow(e)
            end
        end
        (isnothing(data) || isempty(data)) && break
        append!(rows, data)
        since = Int(minimum(t -> to_float(t[:timestamp]), data)) - 1
        (!isnothing(limit) && length(data) < limit) && break
    end
    isempty(rows) && return nothing
    df = DataFrame(
        timestamp=[dt(Float64(to_float(t[:timestamp]))) for t in rows],
        price=[Float64(to_float(t[:price])) for t in rows],
        amount=[Float64(to_float(t[:amount])) for t in rows],
    )
    sort!(df, :timestamp)
    unique!(df, [:timestamp, :price, :amount])
    df
end

@doc """Fetches real trades for multiple pairs.

$(TYPEDSIGNATURES)

Batch form of `fetch_trades`: returns a `Dict` mapping each pair to its tick
`DataFrame`, or `nothing` for pairs the exchange returned no trades for.
Fetches are sequential to avoid exchange rate limits.
"""
function fetch_trades(
    exc::Exchange,
    pairs::Iterable;
    since=nothing,
    limit=nothing,
    pages=1,
)
    Dict(pair => fetch_trades(exc, pair; since, limit, pages) for pair in pairs)
end
