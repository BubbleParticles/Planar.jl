using PlanarCore.SimMode: create_sim_limit_order, limitorder_ifprice!, hold!, AnyLimitOrder, singlewaycheck
using .st: NoMarginStrategy, MarginStrategy
using PlanarCore.OrderTypes: LimitOrderType, ImmediateOrderType
using PlanarCore.OrderTypes: positionside
using PlanarCore.Misc: Short
using PlanarCore.Instances: raw, NoMarginInstance
using .Executors: AnyMarketOrder
using .Misc.Lang: splitkws
using .Misc: DFT

@doc """Creates a paper market order.

$(TYPEDSIGNATURES)

The function creates a paper market order for a given strategy and asset.
It specifies the amount of the order and the type of order (e.g., limit order, immediate order).

"""
function call!(
    s::NoMarginStrategy{Paper},
    ii,
    t::Type{<:AnyMarketOrder};
    amount,
    date,
    price=priceat(s, t, ii, nothing),
    kwargs...,
)
    if positionside(t) == Short()
        @debug "NoMargin: rejecting short market order" ii=raw(ii) order_type=t
        return nothing
    end
    fees_kwarg, order_kwargs = splitkws(:fees; kwargs)
    # Handle NaN price from priceat
    price = isnan(price) ? zero(DFT) : convert(DFT, price)
    try
        o, obside = create_paper_market_order(s, t, ii; amount, date, price, order_kwargs...)
        isnothing(o) && return nothing
        marketorder!(s, o, ii; date, obside, fees_kwarg...)
    catch e
        e isa InterruptException && rethrow(e)
        @error "NoMarginStrategy: market order failed" exception = (e, catch_backtrace()) raw(ii)
        return nothing
    end
end

@doc """Creates a paper market order for a margin strategy.

$(TYPEDSIGNATURES)

Same logic as `NoMarginStrategy` but dispatches for margin strategies.

"""
function call!(
    s::MarginStrategy{Paper},
    ii,
    t::Type{<:AnyMarketOrder};
    amount,
    date,
    price=priceat(s, t, ii, nothing),
    kwargs...,
)
    if !singlewaycheck(s, ii, t)
        return nothing
    end
    fees_kwarg, order_kwargs = splitkws(:fees; kwargs)
    # Handle NaN price from priceat
    price = isnan(price) ? zero(DFT) : convert(DFT, price)
    try
        o, obside = create_paper_market_order(s, t, ii; amount, date, price, order_kwargs...)
        isnothing(o) && return nothing
        marketorder!(s, o, ii; date, obside, fees_kwarg...)
    catch e
        e isa InterruptException && rethrow(e)
        @error "MarginStrategy: market order failed" exception = (e, catch_backtrace()) raw(ii)
        return nothing
    end
end

@doc """Creates a simulated limit order for a NoMarginStrategy.

$(TYPEDSIGNATURES)

"""
function call!(
    s::NoMarginStrategy{Paper},
    ii,
    t::Type{<:AnyLimitOrder};
    amount,
    date,
    kwargs...,
)
    !singlewaycheck(s, ii, t) && return nothing
    create_paper_limit_order!(s, ii, t; amount, date, kwargs...)
end

@doc """Creates a simulated limit order for a margin strategy.

$(TYPEDSIGNATURES)

Same logic as `NoMarginStrategy` but dispatches for margin strategies.

"""
function call!(
    s::MarginStrategy{Paper},
    ii,
    t::Type{<:AnyLimitOrder};
    amount,
    date,
    kwargs...,
)
    if !singlewaycheck(s, ii, t)
        return nothing
    end
    fees_kwarg, order_kwargs = splitkws(:fees; kwargs)
    create_paper_limit_order!(s, ii, t; amount, date, order_kwargs..., fees_kwarg...)
end
@doc """ Cancels all orders for a NoMarginStrategy.
$(TYPEDSIGNATURES)
"""
function call!(
    s::NoMarginStrategy{Paper},
    ii::NoMarginInstance,
    ::CancelOrders;
    kwargs...,
)::Bool
    all(cancel!(s, o, ii; err=OrderCanceled(o)) for o in values(s, ii, BuyOrSell))
end
