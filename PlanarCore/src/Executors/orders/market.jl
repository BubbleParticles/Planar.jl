using ..OrderTypes: MarketOrderType, ExchangeID, PositionSide, PositionTrade
using Base: negate
import ..Instruments: cash!

@doc """ Executes a market order.

$(TYPEDSIGNATURES)

This function takes a strategy, an ii, an amount, and other optional arguments such as date, type, take, stop, price, and kwargs. It executes a market order with the given parameters. If `skipcommit` is set to false (default), the order is committed. Returns nothing.
"""
function marketorder(
    s::Strategy,
    ii,
    amount;
    date,
    type,
    take=nothing,
    stop=nothing,
    price,
    skipcommit=false,
    kwargs...,
)
    @price! ii take stop
    if type <: ReduceOnlyOrder
        amount = min(ii.limits.amount.max, amount)
    else
        @amount! ii amount
    end
    comm = Ref(committment(type, ii, price, amount))
    @debug "create market order:" ii = raw(ii) price amount cash(ii) comm type is_comm = iscommittable(s, type, comm, ii)
    if skipcommit || iscommittable(s, type, comm, ii)
        basicorder(ii, price, amount, comm, SanitizeOff(); date, type, kwargs...)
    end
end
@doc "Defines a long market buy trade type."
const LongMarketBuyTrade = Trade{<:MarketOrderType{Buy},<:AbstractInstrument,<:ExchangeID,Long}
@doc "Represents a long market sell trade on a certain exchange for a specific asset."
const LongMarketSellTrade = Trade{<:MarketOrderType{Sell},<:AbstractInstrument,<:ExchangeID,Long}

# FIXME: Should this be ≈/≉?
islastfill(t::Trade{<:MarketOrderType}) = true
isfirstfill(t::Trade{<:MarketOrderType}) = true
