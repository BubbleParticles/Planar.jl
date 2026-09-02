using .Checks: sanitize_price, sanitize_amount
using .Checks: iscost, ismonotonic, SanitizeOff, cost, withfees
using ..Strategies: PriceTime, universe, inuniverse, Strategies as st
using ..Collections: snapshot
using ..Instances:
    MarginInstance, NoMarginInstance, InstrumentInstance, @rprice, @ramount, amount_with_fees
using ..OrderTypes:
    IncreaseOrder, ShortBuyOrder, LimitOrderType, MarketOrderType, PostOnlyOrderType
using ..OrderTypes: ExchangeID, ByPos, ordertype
using ..Instruments: AbstractInstrument
using Base: negate, beginsym
using ..Lang: @lget!, @deassert, @caller
using ..Misc: Long, Short, PositionSide

@doc """ Type alias for any limit order """
const AnyLimitOrder{S<:OrderSide,P<:PositionSide} = Order{
    <:LimitOrderType{S},<:AbstractInstrument,<:ExchangeID,P
}

@doc """ Type alias for any GTC order """
const AnyGTCOrder = Union{GTCOrder,ShortGTCOrder}

@doc """ Type alias for any FOK order """
const AnyFOKOrder = Union{FOKOrder,ShortFOKOrder}

@doc """ Type alias for any IOC order """
const AnyIOCOrder = Union{IOCOrder,ShortIOCOrder}

@doc """ Type alias for any market order """
const AnyMarketOrder{S<:OrderSide,P<:PositionSide} = Order{
    <:MarketOrderType{S},<:AbstractInstrument,<:ExchangeID,P
}

@doc """ Type alias for any post only order """
const AnyPostOnlyOrder{S<:OrderSide,P<:PositionSide} = Order{
    <:PostOnlyOrderType{S},<:AbstractInstrument,<:ExchangeID,P
}

@doc """
Clamps the given values within the correct boundaries.

$(TYPEDSIGNATURES)
"""
function _doclamp(clamper, ii, whats...)
    ii = esc(ii)
    clamper = esc(clamper)
    expr = quote end
    for w in whats
        w = esc(w)
        push!(expr.args, :(isnothing($w) || begin
            $w = $clamper($ii, $w)
        end))
    end
    expr
end

@doc """
Ensures the price is within correct boundaries.

$(TYPEDSIGNATURES)
"""
macro price!(ii, prices...)
    _doclamp(:($(@__MODULE__).sanitize_price), ii, prices...)
end

@doc """
Ensures the amount is within correct boundaries.

$(TYPEDSIGNATURES)
"""
macro amount!(ii, amounts...)
    _doclamp(:($(@__MODULE__).sanitize_amount), ii, amounts...)
end

@doc """
Calculates the commitment for an increase order without margin.

$(TYPEDSIGNATURES)
"""
function committment(
    ::Type{<:IncreaseOrder}, ii::NoMarginInstance, price, amount; kwargs...
)
    @deassert amount > 0.0
    withfees(cost(price, amount), maxfees(ii), IncreaseOrder)
end

@doc """
Calculates the commitment for a leveraged position.

$(TYPEDSIGNATURES)
"""
function committment(
    o::Type{<:IncreaseOrder},
    ii::MarginInstance,
    price,
    amount;
    ntl=cost(price, amount),
    fees=ntl * maxfees(ii),
    lev=leverage(ii, positionside(o)()),
    kwargs...,
)
    margin = ntl / lev
    margin + fees
end

@doc """
Calculates the commitment when exiting a position for longs.

$(TYPEDSIGNATURES)
"""
function committment(::Type{<:SellOrder}, ii, price, amount; fees_base=0.0, kwargs...)
    @deassert amount > 0.0
    amount_with_fees(amount, fees_base)
end

@doc """
Calculates the commitment when exiting a position for shorts.

$(TYPEDSIGNATURES)
"""
function committment(::Type{<:ShortBuyOrder}, ii, price, amount; fees_base=0.0, kwargs...)
    @deassert amount > 0.0
    amount_with_fees(negate(amount), fees_base)
end

@doc """
Calculates the partial commitment of a trade.

$(TYPEDSIGNATURES)
"""
function committment(ii::InstrumentInstance, t::Trade)
    o = t.order
    committment(
        typeof(o), ii, o.price, t.amount; t.fees_base, t.fees, ntl=t.value, lev=t.leverage
    )
end

@doc """
Calculates the commitment for an order.

$(TYPEDSIGNATURES)
"""
function committment(ii::InstrumentInstance, o::Order; kwargs...)
    @debug "committment input" ii=ii order=o kwargs=kwargs
    res = committment(typeof(o), ii, o.price, o.amount; kwargs...)
    @debug "committment result" result=res
    res
end

@doc """
Calculates the unfulfilled amount for a buy order.

$(TYPEDSIGNATURES)
"""
function unfillment(t::Type{<:AnyBuyOrder}, amount)
    @deassert amount > 0.0
    @deassert !(t isa AnySellOrder)
    negate(abs(amount))
end

@doc """
Calculates the unfulfilled amount for a sell order.

$(TYPEDSIGNATURES)
"""
function unfillment(t::Type{<:AnySellOrder}, amount)
    @deassert amount > 0.0
    @deassert !(t isa AnyBuyOrder)
    amount
end

@doc """
Calculates the unfulfilled amount for an order.

$(TYPEDSIGNATURES)
"""
unfillment(o::Order) = unfillment(typeof(o), o.amount)


@doc """
Iterates over all the orders in a strategy.

$(TYPEDSIGNATURES)
"""
function orders(s::Strategy)
    OrderIterator((orders(s, ii, side) for side in (Buy, Sell) for ii in s.holdings))
end

@doc """
Iterates over all the orderless orders in a strategy.

$(TYPEDSIGNATURES)
"""
function orders(s::Strategy, ::Val{:orderless})
    (o for side in (Buy, Sell) for ii in s.holdings for o in orders(s, ii, side))
end

function orders(s::Strategy, ::BySide{O}, ::Val{:orderless}) where {O<:Union{Buy,Sell}}
    odict = ordersdict(s, O)
    (o for ii in s.holdings for o in odict[ii])
end

@doc """
Iterates over all the orders in a strategy (all the assets in the universe).

$(TYPEDSIGNATURES)
"""
function orders(s::Strategy, ::Val{:universe})
    OrderIterator((orders(s, ii, side) for side in (Buy, Sell) for ii in snapshot(s.universe)))
end

@doc """
Iterates orderlessly over all the orders in a strategy (all the assets in the universe).

$(TYPEDSIGNATURES)
"""
function orders(s::Strategy, ::Val{:orderless}, ::Val{:universe})
    OrderIterator((orders(s, ii, side) for side in (Buy, Sell) for ii in snapshot(s.universe)))
end

@doc """
Iterates over all the orders for an asset instance in a strategy.

$(TYPEDSIGNATURES)
"""
function orders(s::Strategy, ii::InstrumentInstance)
    buys = orders(s, ii, Buy)
    if isempty(buys)
        orders(s, ii, Sell)
    else
        sells = orders(s, ii, Sell)
        if isempty(sells)
            buys
        else
            OrderIterator(buys, sells)
        end
    end
end

@doc """
Iterates over all the orderless orders for an asset instance in a strategy.

$(TYPEDSIGNATURES)
"""
function orders(s::Strategy, ii::InstrumentInstance, ::Val{:orderless})
    (o for side in (Buy, Sell) for o in orders(s, ii, side))
end

@doc """
Returns all orders for an asset instance in a strategy.

$(TYPEDSIGNATURES)
"""
orders(s, ii, ::Type{BuyOrSell}) = orders(s, ii)

@doc """
Returns all buy orders for a strategy.

$(TYPEDSIGNATURES)
"""
orders(s::Strategy, ::BySide{Buy}) =
    OrderIterator(Iterators.flatten(pairs(dict) for dict in values(s.buyorders)))

@doc """
Returns all sell orders for a strategy.

$(TYPEDSIGNATURES)
"""
orders(s::Strategy, ::BySide{Sell}) =
    OrderIterator(Iterators.flatten(pairs(dict) for dict in values(s.sellorders)))

orders(s::Strategy, ::Type{BuyOrSell}) = orders(s)

@doc """
Returns all buy orders for an asset in a strategy.

$(TYPEDSIGNATURES)
"""
function orders(s::Strategy{M,S,E}, ii, ::BySide{Buy}) where {M,S,E}
    @lget! s.buyorders ii st.BuyOrdersDict{E}(st.BuyPriceTimeOrdering())
end

@doc """
Returns all sell orders for an asset in a strategy.

$(TYPEDSIGNATURES)
"""
function orders(s::Strategy{M,S,E}, ii, ::BySide{Sell}) where {M,S,E}
    @lget! s.sellorders ii st.SellOrdersDict{E}(st.SellPriceTimeOrdering())
end

"""
Returns a unique list of orders from the trade history of a given asset instance.

$(TYPEDSIGNATURES)
"""
function ordershistory(ii::InstrumentInstance)
    unique(t.order for t in trades(ii))
end

@doc """
Returns all keys for orders in a strategy.

$(TYPEDSIGNATURES)
"""
Base.keys(s::Strategy, args...; kwargs...) = (k for (k, _) in orders(s, args...; kwargs...))

@doc """
Returns all values for orders in a strategy.

$(TYPEDSIGNATURES)
"""
function Base.values(s::Strategy, args...; kwargs...)
    (o for (_, o) in orders(s, args...; kwargs...))
end

@doc """
Returns the first order for an asset in a strategy.

$(TYPEDSIGNATURES)
"""
function Base.first(s::Strategy{M,S,E}, ii, bs::BySide=BuyOrSell) where {M,S,E}
    values(s, ii, bs) |> first
end

@doc """
Returns the first index for an order for an asset in a strategy.

$(TYPEDSIGNATURES)
"""
function Base.firstindex(s::Strategy{M,S,E}, ii, bs::BySide=BuyOrSell) where {M,S,E}
    keys(s, ii, bs) |> first
end

@doc """
Returns the last order for an asset in a strategy.

$(TYPEDSIGNATURES)
"""
function Base.last(s::Strategy{M,S,E}, ii, bs::BySide=BuyOrSell) where {M,S,E}
    ans = missing
    for v in values(s, ii, bs)
        ans = v
    end
    ismissing(ans) && throw(BoundsError())
    ans
end

@doc """
Returns the last index for an order for an asset in a strategy.

$(TYPEDSIGNATURES)
"""
function Base.lastindex(s::Strategy{M,S,E}, ii, bs::BySide=BuyOrSell) where {M,S,E}
    ans = missing
    for k in keys(s, ii, bs)
        ans = k
    end
    ismissing(ans) && throw(BoundsError())
    ans
end

function ordersdict(s::Strategy, bs::BySide{O}) where {O<:Union{Buy,Sell}}
    bs === Buy ? s.buyorders : s.sellorders
end

@doc """
Returns the count of orders in a strategy.

$(TYPEDSIGNATURES)
"""
function orderscount(s::Strategy, ::BySide{O}) where {O}
    ans = 0
    foreach(ordersdict(s, O)) do (_, dict)
        ans += length(dict)
    end
    ans
end

@doc """
Returns the count of pending entry orders in a strategy.

$(TYPEDSIGNATURES)
"""
function orderscount(s::Strategy, ::Val{:increase})
    ans = 0
    itr = values(s)
    foreach(itr) do o
        if o isa IncreaseOrder
            ans += 1
        end
    end
    ans
end

@doc """
Returns the count of pending exit orders in a strategy.

$(TYPEDSIGNATURES)
"""
function orderscount(s::Strategy, ::Val{:reduce})
    ans = 0
    itr = values(s)
    foreach(itr) do o
        if o isa ReduceOrder
            ans += 1
        end
    end
    ans
end

function orderscount(s::Strategy, ::Val{:inc_red})
    inc_ans = 0
    dec_ans = 0
    itr = values(s)
    foreach(itr) do o
        if o isa IncreaseOrder
            inc_ans += 1
        elseif o isa ReduceOrder
            dec_ans += 1
        end
    end
    return inc_ans, dec_ans
end

@doc """
Returns the total count of pending orders in a strategy.

$(TYPEDSIGNATURES)
"""
function orderscount(s::Strategy)
    orderscount(s, Buy) + orderscount(s, Sell)
end

@doc """
Returns the count of orders for an asset in a strategy.

$(TYPEDSIGNATURES)
"""
function orderscount(s::Strategy, ii::InstrumentInstance)
    n = 0
    foreach(orders(s, ii)) do _
        n += 1
    end
    n
end

@doc """
Returns the count of orders for an asset in a strategy.

$(TYPEDSIGNATURES)
"""
orderscount(s::Strategy, ii::InstrumentInstance, ::Type{BuyOrSell}) = orderscount(s, ii)

@doc """
Returns the count of buy orders for an asset in a strategy.

$(TYPEDSIGNATURES)
"""
orderscount(s::Strategy, ii::InstrumentInstance, ::Type{Buy}) = length(buyorders(s, ii))

@doc """
Returns the count of sell orders for an asset in a strategy.

$(TYPEDSIGNATURES)
"""
orderscount(s::Strategy, ii::InstrumentInstance, ::Type{Sell}) = length(sellorders(s, ii))

@doc """Checks if any of the holdings has non dust cash.

$(TYPEDSIGNATURES)
"""
function hascash(s::Strategy)
    for ii in s.holdings
        iszero(ii) || return true
    end
    return false
end

@doc """
Checks if a strategy has orders.

$(TYPEDSIGNATURES)
"""
hasorders(s::Strategy) = orderscount(s) > 0

@doc """
Returns buy orders for an asset in a strategy.

$(TYPEDSIGNATURES)
"""
buyorders(s::Strategy, ii) = orders(s, ii, Buy)

@doc """
Returns sell orders for an asset in a strategy.

$(TYPEDSIGNATURES)
"""
sellorders(s::Strategy, ii) = orders(s, ii, Sell)

@doc """
Returns orders for an asset in a strategy by side.

$(TYPEDSIGNATURES)
"""
sideorders(s::Strategy, ii, ::Type{Buy}) = buyorders(s, ii)

@doc """
Returns orders for an asset in a strategy by side.

$(TYPEDSIGNATURES)
"""
sideorders(s::Strategy, ii, ::Type{Sell}) = sellorders(s, ii)

@doc """
Returns orders for an asset in a strategy by side.

$(TYPEDSIGNATURES)
"""
sideorders(s::Strategy, ii, ::BySide{S}) where {S} = sideorders(s, ii, S)

@doc """
Checks if an asset instance has pending buy orders in a strategy.

$(TYPEDSIGNATURES)
"""
hasorders(s::Strategy, ii, ::Type{S}) where {S<:Union{Buy,Sell}} = length(orders(s, ii, S)) > 0

@doc """
Checks if an asset instance has pending orders in a strategy.

$(TYPEDSIGNATURES)
"""
function hasorders(s::Strategy, ii::InstrumentInstance)
    hasorders(s, ii, Sell) || hasorders(s, ii, Buy)
end

function hasorders(s::Strategy, ii::InstrumentInstance, ::Type{BuyOrSell})
    hasorders(s, ii)
end

@doc """
Checks if an asset instance has a specific order in a strategy by side.

$(TYPEDSIGNATURES)
"""
function hasorders(s::Strategy, ii, id::String, ::BySide{S}=BuyOrSell) where {S<:OrderSide}
    for o in values(s, ii, S)
        o.id == id && return true
    end
    false
end

@doc """
Checks if a strategy has a specific order for an asset.

$(TYPEDSIGNATURES)
"""
Base.haskey(s::Strategy, ii, o::Order) = haskey(sideorders(s, ii, o), pricetime(o))

@doc """
Checks if a strategy has a specific order for an asset by price and time.

$(TYPEDSIGNATURES)
"""
function Base.haskey(s::Strategy, ii, pt::PriceTime, side::BySide{<:Union{Buy,Sell}})
    haskey(sideorders(s, ii, side), pt)
end

@doc """
Checks if a strategy has a specific order for an asset by price and time.

$(TYPEDSIGNATURES)
"""
function Base.haskey(s::Strategy, ii, pt::PriceTime, ::BySide{BuyOrSell})
    haskey(sideorders(s, ii, Buy), pt) || haskey(sideorders(s, ii, Sell), pt)
end

@doc """
Checks if a strategy has a specific order for an asset by price and time.

$(TYPEDSIGNATURES)
"""
Base.haskey(s::Strategy, ii, pt::PriceTime) = haskey(s, ii, pt, BuyOrSell)

@doc """
Checks if a strategy has sell orders.

$(TYPEDSIGNATURES)
"""
function hasorders(s::Strategy, ::BySide{S}) where {S<:OrderSide}
    for ii in universe(s)
        ords = sideorders(s, ii, S)
        if !isempty(ords)
            return true
        end
    end
    return false
end

@doc """
Checks if a strategy is out of orders.

$(TYPEDSIGNATURES)
"""
function isoutof_orders(s::Strategy)
    ltxzero(s.cash) && isempty(s.holdings) && orderscount(s) == 0
end

@doc """
Checks a buy trade.

$(TYPEDSIGNATURES)
"""
function _check_trade(t::BuyTrade, ii)
    @deassert t.price <= t.order.price || ordertype(t) <: MarketOrderType
    @deassert t.size < 0.0
    @deassert t.amount > 0.0
    @deassert if isshort(t)
        ltxzero(ii, committed(t.order), Val(:amount))
    else
        gtxzero(committed(t.order), atol=fees(t))
    end committed(t.order), t.order
end

@doc """
Checks a sell trade.

$(TYPEDSIGNATURES)
"""
function _check_trade(t::SellTrade, ii)
    @deassert t.price >= t.order.price || ordertype(t) <: MarketOrderType (
        t.price, t.order.price
    )
    @deassert t.size > 0.0
    @deassert t.amount < 0.0
    @deassert committed(t.order) >= -1e-12
end

@doc """
Checks a short sell trade.

$(TYPEDSIGNATURES)
"""
function _check_trade(t::ShortSellTrade, ii)
    @deassert t.price >= t.order.price || ordertype(t) <: MarketOrderType
    @deassert t.size < 0.0
    @deassert t.amount < 0.0
    @deassert abs(committed(t.order)) <= t.fees || t.order isa ShortSellOrder
end

@doc """
Checks a short buy trade.

$(TYPEDSIGNATURES)
"""
function _check_trade(t::ShortBuyTrade, ii)
    @deassert t.price <= t.order.price || ordertype(t) <: MarketOrderType (
        t.price, t.order.price
    )
    @deassert t.size > 0.0
    @deassert t.amount > 0.0
    @deassert committed(t.order) |> ltxzero
end

@doc """
Checks the cash for an asset instance in a strategy for long.

$(TYPEDSIGNATURES)
"""
function _check_cash(ii::InstrumentInstance, ::Long)
    @deassert gtxzero(ii, committed(ii, Long()), Val(:amount)) ||
        ordertype(last(ii.history)) <: MarketOrderType committed(ii, Long()).value
    @deassert cash(ii, Long()) |> gtxzero
end

@doc """
Checks the cash for an asset instance in a strategy for short.

$(TYPEDSIGNATURES)
"""
_check_cash(ii::InstrumentInstance, ::Short) = begin
    @deassert committed(ii, Short()) |> ltxzero
    @deassert cash(ii, Short()) |> ltxzero
end

_cur_by_side(o::BuyOrder) = :fees_base
_cur_by_side(o::SellOrder) = :fees
@doc """
The sum of all the trades fees that have heppened for the order.

$(TYPEDSIGNATURES)
"""
function feespaid(o::Order)
    ot = trades(o)
    if isempty(ot)
        0.0
    else
        cur = _cur_by_side(o)
        sum(getproperty(t, cur) for t in trades(o))
    end
end

tradetuple(t::Trade) = (t.order, t.price, t.size, t.amount)
function tradetuple(ii::InstrumentInstance, t::Trade)
    (
        t.order.id,
        t.order.date,
        toprecision(t.price, ii.precision.price),
        toprecision(t.size, ii.precision.amount),
        toprecision(t.amount, ii.precision.amount),
    )
end

@doc """
Check if the given trade is in the order.

$(TYPEDSIGNATURES)
"""
hastrade(o::Order, t::Trade) = begin
    tup = tradetuple(t)
    for t in trades(o)
        if tup == tradetuple(t)
            return true
        end
    end
    return false
end

@doc "More precise version of `hastrade`."
function hastrade(ii::InstrumentInstance, o::Order, t::Trade)
    tup = tradetuple(ii, t)
    for t in trades(o)
        if tup == tradetuple(ii, t)
            return true
        end
    end
    return false
end

@doc """
Returns the order that matches the given id (if any).

$(TYPEDSIGNATURES)
"""
function order_byid(s::Strategy, ii::InstrumentInstance, id::String)
    for o in values(s, ii)
        if o.id == id
            return o
        end
    end
end

function order_byid(s::Strategy, id::String)
    for ii in s.holdings
        o = order_byid(s, ii, id)
        if !isnothing(o)
            return o
        end
    end
end

isnocost(o::BySide) = ordertype(o) <: MarketOrderType
