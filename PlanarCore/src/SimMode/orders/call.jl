import ..Executors: call!
using ..Executors
using ..Executors: iscommittable, priceat, marketorder, hold!, AnyLimitOrder, orders
using ..OrderTypes: LimitOrderType, MarketOrderType
using ..OrderTypes: positionside as _positionside
using ..Lang: @lget!, Option
using ..Instances: ishedged, isopen, iszero, position, raw
using ..Misc: Long, Short, opposite
function call!(s::NoMarginStrategy{Sim}, ii, t::Type{<:AnyLimitOrder}; amount, kwargs...)
    if _positionside(t) == Short()
        @debug "NoMargin: rejecting short limit order" ii=raw(ii) order_type=t
        return nothing
    end
    fees_kwarg, order_kwargs = splitkws(:fees; kwargs)
    o = create_sim_limit_order(s, t, ii; amount, order_kwargs...)
    isnothing(o) && return nothing
    limitorder_ifprice!(s, o, o.date, ii; fees_kwarg...)
end

@doc """ Creates a simulated limit order for a margin strategy.

$(TYPEDSIGNATURES)

Same logic as `NoMarginStrategy` but dispatches for margin strategies.
Enforces hedged gating (hedged allows both sides, non-hedged blocks opposite).
"""
function call!(s::MarginStrategy{Sim}, ii, t::Type{<:AnyLimitOrder}; amount, kwargs...)
    !singlewaycheck(s, ii, t) && return nothing
    fees_kwarg, order_kwargs = splitkws(:fees; kwargs)
    o = create_sim_limit_order(s, t, ii; amount, order_kwargs...)
    isnothing(o) && return nothing
    limitorder_ifprice!(s, o, o.date, ii; fees_kwarg...)
end

@doc """ Creates a simulated market order for a margin strategy.

$(TYPEDSIGNATURES)

Same logic as `NoMarginStrategy` but dispatches for margin strategies.
Enforces hedged gating.
"""
function call!(
    s::MarginStrategy{Sim}, ii, t::Type{<:AnyMarketOrder}; amount, date, kwargs...
)
    !singlewaycheck(s, ii, t) && return nothing
    fees_kwarg, order_kwargs = splitkws(:fees; kwargs)
    o = create_sim_market_order(s, t, ii; amount, date, order_kwargs...)
    isnothing(o) && return nothing
    marketorder!(s, o, ii, amount; date, fees_kwarg...)
end

function call!(
    s::NoMarginStrategy{Sim}, ii, t::Type{<:AnyMarketOrder}; amount, date, kwargs...
)
    if _positionside(t) == Short()
        @debug "NoMargin: rejecting short market order" ii=raw(ii) order_type=t
        return nothing
    end
    fees_kwarg, order_kwargs = splitkws(:fees; kwargs)
    o = create_sim_market_order(s, t, ii; amount, date, order_kwargs...)
    isnothing(o) && return nothing
    marketorder!(s, o, ii, amount; date, fees_kwarg...)
end

@doc """ Cancel orders for a specific asset instance.

$(TYPEDSIGNATURES)

The function `call!` cancels all orders for a specific asset instance `ii`.
It iterates over the orders of the asset and cancels each one using `cancel!`.
Parameters include a strategy `s`, an asset instance `ii`, and a type `t` which defaults to `BuyOrSell`.
Additional arguments can be passed through `kwargs...`.
"""
function call!(
    s::Strategy{<:Union{Paper,Sim}},
    ii::InstrumentInstance,
    ::CancelOrders;
    t::Type{<:OrderSide}=BuyOrSell,
    kwargs...,
)::Bool
    all(cancel!(s, o, ii; err=OrderCanceled(o)) for o in values(s, ii, t))
end

@doc """ Cancels all orders for a NoMarginStrategy.
$(TYPEDSIGNATURES)
"""
function call!(
    s::NoMarginStrategy{Sim},
    ii::NoMarginInstance,
    ::CancelOrders;
    kwargs...,
)::Bool
    all(cancel!(s, o, ii; err=OrderCanceled(o)) for o in values(s, ii, BuyOrSell))
end
