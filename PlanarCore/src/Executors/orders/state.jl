using ..Lang: @deassert, @lget!, Option, @ifdebug
using ..OrderTypes: ExchangeID
import ..OrderTypes: commit!, positionside, LiquidationType, ReduceOnlyOrder, trades
using ..Strategies: Strategies as st, NoMarginStrategy, MarginStrategy, IsolatedStrategy
using ..Instances: notional, pnl, Instances
import ..Instances: committed
using ..Misc: Short, DFT, toprecision
using ..Instruments
using ..Instruments: @importcash!, AbstractInstrument
import .Checks: cost
@importcash!
import ..Misc: reset!, attr

##  committed::DFT # committed is `cost + fees` for buying or `amount` for selling
const _BasicOrderState{T} = NamedTuple{
    (:take, :stop, :committed, :unfilled, :trades),
    Tuple{Option{T},Option{T},Ref{T},Ref{T},Vector{Trade}},
}

@doc """Constructs a basic order state with given parameters.

$(TYPEDSIGNATURES)

"""
function basic_order_state(
    # FIXME: should `trades` be a `SortedArray`?
    take,
    stop,
    committed::Ref{T},
    unfilled::Ref{T},
    trades=Trade[],
) where {T<:Real}
    _BasicOrderState{T}((take, stop, committed, unfilled, trades))
end

@doc """Constructs an `Order` for a given `OrderType` `type` and inputs.

$(TYPEDSIGNATURES)

"""
function basicorder(
    ii::InstrumentInstance,
    price,
    amount,
    committed,
    ::SanitizeOff;
    type::Type{<:Order},
    date,
    loss=nothing,
    profit=nothing,
    id="",
    tag="",
)
    if !ismonotonic(loss, price, profit)
        @debug "basic order: prices not monotonic" ii = raw(ii) loss price profit type
        return nothing
    end
    # don't check cost for market orders since they can go lower
    ignore_cost = isnocost(type)
    # Allow reduce only orders below minimum cost
    if !ignore_cost && !iscost(ii, amount, loss, price, profit)
        @debug "basic order: invalid cost" ii = raw(ii) amount loss price profit type
        return nothing
    end
    if !ignore_cost
        @deassert if type <: IncreaseOrder
            committed[] * leverage(ii, positionside(type)) >= ii.limits.cost.min
        else
            abs(committed[]) >= ii.limits.amount.min || ignore_cost
        end "Order committment too low\n$(committed[]), $(ii.asset) $date"
    end
    unfilled = Ref(unfillment(type, amount))
    @deassert type <: AnyBuyOrder ? unfilled[] < 0.0 : unfilled[] > 0.0
    OrderTypes.Order(
        ii,
        type;
        date,
        price,
        amount,
        id,
        tag,
        attrs=basic_order_state(profit, loss, committed, unfilled),
    )
end

@doc """Removes a single order from the order queue.

$(TYPEDSIGNATURES)

"""
function Base.delete!(s::Strategy, ii, o::IncreaseOrder)
    @deassert committed(o) |> approxzero o
    delete!(orders(s, ii, orderside(o)), pricetime(o))
    @deassert pricetime(o) ∉ keys(orders(s, ii, orderside(o)))
    # If we don't have cash for this asset, it should be released from holdings
    release!(s, ii)
end

@doc """Removes a single sell order from the order queue.

$(TYPEDSIGNATURES)

"""
function Base.delete!(s::Strategy, ii, o::SellOrder)
    @deassert committed(o) |> approxzero o
    delete!(orders(s, ii, orderside(o)), pricetime(o))
    # If we don't have cash for this asset, it should be released from holdings
    release!(s, ii)
end

@doc """Removes a single short buy order from the order queue.

$(TYPEDSIGNATURES)

"""
function Base.delete!(s::Strategy, ii, o::ShortBuyOrder)
    # Short buy orders have negative committment
    @deassert committed(o) |> approxzero o
    delete!(orders(s, ii, Buy), pricetime(o))
    # If we don't have cash for this asset, it should be released from holdings
    release!(s, ii)
end

@doc """Removes all buy/sell orders for an asset instance.

$(TYPEDSIGNATURES)

"""
function Base.delete!(s::Strategy, ii, t::Type{<:Union{Buy,Sell}})
    delete!.(s, ii, values(orders(s, ii, t)))
end

@doc """Removes all buy and sell orders for an asset instance.

$(TYPEDSIGNATURES)

"""
Base.delete!(s::Strategy, ii, ::Type{BuyOrSell}) = begin
    delete!(s, ii, Buy)
    delete!(s, ii, Sell)
end

@doc """Removes all orders for an asset instance.

$(TYPEDSIGNATURES)

"""
Base.delete!(s::Strategy, ii) = delete!(s, ii, BuyOrSell)

@doc """Inserts an order into the order dict of the asset instance. Orders should be identifiable by a unique (price, date) tuple.

$(TYPEDSIGNATURES)

"""
function Base.push!(s::Strategy, ii, o::Order{<:OrderType{S}}) where {S<:OrderSide}
    k = pricetime(o)
    d = orders(s, ii, S)
    # stok = searchsortedfirst(d, k)
    @ifdebug if k ∈ keys(d)
        @debug "Duplicate order key" o.id d[k].id o.price o.date
    end
    @assert k ∉ keys(d)
    d[k] = o
end
@doc """Checks if an order is already added to the queue.

$(TYPEDSIGNATURES)

"""
function isqueued(o::Order{<:OrderType{S}}, s::Strategy, ii) where {S<:OrderSide}
    let k = pricetime(o), d = orders(s, ii, S)
        k in keys(d)
    end
end

@doc """Checks order committment to be within expected values.

$(TYPEDSIGNATURES)

"""
function _check_committment(o)
    @deassert attr(o, :committed)[] |> gtxzero ||
        ordertype(o) <: MarketOrderType ||
        o isa IncreaseLimitOrder o
end

@doc """Checks if the unfilled amount for a limit sell order is positive.

$(TYPEDSIGNATURES)

"""
_check_unfillment(o::AnyLimitOrder{Sell}) = attr(o, :unfilled)[] > 0.0

@doc """Checks if the unfilled amount for a limit buy order is negative.

$(TYPEDSIGNATURES)

"""
_check_unfillment(o::AnyLimitOrder{Buy}) = attr(o, :unfilled)[] < 0.0

@doc """Checks if the unfilled amount for a market buy order is negative.

$(TYPEDSIGNATURES)

"""
_check_unfillment(o::AnyMarketOrder{Buy}) = attr(o, :unfilled)[] < 0.0

@doc """Checks if the unfilled amount for a market sell order is positive.

$(TYPEDSIGNATURES)

"""
_check_unfillment(o::AnyMarketOrder{Sell}) = attr(o, :unfilled)[] > 0.0

@doc """Checks if the unfilled amount for a long order is positive.

$(TYPEDSIGNATURES)

"""
_check_unfillment(o::LongOrder) = attr(o, :unfilled)[] > 0.0

@doc """Checks if the unfilled amount for a short order is negative.

$(TYPEDSIGNATURES)

"""
_check_unfillment(o::ShortOrder) = attr(o, :unfilled)[] < 0.0
@doc """Fills a buy order for a no-margin strategy.

$(TYPEDSIGNATURES)

"""
function applyfill!(
    ::Strategy{<:Union{Sim,Paper}}, ii::NoMarginInstance, o::BuyOrder, t::BuyTrade
)
    @deassert o isa IncreaseOrder && _check_unfillment(o) unfilled(o), typeof(o)
    @deassert committed(o) == o.attrs.committed[] && committed(o) >= 0.0
    # from neg to 0 (buy amount is pos)
    attr(o, :unfilled)[] += t.amount
    @deassert attr(o, :unfilled)[] |> ltxzero (o, t.amount)
    # from pos to 0 (buy size is neg)
    attr(o, :committed)[] -= committment(ii, t)
    @deassert gtxzero(ii, committed(o), Val(:price)) || o isa MarketOrder o,
    committment(ii, t)
end

@doc """Fills a sell order.

$(TYPEDSIGNATURES)

"""
function applyfill!(
    ::Strategy{<:Union{Sim,Paper}}, ii::InstrumentInstance, o::SellOrder, t::SellTrade
)
    @deassert o isa SellOrder && _check_unfillment(o)
    @deassert committed(o) == o.attrs.committed[] && committed(o) |> gtxzero
    # from pos to 0 (sell amount is neg)
    attr(o, :unfilled)[] += t.amount
    @deassert attr(o, :unfilled)[] |> gtxzero
    # from pos to 0 (sell amount is neg)
    attr(o, :committed)[] += t.amount
    @deassert committed(o) |> gtxzero
end

@doc """Fills a short buy order.

$(TYPEDSIGNATURES)

"""
function applyfill!(
    ::Strategy{<:Union{Sim,Paper}}, ii::InstrumentInstance, o::ShortBuyOrder, t::ShortBuyTrade
)
    @deassert o isa ShortBuyOrder && _check_unfillment(o) o
    @deassert committed(o) == o.attrs.committed[] && committed(o) |> ltxzero
    @deassert attr(o, :unfilled)[] < 0.0
    attr(o, :unfilled)[] += t.amount # from neg to 0 (buy amount is pos)
    @deassert attr(o, :unfilled)[] |> ltxzero
    # NOTE: committment is always positive except for short buy orders
    # where that's committed is shorted (negative) asset cash
    @deassert t.amount > 0.0 && committed(o) < 0.0
    attr(o, :committed)[] += t.amount # from neg to 0 (buy amount is pos)
    @deassert committed(o) |> ltxzero
end
@doc """Fills an increase order for a margin strategy.

$(TYPEDSIGNATURES)

"""
function applyfill!(
    ::MarginStrategy{<:Union{Sim,Paper}},
    ii::MarginInstance,
    o::IncreaseOrder,
    t::IncreaseTrade,
)
    @deassert o isa IncreaseOrder && _check_unfillment(o) o
    @deassert committed(o) == o.attrs.committed[] && committed(o) > 0.0 t
    attr(o, :unfilled)[] += t.amount
    @deassert attr(o, :unfilled)[] |> ltxzero || o isa ShortSellOrder
    @deassert t.value > 0.0
    attr(o, :committed)[] -= committment(ii, t)
    # Market order spending can exceed the estimated committment
    # ShortSell limit orders can spend more than committed because of slippage
    @deassert committed(o) |> gtxzero || o isa AnyMarketOrder || o isa IncreaseLimitOrder
end

@doc """Checks if an order is open.

$(TYPEDSIGNATURES)

"""
Base.isopen(ii::InstrumentInstance, o::Order) = !isfilled(ii, o)

@doc """Checks if the order amount left to fill is below minimum qty.

$(TYPEDSIGNATURES)

"""
Base.iszero(ii::InstrumentInstance, o::Order) = iszero(ii, unfilled(o))

@doc """Checks if the order committed value is below minimum quantity.

$(TYPEDSIGNATURES)

"""
function Instances.isdust(ii::InstrumentInstance, o::Order)
    unf = abs(unfilled(o))
    unf < ii.limits.amount.min ||
        unf * o.price < ii.limits.cost.min ||
        unf < ii.limits.amount.min * ii.fees.min
end

function Instances.isdust(ii::InstrumentInstance, o::ReduceOnlyOrder)
    false
end

@doc """Checks if an order is filled.

$(TYPEDSIGNATURES)

"""
isfilled(ii::InstrumentInstance, o::Order) =
    isdust(ii, o) || begin
        ot = trades(o)
        if !isempty(ot)
            abs(sum(t.amount for t in ot)) >= abs(o.amount)
        else
            false
        end
    end

@doc """Updates the strategy's cash after a buy trade.

$(TYPEDSIGNATURES)

"""
function strategycash!(s::NoMarginStrategy, ii, t::BuyTrade)
    @deassert t.size < 0.0
    add!(s.cash, t.size)
    sub!(s.cash_committed, committment(ii, t))
    @deassert gtxzero(ii, s.cash_committed, Val(:price))
end

@doc """Updates the strategy's cash after a sell trade.

$(TYPEDSIGNATURES)

"""
function strategycash!(s::NoMarginStrategy, _, t::SellTrade)
    @deassert t.size > 0.0
    add!(s.cash, t.size)
    @deassert s.cash |> gtxzero
end

@doc """Updates the strategy's cash after an increase trade.

$(TYPEDSIGNATURES)

"""
function strategycash!(s::MarginStrategy, ii, t::IncreaseTrade)
    @deassert t.size < 0.0
    # t.amount can be negative for short sells
    margin = t.value / t.leverage
    # subtract realized fees, and added margin
    @deassert t.fees > 0.0 || maxfees(ii) < 0.0
    spent = t.fees + margin
    @deassert spent > 0.0
    sub!(s.cash, spent)
    @ifdebug if committment(ii, t) > committed(s)
        @error "cash: trade committment can't be higher that total comm" trade = committment(
            ii, t
        ) total = committed(s) t
    end
    subzero!(s.cash_committed, committment(ii, t); atol=ii.limits.cost.min, dothrow=false)
    @deassert s.cash_committed |> gtxzero s.cash, s.cash_committed.value, orderscount(s)
end

function _showliq(s, unrealized_pnl, gained, po, t)
    get(s.attrs, :verbose, false) || return nothing
    if ordertype(t) <: LiquidationType
        @show positionside(t) s.cash margin(po) t.fees t.leverage t.size price(po) t.order.price t.price liqprice(
            po
        ) unrealized_pnl gained ""
    end
end

_checktrade(t::SellTrade) = @deassert t.amount < 0.0
_checktrade(t::ShortBuyTrade) = @deassert t.amount > 0.0

@doc """Updates the strategy's cash after a reduce trade.

$(TYPEDSIGNATURES)

"""
function strategycash!(s::MarginStrategy, ii, t::ReduceTrade)
    @deassert t.size > 0.0
    @deassert abs(cash(ii, positionside(t)())) >= abs(t.amount) (
        cash(ii), t.amount, t.order
    )
    @ifdebug _checktrade(t)
    po = position(ii, positionside(t))
    # The notional tracks current value, but the margin
    # refers to the notional from the (avg) entry price
    # of the position
    margin = abs(t.entryprice * t.amount) / t.leverage
    unrealized_pnl = pnl(po, t.price, t.amount)
    @deassert t.fees > 0.0 || maxfees(ii) < 0.0
    gained = margin + unrealized_pnl - t.fees # minus fees
    @ifdebug _showliq(s, unrealized_pnl, gained, po, t)
    @debug "strategycash reduce trade:" gained t.value margin unrealized_pnl t.fees po.entryprice[] cash(
        po
    ) t.price t.leverage t.amount posside(t) orderside(t)
    add!(s.cash, gained)
    @deassert s.cash |> gtxzero || (hasorders(s) || hascash(s)) (;
        s.cash, s.cash_committed, t.price, t.amount, unrealized_pnl, t.fees, margin
    )
end

@doc """Updates the strategy's and asset instance's cash after a trade.

$(TYPEDSIGNATURES)

"""
function cash!(s::Strategy, ii, t::Trade)
    @ifdebug _check_trade(t, ii)
    strategycash!(s, ii, t)
    cash!(ii, t)
    @ifdebug _check_cash(ii, positionside(t)())
end

@doc """Returns the attribute of an order.

$(TYPEDSIGNATURES)

"""
attr(o::Order, sym) = getfield(getfield(o, :attrs), sym)

@doc """Returns the absolute value of the unfilled amount of an order.

$(TYPEDSIGNATURES)

"""
unfilled(o::Order) = abs(attr(o, :unfilled)[])

@doc """Returns the filled amount of an order.

$(TYPEDSIGNATURES)

"""
filled_amount(o) = abs(o.amount) - unfilled(o)
@doc """Commits an increase order to a strategy.

$(TYPEDSIGNATURES)

"""
function commit!(s::Strategy, o::IncreaseOrder, _)
    @deassert committed(o) |> gtxzero
    add!(s.cash_committed, committed(o))
    @debug "order commit" s.cash_committed.value committed(o)
end

@doc """Commits a reduce order to an asset instance.

$(TYPEDSIGNATURES)

"""
function commit!(::Strategy, o::ReduceOrder, ii)
    @deassert committed(o) |> ltxzero || positionside(o) == Long
    add!(committed(ii, positionside(o)()), committed(o))
end

@doc """Decommits an increase order from a strategy.

$(TYPEDSIGNATURES)

"""
function decommit!(s::Strategy, o::IncreaseOrder, ii, canceled=false)
    @ifdebug _check_committment(o)
    # NOTE: ignore negative values caused by slippage
    @deassert canceled || isdust(ii, o) o
    # NOTE: committed can be negative in case the predicted commit is below the executed size
    subzero!(s.cash_committed, abs(committed(o)))
    @deassert gtxzero(ii, s.cash_committed, Val(:price)) s.cash_committed.value,
    s.cash.precision,
    o
    attr(o, :committed)[] = 0.0
end

# FIXME: order committment for reduce orders could also be negative IF the exchange
# does fee exclusive trading (rare, never seen) and the fee is paid in base currency (so and so).
# for long sells fee is usually paid in quote cur, for short buys it is possible
# it could be paid in base cur.
# Should we check the sign of `committed(o)` for long sells and short buys?

@doc """Decommits a sell order from an asset instance.

$(TYPEDSIGNATURES)

"""
function decommit!(s::Strategy, o::SellOrder, ii, args...)
    # NOTE: ignore negative values caused by slippage
    sub!(committed(ii, Long()), max(0.0, committed(o)))
    @deassert gtxzero(ii, committed(ii, Long()), Val(:amount))
    attr(o, :committed)[] = 0.0
end

@doc """Decommits a short buy order from an asset instance.

$(TYPEDSIGNATURES)

"""
function decommit!(s::Strategy, o::ShortBuyOrder, ii, args...)
    @deassert committed(o) |> ltxzero
    sub!(committed(ii, Short()), committed(o))
    attr(o, :committed)[] = 0.0
end
@doc """Checks if an increase order can be committed to a strategy.

$(TYPEDSIGNATURES)

"""
function iscommittable(s::Strategy, o::IncreaseOrder, ii)
    @deassert committed(o) > 0.0
    c = st.freecash(s)
    comm = committed(o)
    c >= comm || isapprox(c, comm)
end

@doc """Checks if a sell order can be committed to an asset instance.

$(TYPEDSIGNATURES)

"""
function iscommittable(::Strategy, o::SellOrder, ii)
    @deassert committed(o) > 0.0
    c = Instances.freecash(ii, Long())
    comm = committed(o)
    c >= comm || isapprox(c, comm)
end

@doc """Checks if a short buy order can be committed to an asset instance.

$(TYPEDSIGNATURES)

"""
function iscommittable(::Strategy, o::ShortBuyOrder, ii)
    @deassert committed(o) < 0.0
    c = Instances.freecash(ii, Short())
    comm = committed(o)
    c <= comm || isapprox(c, comm)
end

@doc """When an increase order is added to a strategy, the asset is added to the holdings.

$(TYPEDSIGNATURES)

"""
function hold!(s::Strategy, ii, o::IncreaseOrder)
    @deassert hasorders(s, ii, orderside(o)) || !iszero(ii) o
    push!(s.holdings, ii)
end

@doc """Reduce orders can never switch an asset from not held to held.

$(TYPEDSIGNATURES)

"""
hold!(::Strategy, _, ::ReduceOrder) = nothing

@doc """An asset is released when there are no orders for it and its balance is zero.

$(TYPEDSIGNATURES)

"""
function release!(s::Strategy, ii)
    if iszero(ii) && !hasorders(s, ii)
        delete!(s.holdings, ii)
    end
end

@doc """Cancels an order with given error.

$(TYPEDSIGNATURES)

"""
function cancel!(s::Strategy, o::Order, ii; err::OrderError)::Bool
    @debug "order cancel" o.id ii = raw(ii) err s.cash_committed.value committed(o)
    if isqueued(o, s, ii)
        decommit!(s, o, ii, true)
        @debug "order cancel" s.cash_committed.value
        delete!(s, ii, o)
        st.call!(s, o, err, ii)
    end
    true
end


@doc """Returns the amount of an order.

$(TYPEDSIGNATURES)

"""
amount(o::Order) = getfield(o, :amount)

@doc """Returns the trades of an order.

$(TYPEDSIGNATURES)

"""
trades(o::Order) = attr(o, :trades)

@doc """Returns the committed amount of a short buy order.

$(TYPEDSIGNATURES)

"""
function committed(o::ShortBuyOrder{<:AbstractInstrument,<:ExchangeID})
    @deassert attr(o, :committed)[] |> ltxzero o
    attr(o, :committed)[]
end

@doc """Returns the committed amount of an order.

$(TYPEDSIGNATURES)

"""
function committed(o::Order)
    @ifdebug _check_committment(o)
    attr(o, :committed)[]
end

@doc """Returns the cost of an order.

$(TYPEDSIGNATURES)

"""
cost(o::Order) = o.price * abs(o.amount)

@doc """Resets an order committment and unfilled amount.

$(TYPEDSIGNATURES)

"""
function reset!(o::Order, ii)
    empty!(trades(o))
    attr(o, :committed)[] = committment(ii, o)
    attr(o, :unfilled)[] = unfillment(o)
end

queue!(s::Strategy, o::Order, ii; skipcommit=false) = nothing

function _increase_order_comm(s::Strategy, ii::InstrumentInstance, oside::BySide)
    all_comm = sum((committed(o) for o in values(s, ii, oside)); init=0.0)
    s_comm = committed(s)
    all_comm, s_comm
end

function _check_committment(s::Strategy, ii::InstrumentInstance, ::BySide{Buy}, ::ByPos{Long})
    o_comm, ai_comm = _increase_order_comm(s, ii, Buy)
    abs(ai_comm) >= abs(o_comm)
end

function _check_committment(s::Strategy, ii::InstrumentInstance, ::BySide{Sell}, ::ByPos{Short})
    o_comm, s_comm = _increase_order_comm(s, ii, Sell)
    abs(s_comm) >= abs(o_comm)
end

function _reduce_order_comm(
    s::Strategy, ii::InstrumentInstance, oside::BySide, pside::ByPos=posside(ii)
)
    o_comm = sum((committed(o) for o in values(s, ii, oside) if ispos(pside, o)); init=0.0)
    s_comm = committed(ii, pside)
    o_comm, s_comm
end

function _check_committment(s::Strategy, ii::InstrumentInstance, ::BySide{Sell}, ::ByPos{Long})
    o_comm, ai_comm = _reduce_order_comm(s, ii, Sell, Long)
    isapprox(ii, abs(o_comm), abs(ai_comm), Val(:amount))
end

function _check_committment(s::Strategy, ii::InstrumentInstance, ::BySide{Buy}, ::ByPos{Short})
    o_comm, ai_comm = _reduce_order_comm(s, ii, Buy, Short)
    isapprox(ii, abs(o_comm), abs(ai_comm), Val(:amount))
end
