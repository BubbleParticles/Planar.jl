@doc "!!! editing this file triggers precompilation."
module TickStrat

using Planar

const DESCRIPTION = "TickStrat"
const EXC = :binance
const MARGIN = NoMargin
const TF = tf"1m"
@strategyenv!

using .ot: LimitOrder, Buy, Sell
using .ect: orders

# One-sided quote offset from the last trade price (5 bps half-spread).
const HALF_SPREAD = 0.0005
# Fraction of free cash committed behind each resting buy quote.
const QUOTE_FRACTION = 0.5

@doc """Tick-mode entrypoint — called once per market trade.

Quotes a resting buy limit just below the tick price and — only when the
asset is actually held — a resting sell limit just above it, at most one
order per side. Fills are evaluated on the next ticks by
`update!(s, tick, UpdateOrdersTick())` (runs before this function), so a
just-filled quote is already out of the book and the opposite leg re-quotes
the next tick.

Run with `examples/tick_backtest.jl`.
"""
function ping!(s::SC, ctx::TickContext, tick::TradeTick)
    ai = tick.asset
    price = tick.price
    # keep at most one resting order per side
    (isempty(orders(s, ai, Buy)) && isempty(orders(s, ai, Sell))) || return nothing
    # buy leg — size by free cash, quote below the last trade
    if freecash(s) > price * ai.limits.amount.min
        amt = clamp(
            QUOTE_FRACTION * freecash(s) / price,
            ai.limits.amount.min,
            ai.limits.amount.max,
        )
        call!(
            s, ai, LimitOrder{Buy};
            amount=amt, price=price * (1 - HALF_SPREAD), date=tick.timestamp,
        )
    end
    # sell leg — only what is actually held (spot: no shorting)
    held = float(ai)
    if held > 0
        call!(
            s, ai, LimitOrder{Sell};
            amount=min(held, ai.limits.amount.max),
            price=price * (1 + HALF_SPREAD), date=tick.timestamp,
        )
    end
    nothing
end

@doc """OHLCV-mode entrypoint — no-op, this strategy only trades on ticks."""
call!(s::SC, ts::DateTime, _) = nothing

call!(::SC, ::ResetStrategy) = nothing

@doc "Use every tick — no warmup lookback."
call!(_::SC, ::WarmupPeriod) = Millisecond(0)

const ASSETS = ["BTC/USDT", "ETH/USDT"]
call!(::Union{<:SC,Type{<:SC}}, ::StrategyMarkets) = ASSETS

function call!(t::Type{<:SC}, config, ::LoadStrategy)
    config.min_timeframe = tf"1m"
    config.timeframes = [tf"1m"]
    st.default_load(@__MODULE__, t, config)
end

end
