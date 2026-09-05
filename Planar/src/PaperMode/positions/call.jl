using .st: MarginStrategy, NoMarginStrategy
using PlanarCore.Executors: CancelOrders
using PlanarCore.OrderTypes: BuyOrSell
using PlanarCore.Instances: NoMarginInstance, HedgedInstance, MarginInstance, ishedged
using .Executors: AnyMarketOrder
using PlanarCore.SimMode: singlewaycheck, close_position!
using PlanarCore.Collections: snapshot
using PlanarCore.Instances.Exchanges: lastprice
using PlanarCore.Instances: position, isopen, posside
using PlanarCore.Instances: PositionClose
using PlanarCore.OrderTypes: postoside
using PlanarCore.SimMode.OrderTypes: MarketOrder, ShortMarketOrder
using .Misc: DFT
using .Misc.Lang: splitkws

@doc """Creates a paper market order, updating a leveraged position.

$(TYPEDSIGNATURES)

The function creates a paper market order for a given strategy, asset, and order type.
It specifies the amount and date of the order.
Additional keyword arguments can be passed.

"""
function call!(
    s::MarginStrategy{Paper},
    ii::MarginInstance,
    t::Type{<:AnyMarketOrder};
    amount,
    date,
    price=priceat(s, t, ii, nothing),
    kwargs...,
)
    !singlewaycheck(s, ii, t) && return nothing
    fees_kwarg, order_kwargs = splitkws(:fees; kwargs)
    # Handle NaN price from priceat
    price = isnan(price) ? zero(DFT) : convert(DFT, price)
    o = create_paper_market_order(s, t, ii; amount, date, order_kwargs...)
    isnothing(o) && return nothing
    marketorder!(s, o, ii; date, obside=orderbook_side(ii, t))
end

@doc """Creates a simulated limit order.

$(TYPEDSIGNATURES)

The function creates a simulated limit order for a given strategy, asset, and order type.
It specifies the amount and date of the order.
Additional keyword arguments can be passed.

"""
function call!(
    s::MarginStrategy{Paper},
    ii::MarginInstance,
    t::Type{<:AnyLimitOrder};
    amount,
    date,
    kwargs...,
)
    !singlewaycheck(s, ii, t) && return nothing
    fees_kwarg, order_kwargs = splitkws(:fees; kwargs)
    create_paper_limit_order!(s, ii, t; amount, date, order_kwargs..., fees_kwarg...)
end


@doc "Closes a leveraged position (no margin)."
function call!(
    s::NoMarginStrategy{Paper},
    ii::NoMarginInstance,
    side::ByPos,
    date,
    ::PositionClose;
    kwargs...,
)::Bool
    true
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
    # In hedged mode, cancel only orders on the side being closed to preserve the opposite side's active orders.
    call!(s, ii, CancelOrders(); t=ishedged(ii) ? postoside(side) : BuyOrSell)
    v = close_position!(s, ii, side, date; kwargs...)
    if !v
        @error "close_position! returned false (failed to close position)" ii=raw(ii) side
        throw(ArgumentError("Failed to close position for $ii on side $side"))
    end
    @deassert !isopen(ii, side)
    v
end
