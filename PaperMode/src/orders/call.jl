using PlanarCore.SimMode: create_sim_limit_order, limitorder_ifprice!, hold!
using .st: NoMarginStrategy
using .OrderTypes: LimitOrderType, ImmediateOrderType, AnyMarketOrder
using .Misc.Lang: splitkws
using .Misc: DFT

@doc """Creates a paper market order.

$(TYPEDSIGNATURES)

The function creates a paper market order for a given strategy and asset. 
It specifies the amount of the order and the type of order (e.g., limit order, immediate order).

"""
function call!(
    s::NoMarginStrategy{Paper},
    ai,
    t::Type{<:AnyMarketOrder};
    amount,
    date,
    price=priceat(s, t, ai, nothing),
    kwargs...,
)
    fees_kwarg, order_kwargs = splitkws(:fees; kwargs)
    # Handle NaN price from priceat
    price = isnan(price) ? zero(DFT) : convert(DFT, price)
    try
        o, obside = create_paper_market_order(s, t, ai; amount, date, price, order_kwargs...)
        isnothing(o) && return nothing
        marketorder!(s, o, ai; date, obside, fees_kwarg...)
    catch e
        e isa InterruptException && rethrow(e)
        @error "NoMarginStrategy: market order failed" exception = (e, catch_backtrace()) raw(ai)
        return nothing
    end
end

@doc """Creates a simulated limit order.

$(TYPEDSIGNATURES)

The function creates a simulated limit order for a given strategy and asset.
It specifies the amount of the order and the date. 
Additional keyword arguments can be passed.

"""
function call!(
    s::NoMarginStrategy{Paper},
    ai,
    t::Type{<:Order{<:LimitOrderType}};
    amount,
    date,
    kwargs...,
)
    create_paper_limit_order!(s, ai, t; amount, date, kwargs...)
end
