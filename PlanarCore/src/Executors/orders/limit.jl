using ..Instances
import ..Instances: committed, PositionOpen, PositionClose, freecash
using ..OrderTypes:
    LimitOrderType, PositionSide, ExchangeID, ShortSellOrder, FOKOrderType, IOCOrderType
using ..Strategies: NoMarginStrategy
using Base: negate
using ..Misc: Long, Short
using ..Lang: @ifdebug

@doc "Union type representing limit order increase operations. Includes Buy and Sell Short orders."
const IncreaseLimitOrder{A,E} = Union{LimitOrder{Buy,A,E},ShortLimitOrder{Sell,A,E}}

@doc "Union type representing limit order reduction operations. Includes Sell and Buy Short orders."
const ReduceLimitOrder{A,E} = Union{LimitOrder{Sell,A,E},ShortLimitOrder{Buy,A,E}}

@doc "Type representing a limit trade, includes long position limit orders."
const LimitTrade{S,A,E} = Trade{<:LimitOrderType{S},A,E,Long}

@doc "Type representing a short limit trade, includes short position limit orders."
const ShortLimitTrade{S,A,E} = Trade{<:LimitOrderType{S},A,E,Short}

@doc "Type representing a limit buy trade, specific to long position buy limit orders."
const LimitBuyTrade{A,E} = LimitTrade{Buy,A,E}

@doc "Type representing a limit sell trade, specific to long position sell limit orders."
const LimitSellTrade{A,E} = LimitTrade{Sell,A,E}

@doc "Type representing a short limit buy trade, specific to short position buy limit orders."
const ShortLimitBuyTrade{A,E} = ShortLimitTrade{Buy,A,E}

@doc "Type representing a short limit sell trade, specific to short position sell limit orders."
const ShortLimitSellTrade{A,E} = ShortLimitTrade{Sell,A,E}

@doc "Union type representing limit trade increase operations. Includes Buy and Sell Short trades."
const IncreaseLimitTrade{A,E} = Union{LimitBuyTrade{A,E},ShortLimitSellTrade{A,E}}

@doc "Union type representing limit trade reduction operations. Includes Sell and Buy Short trades."
const ReduceLimitTrade{A,E} = Union{LimitSellTrade{A,E},ShortLimitBuyTrade{A,E}}

@doc """ Places a limit order in the strategy

$(TYPEDSIGNATURES)

This function places a limit order with specified parameters in the strategy `s`. The `type` argument specifies the type of the order. The `price` defaults to the current price at the given `date` if not provided. The `take` and `stop` arguments are optional and default to `nothing`. If `skipcommit` is true, the function will not commit the order. Additional arguments can be passed via `kwargs`.

"""
function limitorder(
    s::Strategy,
    ii,
    amount;
    date,
    type,
    price=priceat(s, type, ii, date),
    take=nothing,
    stop=nothing,
    skipcommit=false,
    kwargs...,
)
    @debug "limitorder: entry" ii = raw(ii) date type price take stop kwargs
    @debug "limitorder: limits" ii.limits.price.min ii.precision.price
    @price! ii price take stop
    @amount! ii amount
    comm = Ref(committment(type, ii, price, amount))
    is_comm = iscommittable(s, type, comm, ii)
    free = try freecash(ii, posside(ii)) catch err; nothing end
    @debug "create limitorder:" ii = raw(ii) price amount comm[] is_comm free
    if skipcommit || is_comm
        basicorder(ii, price, amount, comm, SanitizeOff(); date, type, kwargs...)
    end
end

_cashfrom(s, _, o::IncreaseOrder) = st.freecash(s) + committed(o) # Increase→freecash(s) (s.cash_committed bucket) per margin-matrix freecash rows
_cashfrom(_, ii, o::ReduceOrder) = Instances.freecash(ii, positionside(o)()) + committed(o) # Reduce→freecash(ii, side) per margin-matrix

@doc """ Checks if the provided trade is the last fill for the given asset instance.

$(TYPEDSIGNATURES)
"""
function islastfill(ii::InstrumentInstance, t::Trade{<:LimitOrderType})
    o = t.order
    t.amount != o.amount && isfilled(ii, o)
end
@doc """ Checks if the provided trade is the first fill for the given asset instance.

$(TYPEDSIGNATURES)
"""
function isfirstfill(::InstrumentInstance, t::Trade{<:LimitOrderType})
    o = t.order
    attr(o, :unfilled)[] == negate(t.amount)
end

@doc """ Adds a limit order to the pending orders of the strategy.

$(TYPEDSIGNATURES)

This function takes a strategy, a limit order of type LimitOrderType{S}, and an asset instance as arguments. It adds the limit order to the pending orders of the strategy. If `skipcommit` is set to false (default), the order is committed and held. Returns true if the order was successfully added, otherwise false.
"""
function queue!(
    s::Strategy, o::Order{<:LimitOrderType{S}}, ii; skipcommit=false
) where {S<:OrderSide}
    @debug "queue limitorder:" is_comm = iscommittable(s, o, ii)
    # This is already done in general by the function that creates the order
    skipcommit || iscommittable(s, o, ii) || return false
    push!(s, ii, o)
    @deassert hasorders(s, ii, positionside(o))
    skipcommit || commit!(s, o, ii)
    hold!(s, ii, o)
    return true
end
