module Checks
using ..Lang: Option, @ifdebug, @deassert, @caller
using ..Misc: isstrictlysorted, toprecision, ltxzero
using ..Misc.DocStringExtensions
using ..Instances
using ..Strategies: NoMarginStrategy, MarginStrategy, Strategy
using ..OrderTypes
using ..Instances.Instruments: value
using Base: negate

struct SanitizeOn end
struct SanitizeOff end

@doc """ Calculate the absolute cost of a trade

$(TYPEDSIGNATURES)

The cost of a trade is always absolute, while fees can also be negative.
"""
cost(price, amount) = abs(price * amount)
cost(price, amount, leverage) = leverage <= 0 ? Inf : abs(price * amount) / leverage

@doc """ Calculate cost with fees for increasing a position

$(TYPEDSIGNATURES)

When increasing a position, fees are added to the currency spent.
"""
function withfees(cost, fees, ::T) where {T<:Union{IncreaseOrder,Type{<:IncreaseOrder}}}
    @deassert cost > 0.0
    muladd(cost, fees, cost)
end

@doc """ Calculate cost with fees for exiting a position

$(TYPEDSIGNATURES)

When exiting a position, fees are deducted from the received currency.
"""
function withfees(cost, fees, ::T) where {T<:Union{ReduceOrder,Type{<:ReduceOrder}}}
    @deassert cost > 0.0
    muladd(negate(cost), fees, cost)
end

checkprice(_::NoMarginStrategy, _, _, _) = nothing

@doc """ Check the price for long positions

$(TYPEDSIGNATURES)

The price of a trade for long positions should never be below the liquidation price.
"""
function checkprice(_::MarginStrategy, ii, actual_price, o::LongOrder)
    @assert actual_price > liqprice(ii, Long()) (o, actual_price, liqprice(ii, Long()))
end

@doc """ Check the price for short positions

$(TYPEDSIGNATURES)

The price of a trade for short positions should never be above the liquidation price.
"""
function checkprice(_::MarginStrategy, ii, actual_price, o::ShortOrder)
    @assert actual_price < liqprice(ii, Short()) (o, actual_price, liqprice(ii, Short()))
end

@doc """ Check the amount of a trade

$(TYPEDSIGNATURES)

Amount changes sign only after trade creation, it is always given as positive.
"""
checkamount(actual_amount) = @assert actual_amount >= 0.0

@doc """ Adjust the amount value of an order by subtraction

$(TYPEDSIGNATURES)

Price and amount value of an order are adjusted by subtraction. Their output values will always be lower than their input, except for the case in which their values would fall below the exchange minimums. In such case the exchange minimum is returned.
"""
function sanitize_amount(ii::InstrumentInstance, amount::N) where {N<:Real}
    if ii.limits.amount.min > 0.0 && amount < ii.limits.amount.min
        if amount < zero(amount)
            @warn "orders: amounts should never be negative (default to min amount)" ii ii.limits.amount.min maxlog = 1 @caller 20
        end
        ii.limits.amount.min
    elseif ii.precision.amount < 0.0 # has to be a multiple of 10
        max(toprecision(Int(amount), 10.0), ii.limits.amount.min)
    else
        toprecision(amount, ii.precision.amount)
    end
end

sanitize_amount(ii, amount) = sanitize_amount(ii, value(amount))

@doc """ Adjust the price value of an order

$(TYPEDSIGNATURES)

See `sanitize_amount`.
"""
function sanitize_price(ii::InstrumentInstance, price)
    @debug "sanitize_price input" ii=ii price=price
    out = if ii.limits.price.min > 0.0 && price < ii.limits.price.min
        ii.limits.price.min
    else
        max(toprecision(price, ii.precision.price), ii.limits.price.min)
    end
    @debug "sanitize_price result" result=out
    out
end

function _cost_msg(asset, direction, value, cost)
    "The cost ($cost) of the order ($asset) is $direction market minimum of $value"
end

@doc """
Check if the cost of an order is above the minimum limit

$(TYPEDSIGNATURES)

This function checks if the cost of an order is above the minimum limit for the exchange. It takes an InstrumentInstance, a price, and an amount as arguments and returns a boolean indicating whether the cost is above the minimum limit.
"""
function ismincost(ii::InstrumentInstance, price, amount)
    let min = ii.limits.cost.min
        iszero(min) || begin
            cost = price * amount
            cost >= min
        end
    end
end

@doc """ Check the minimum cost of an order

$(TYPEDSIGNATURES)

The cost of the order should not be below the minimum for the exchange.
"""
function checkmincost(ii::InstrumentInstance, price, amount)
    @assert ismincost(ii, price, amount) _cost_msg(
        ii.asset, "below", ii.limits.cost.min, price * amount
    )
    return true
end

@doc """ Check if the cost is below the maximum

$(TYPEDSIGNATURES)

This function checks if the cost of the order is below the maximum for the exchange.
"""
function ismaxcost(ii::InstrumentInstance, price, amount)
    let max = ii.limits.cost.max
        iszero(max) || begin
            cost = price * amount
            cost < max
        end
    end
end

@doc """ Check the maximum cost of an order

$(TYPEDSIGNATURES)

The cost of the order should not be above the maximum for the exchange.
"""
function checkmaxcost(ii::InstrumentInstance, price, amount)
    @assert ismaxcost(ii, price, amount) _cost_msg(
        ii.asset, "above", ii.limits.cost.max, price * amount
    )
    return true
end

function _checkcost(fmin, fmax, ii::InstrumentInstance, amount, prices...)
    ok = false
    for p in Iterators.reverse(prices)
        isnothing(p) || (fmax(ii, amount, p) && (ok = true; break))
    end
    ok || return false
    ok = false
    for p in prices
        isnothing(p) || (fmin(ii, amount, p) && (ok = true; break))
    end
    ok
end

@doc """ Check the cost of an order

$(TYPEDSIGNATURES)

Checks that the last price given is below maximum, and the first is above minimum. In other words, it expects all given prices to be already sorted.
"""
function checkcost(ii::InstrumentInstance, amount, prices...)
    _checkcost(checkmincost, checkmaxcost, ii, amount, prices...)
end

function checkcost(ii::InstrumentInstance; amount, price)
    checkmaxcost(ii, amount, price)
    checkmincost(ii, amount, price)
end

function iscost(ii::InstrumentInstance, amount, prices...)
    @ifdebug check_monotonic(prices...)
    _checkcost(ismincost, ismaxcost, ii, amount, prices...)
end

@doc """
Check if the cost of an order is within the limits

$(TYPEDSIGNATURES)

This function checks if the cost of an order is within the maximum and minimum limits. It takes an InstrumentInstance, an amount, and a price as arguments and returns a boolean indicating whether the cost is within the limits.
"""
function iscost(ii::InstrumentInstance; amount, price)
    ismaxcost(ii, amount, price) && ismincost(ii, amount, price)
end

ismonotonic(prices...) = isstrictlysorted(Iterators.filter(!isnothing, prices)...)

@doc """
Check if prices are sorted

$(TYPEDSIGNATURES)

This function checks if the given prices are sorted. It takes a variable number of prices as arguments and returns a boolean indicating whether the prices are sorted.
"""
function check_monotonic(prices...)
    @assert ismonotonic(prices...) "Prices should be sorted, e.g. stoploss < price < takeprofit"
    return true
end

export SanitizeOn, SanitizeOff, cost, withfees, checkprice, checkamount

end
