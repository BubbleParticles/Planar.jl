@doc """ Creates a simulated market order.

$(TYPEDSIGNATURES)

This function creates a market order in a simulated environment.
It takes a strategy `s`, an order type `t`, and an asset `ii` as inputs, along with an `amount`, `date`, and `price`.
It also takes an optional `skipcommit` flag. If the order is valid, it is committed.
"""
function create_sim_market_order(
    s, t, ii; amount, date, price=priceat(s, t, ii, date), skipcommit=false, kwargs...
)
    o = marketorder(s, ii, amount; type=t, date, price, skipcommit, kwargs...)
    isnothing(o) && return nothing
    skipcommit || begin
        iscommittable(s, o, ii) || return nothing
        commit!(s, o, ii)
    end
    return o
end

@doc """ Executes a market order at a specified time if volume exists.

$(TYPEDSIGNATURES)

The function `marketorder!` executes a market order if the volume is available.
It takes a strategy `s`, an order `o`, an asset `ii`, and an `actual_amount`.
Optional parameters include a `date` and a `price` which defaults to `openat(ii, date)`.
"""
function marketorder!(
    s::Strategy{Sim},
    o::Order{<:MarketOrderType},
    ii,
    actual_amount;
    date,
    price=priceat(s, o, ii, date),
    kwargs...,
)
    t = trade!(s, o, ii; date, price, actual_amount, kwargs...)
    isnothing(t) || hold!(s, ii, o)
    t
end
