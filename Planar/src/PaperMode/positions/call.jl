using .st: MarginStrategy, NoMarginStrategy
using PlanarCore.Executors: CancelOrders, call!
using PlanarCore.OrderTypes: BuyOrSell
using PlanarCore.Instances: NoMarginInstance, HedgedInstance, MarginInstance, ishedged
using .Executors: AnyMarketOrder
using PlanarCore.SimMode: singlewaycheck, close_position!, liquidate!, maybe_liquidate!, position!, positions!,
       _maybe_liquidate_positions!, _cross_account_covered
using PlanarCore.Collections: snapshot
using PlanarCore.Instances.Exchanges: lastprice
using PlanarCore.Instances: position, isopen, posside
using PlanarCore.Instances: PositionClose
using PlanarCore.OrderTypes: postoside
using PlanarCore.SimMode.OrderTypes: MarketOrder, ShortMarketOrder
using .Misc: DFT
using .Misc.Lang: splitkws
using PlanarCore.Executors.OrderTypes: OrderCanceled
using PlanarCore.Misc: LittleDict


@doc "Closes a leveraged position (no margin)."
function call!(
    s::NoMarginStrategy{Paper},
    ii::NoMarginInstance,
    side::ByPos,
    date,
    ::PositionClose;
    kwargs...,
)::Bool
    # Same contract as the Sim twin: no positions, but pending spot orders
    # must not survive a reported-successful close.
    call!(s, ii, CancelOrders(); t=BuyOrSell)
end


@doc "Closes a leveraged position (margin)."
function call!(
    s::MarginStrategy{Paper},
    ii::MarginInstance,
    side::ByPos,
    date,
    ::PositionClose;
    kwargs...,
)::Bool
    # Paper shares Sim liquidation/position-close semantics (candle prices),
    # so the implementation mirrors SimMode.
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
@doc "Closes all strategy positions (margin)."
function call!(s::MarginStrategy{Paper}, side::ByPos, date, ::PositionClose; kwargs...)
    # Snapshot: `close_position!` deletes from `s.holdings` on the last-side
    # close, so iterating the live set would skip holdings or throw.
    LittleDict(
        ii => call!(s, ii, side, date, PositionClose(); kwargs...) for ii in collect(s.holdings)
    )
end


