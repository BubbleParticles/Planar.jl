import ..Executors: call!
using ..Executors
using ..Executors: iscommittable, priceat, marketorder, hold!, AnyLimitOrder
using ..OrderTypes: LimitOrderType, MarketOrderType
using ..Lang: @lget!, Option

@doc """ Creates a simulated limit order.

$(TYPEDSIGNATURES)

The function `call!` is responsible for creating a simulated limit order.
It creates the order using `create_sim_limit_order`, checks if the order is not `nothing`, and then calls `limitorder_ifprice!`.
The parameters include a strategy `s`, an asset `ii`, and a type `t`. The function also accepts an `amount` and additional arguments `kwargs...`.
"""
function call!(s::NoMarginStrategy{Sim}, ii, t::Type{<:AnyLimitOrder}; amount, kwargs...)
    fees_kwarg, order_kwargs = splitkws(:fees; kwargs)
    o = create_sim_limit_order(s, t, ii; amount, order_kwargs...)
    isnothing(o) && return nothing
    limitorder_ifprice!(s, o, o.date, ii; fees_kwarg...)
end

@doc """ Creates a simulated limit order for a margin strategy.

$(TYPEDSIGNATURES)

Same logic as `NoMarginStrategy` but dispatches for margin strategies.
"""
function call!(s::MarginStrategy{Sim}, ii, t::Type{<:AnyLimitOrder}; amount, kwargs...)
    fees_kwarg, order_kwargs = splitkws(:fees; kwargs)
    o = create_sim_limit_order(s, t, ii; amount, order_kwargs...)
    isnothing(o) && return nothing
    limitorder_ifprice!(s, o, o.date, ii; fees_kwarg...)
end

@doc """ Creates a simulated market order for a margin strategy.

$(TYPEDSIGNATURES)

Same logic as `NoMarginStrategy` but dispatches for margin strategies.
"""
function call!(
    s::MarginStrategy{Sim}, ii, t::Type{<:AnyMarketOrder}; amount, date, kwargs...
)
    fees_kwarg, order_kwargs = splitkws(:fees; kwargs)
    o = create_sim_market_order(s, t, ii; amount, date, order_kwargs...)
    isnothing(o) && return nothing
    marketorder!(s, o, ii, amount; date, fees_kwarg...)
end

@doc """ Creates a simulated market order.

$(TYPEDSIGNATURES)

The function `call!` creates a simulated market order using `create_sim_market_order`.
It checks if the order is not `nothing`, and then calls `marketorder!`.
Parameters include a strategy `s`, an asset `ii`, a type `t`, an `amount` and a `date`.
Additional arguments can be passed through `kwargs...`.
"""
function call!(
    s::NoMarginStrategy{Sim}, ii, t::Type{<:AnyMarketOrder}; amount, date, kwargs...
)
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
