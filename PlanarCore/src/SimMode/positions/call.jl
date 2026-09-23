using ..Executors.Instances: leverage!, positionside, leverage, MarginInstance
using ..Executors: cancel!, call!, CancelOrders
using ..Executors.Instances: raw
using ..Executors.OrderTypes: OrderCanceled, BuyOrSell
using ..Strategies: MarginStrategy, NoMarginStrategy
using ..Instances: ishedged, NoMarginInstance
using ..Lang: splitkws
using ..Misc: LittleDict

const _PROTECTIONS_WARNING = """
    the position would be liquidated, and would prevent you to do such trade, however we
    always check after the trade, and liquidate accordingly, this is pessimistic since
    we can't ensure that all exchanges have such protections in place.
"""

function singlewaycheck(s, ii, t)
    # Hedged mode allows both sides simultaneously
    ishedged(ii) && return true
    pside = positionside(t)
    opside = opposite(pside)
    opside_inst = opside isa Type ? opside() : opside
    # HACK: see Instances `status!`
    if isopen(ii, opside) && !iszero(ii, opside_inst)
        return false
    end
    for (_, o) in orders(s, ii)
        if positionside(o) == opside
            return false
        end
    end
    return true
end
@doc "Closes a leveraged position."
function call!(
    s::MarginStrategy{<:Union{Paper,Sim}},
    ii::MarginInstance,
    side::ByPos,
    date,
    ::PositionClose;
    kwargs...,
)::Bool
    if ishedged(ii)
        # Position-scoped cancel: `postoside(Long)=Buy` only cancels Long-Buy
        # orders (Buy side), but a Long position has both Buy (increase) and
        # Sell (reduce) orders. Cancel every order whose `posside(o)==side`
        # via `orders(s, ii, side)` (position-scoped) so the opposite position's
        # orders are preserved.
        cancel_ok = true
        for (_, o) in collect(orders(s, ii, side))
            cancel_ok &= cancel!(s, o, ii; err=OrderCanceled(o))
        end
        cancel_ok || @warn "close_position: failed to cancel orders" ii = raw(ii) side
    else
        cancel_ok = call!(s, ii, CancelOrders(); t=BuyOrSell)
        cancel_ok || @warn "close_position: failed to cancel orders" ii = raw(ii) side
    end
    v = close_position!(s, ii, side, date; kwargs...)
    if !v
        # Live reports close failure as `false` (retryable); Sim/Paper must
        # match so bulk-close callers get per-ii results instead of an abort
        # that skips the remaining holdings.
        @error "close_position! returned false (failed to close position)" ii=raw(ii) side
        return false
    end
    @deassert !isopen(ii, side)
    v
end
@doc "Closes all strategy positions"
function call!(s::MarginStrategy{<:Union{Sim,Paper}}, side::ByPos, date, ::PositionClose; kwargs...)
    # Snapshot: `close_position!` deletes from `s.holdings` on the last-side
    # close, so iterating the live set would skip holdings or throw.
    LittleDict(
        ii => call!(s, ii, side, date, PositionClose(); kwargs...) for ii in collect(s.holdings)
    )
end
@doc "Closes all strategy positions (no margin)"
function call!(s::NoMarginStrategy{<:Union{Sim,Paper}}, side::ByPos, date, ::PositionClose; kwargs...)
    LittleDict(
        ii => call!(s, ii, side, date, PositionClose(); kwargs...) for ii in s.universe
    )
end

_lev_value(lev::Function) = lev()
_lev_value(lev) = lev

# TODO: implement leverage update mechanisms when position is open (and or has orders)
@doc "Update position leverage. Returns true if the update was successful, false otherwise.

The leverage is not updated when the position has pending orders or is open (and it will return false in such cases.)
"
function call!(
    s::MarginStrategy{<:Union{Sim,Paper}},
    ii::MarginInstance,
    lev,
    ::UpdateLeverage;
    pos::PositionSide,
    kwargs...,
)
    if isopen(ii, pos) || hasorders(s, ii, pos)
        false
    else
        leverage!(ii, _lev_value(lev), pos)
        @deassert isapprox(leverage(ii, pos), _lev_value(lev), atol=1e-1) (
            leverage(ii, pos), lev
        )
        true
    end
end
@doc "NoMargin strategies have no leverage; UpdateLeverage is a no-op (returns false)."
function call!(
    s::NoMarginStrategy{<:Union{Sim,Paper}},
    ii::NoMarginInstance,
    lev,
    ::UpdateLeverage;
    pos::PositionSide,
    kwargs...,
)::Bool
    false
end

@doc "Closes a leveraged position (no margin)."
function call!(
    s::NoMarginStrategy{Sim},
    ii::NoMarginInstance,
    side::ByPos,
    date,
    ::PositionClose;
    kwargs...,
)::Bool
    # No positions exist in spot mode, but pending spot orders do — a
    # "close all" that reports success while leaving them live is a silent
    # no-op. Cancel everything; the bulk NoMargin path funnels through here.
    call!(s, ii, CancelOrders(); t=BuyOrSell)
    true
end
