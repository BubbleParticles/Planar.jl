_lastupdate!(s, date) = s.attrs[:sim_last_orders_update] = date
_lastupdate(s) = s.attrs[:sim_last_orders_update]

@doc """Checks if the last update date is greater than or equal to the given date and throws an error if not.

$(TYPEDSIGNATURES)

If the last update date is greater than or equal to the given date, an error with the message "Tried to update orders multiple times on the same date." is thrown.

"""
function _check_update_date(s, date)
    if _lastupdate(s) >= date
        error("Tried to update orders multiple times on the same date: $date")
    end
    return nothing
end

using ..Executors.Instances.DataStructures: SAIterationState
using ..Simulations.Random: shuffle!

@doc """Pushes all orders from side_orders into all_orders.

$(TYPEDSIGNATURES)

This function pushes all orders from side_orders into all_orders. It collapses all assets into a single array, so what is shuffled is either orders of the same side.

"""
_dopush!(side_orders, all_orders) =
    for (ii, ords) in side_orders
        push!(all_orders, (ii, ords))
    end

@doc """Pushes orders from `ai_orders` into the simulation `s` at the specified `date`.

$(TYPEDSIGNATURES)

This function iterates over each order in `ai_orders` and checks if it is already queued in the simulation `s`.
If not, it calls the `order!` function to add the order to the simulation at the specified `date`.
"""
_docall!(s, ii, ai_orders, date) =
    for o in collect(ai_orders)
        isqueued(o, s, ii) || continue
        try
            order!(s, o, date, ii)
        catch e
            @error "Error processing order" order=o asset=ii date=date exception=(e, catch_backtrace())
        end
    end

@doc """Iterates over all pending orders checking for new fills.

$(TYPEDSIGNATURES)

This function iterates over each order in `all_orders` and calls `_docall!` to add the order to the simulation `s` at the specified `date`.

"""
_doall!(s, all_orders, date) =
    for (ii, ords) in all_orders
        _docall!(s, ii, ords, date)
    end

@doc """Iterates over all pending orders checking for new fills. 

$(TYPEDSIGNATURES)

If you don't have any callbacks attached to orders,
the outcome is the same as plain `UpdateOrders`. (It is ~10% slower than the basic function.)

The difference between this function and the base one dispatched over `UpdateOrders` is that
the sequence in which the pending orders are evaluated is shuffled. More precisely both buy orders and sell orders
for all assets are collapsed into a single array, therefore what is shuffled is either orders of the same side
_for different assets_, or the precedence between buy and sell _of the same assets_.
This means that if a particular asset has more than one pending buy(sell) order,
their evaluation will be always chained, for example if `A` and `B` are assets, a possible reordering would be:
```
A_buyorder1, A_buyorder2, B_buyorder1, B_buyorder2, A_sellorder1, B_sellorder2
```
Or
```
B_buyorder1, B_buyorder2, A_buyorder1, A_buyorder2 , A_sellorder1, B_sellorder2
```
Or
```
A_sellorder1, B_buyorder1, B_buyorder2, A_buyorder1, A_buyorder2 , B_sellorder2
```
This instead, will never occur:
```
B_buyorder1, A_buyorder1, B_buyorder2, A_buyorder1, A_buyorder2 , B_sellorder2
```
Because the buy orders for B would be detached. The reason why we don't have a finer grained shuffling mechanism
that allows this case is because it would be too slow, and the minimal increase in randomness is not worth it.

Note also that the sequence of evaluation for orders of the same side and asset is always fixed and sorted.
The sorting mirrors the sequence in which the orders would be triggered on the exchange, so for buy orders
the ones with higher price and earlier date are evaluated first, while for sell orders, the ones with a lower price
and still an earlier date. (Check the `lt` functions defined in the `Strategies` module.)
"""
function update!(s::Strategy{Sim}, date, ::UpdateOrdersShuffled)
    _check_update_date(s, date)
    positions!(s, date)
    let buys = orders(s, Buy), sells = orders(s, Sell)
        allorders = Tuple{eltype(s.holdings),Union{valtype(buys),valtype(sells)}}[]
        _dopush!(sells, allorders)
        _dopush!(buys, allorders)
        shuffle!(allorders)
        _doall!(s, allorders, date)
    end
    _lastupdate!(s, date)
end

@doc "Iterates over all pending orders checking for new fills.

$(TYPEDSIGNATURES)

Should be called only once, precisely at the beginning of the main `call!` function.
Orders are evaluated sequentially, first sell orders than buy orders.

For a randomized evaluation sequence use `UpdateOrdersShuffled` by setting
the value `:sim_update_mode` in the strategy config:
```julia
s.attrs[:sim_update_mode] = UpdateOrdersShuffled()
```
"
function update!(s::Strategy{Sim}, date, ::UpdateOrders)
    _check_update_date(s, date)
    positions!(s, date)
    for (ii, ords) in s.sellorders
        @ifdebug prev_sell_price = DFT(0.0)
        for (pt, o) in collect(ords) # Prefetch the orders since `order!` can unqueue
            @ifdebug @deassert prev_sell_price <= pt.price
            # Need to check again if it is queued in case of liquidation events
            isqueued(o, s, ii) || continue
            try
                order!(s, o, date, ii)
            catch e
                @error "Error processing sell order" order=o asset=ii date=date exception=(e, catch_backtrace())
            end
            @ifdebug prev_sell_price = pt.price
        end
    end
    for (ii, ords) in s.buyorders
        @ifdebug prev_buy_price = DFT(Inf)
        for (pt, o) in collect(ords) # Prefetch the orders since `order!` can unqueue
            @ifdebug @deassert prev_buy_price >= pt.price
            # Need to check again if it is queued in case of liquidation events
            isqueued(o, s, ii) || continue
            try
                order!(s, o, date, ii)
            catch e
                @error "Error processing buy order" order=o asset=ii date=date exception=(e, catch_backtrace())
            end
            @ifdebug prev_buy_price = pt.price
        end
    end
    _lastupdate!(s, date)
end

@doc "Action to update orders on a tick-by-tick basis (SimMode tick backtesting)."
struct UpdateOrdersTick <: ExecAction end
export UpdateOrdersTick

@doc """Iterates over all pending orders checking for new fills against a market tick.

$(TYPEDSIGNATURES)

Called once per tick in tick-mode backtesting. Only the asset of the current tick is
checked — that asset's tick price is the only price that can have moved. No
`_check_update_date` (same-millisecond ticks are valid), no `positions!` (Sim has no
price-based liquidation: `isliquidatable` is `Paper`/`Live` only), no `_lastupdate!`.
"""
function update!(s::Strategy{Sim}, tick::TradeTick, ::UpdateOrdersTick)
    ii = tick.asset
    for ords in (get(s.sellorders, ii, nothing), get(s.buyorders, ii, nothing))
        isnothing(ords) && continue
        for (_, o) in collect(ords) # Prefetch the orders since a fill can unqueue
            isqueued(o, s, ii) || continue
            try
                _maybe_fill_tick!(s, o, ii, tick)
            catch e
                @error "Error processing order" order=o asset=ii date=tick.timestamp exception=(e, catch_backtrace())
            end
        end
    end
    nothing
end

@doc """Fills an order at the current tick price if it is crossed.

$(TYPEDSIGNATURES)

Buy limits fill when `tick.price <= o.price`, sell limits when `tick.price >= o.price`.
A non-triggered FOK/IOC order is canceled (mirrors `limitorder_ifprice!`); other orders
stay queued. Triggered orders fill at the exact tick price with `slippage=false` and
`actual_amount=unfilled(o)`, so limit orders can fill partially across successive ticks.
"""
function _maybe_fill_tick!(s::Strategy{Sim}, o::AnyLimitOrder, ii, tick::TradeTick)
    triggered =
        o isa AnyLimitOrder{Buy} ? tick.price <= o.price : tick.price >= o.price
    if !triggered
        if o isa Union{AnyFOKOrder,AnyIOCOrder}
            cancel!(s, o, ii; err=NotMatched(o.price, tick.price, DFT(0.0), DFT(0.0)))
        end
        return nothing
    end
    trade!(
        s, o, ii; date=tick.timestamp, price=tick.price, actual_amount=unfilled(o), slippage=false
    )
end