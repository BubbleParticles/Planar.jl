import ..Executors.Instances: _check_ticks_ordered!

using ..TimeTicks: dt

@doc """One market trade in a tick-by-tick backtest.

$(TYPEDSIGNATURES)

A single merged trade: the `timestamp`, the `asset` it belongs to, the `price` and the
`amount` traded. There is no `side` field — fills depend only on the price. `DateTime`
(ms) precision is kept; ticks within the same millisecond are valid.
"""
struct TradeTick
    timestamp::DateTime
    asset::AssetInstance
    price::DFT
    amount::DFT
end

@doc """A globally time-ordered sequence of market trades across the universe.

$(TYPEDSIGNATURES)

Constructing a `TradeTickRange` from a strategy merges every universe asset's tick
DataFrame into a single vector sorted by timestamp. The merge sort is stable, so ticks
within the same millisecond keep the universe order deterministically. Requires tick
data (via `setticks!`) for every universe asset.
"""
struct TradeTickRange
    ticks::Vector{TradeTick}
    function TradeTickRange(ticks::Vector{TradeTick})
        sort!(ticks; by=t -> t.timestamp, alg=Base.Sort.MergeSort)
        new(ticks)
    end
end

function TradeTickRange(s::Strategy)
    out = TradeTick[]
    for ai in s.universe
        _check_ticks_ordered!(ai)
        df = ticks(ai)
        if isempty(df)
            throw(
                ArgumentError(
                    "asset $(raw(ai)) has no tick data — set it with setticks!(ai, df)",
                ),
            )
        end
        for row in eachrow(df)
            ts = row.timestamp
            ts isa Integer && (ts = dt(ts))
            push!(out, TradeTick(ts, ai, row.price, row.amount))
        end
    end
    TradeTickRange(out)
end

Base.iterate(r::TradeTickRange, args...) = iterate(r.ticks, args...)
Base.length(r::TradeTickRange) = length(r.ticks)
Base.eltype(::Type{TradeTickRange}) = TradeTick
Base.getindex(r::TradeTickRange, i) = r.ticks[i]
Base.lastindex(r::TradeTickRange) = lastindex(r.ticks)

@doc """Execution context for tick-by-tick backtesting.

$(TYPEDSIGNATURES)

Mirrors `Context` (`Executors.context.jl`) but holds a `TradeTickRange` instead of a
`DateRange`; kept separate so `Context` and its constructors are untouched.
"""
struct TickContext{M<:ExecMode}
    trades::TradeTickRange
    function TickContext(::M, trades::TradeTickRange) where {M<:ExecMode}
        new{M}(trades)
    end
end

execmode(::TickContext{M}) where {M} = M

Base.similar(ctx::TickContext) = TickContext(execmode(ctx)(), ctx.trades)

export TradeTick, TradeTickRange, TickContext
