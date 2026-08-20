using .Misc.Lang: @lget!, @deassert, Option
using .Executors:
    AnyGTCOrder, AnyMarketOrder, AnyLimitOrder, AnyIOCOrder, AnyFOKOrder, AnyPostOnlyOrder
using LRUCache

@doc "Represents the state of a live order comprising order details, a lock, trade hashes, an update hash, and average price."
const LiveOrderState = NamedTuple{
    (:order, :lock, :trade_hashes, :update_hash, :average_price),
    Tuple{Order,SafeLock,Vector{UInt64},Ref{UInt64},Ref{DFT}},
}

@doc "A dictionary mapping asset strings to their corresponding live order states."
const InstrumentOrdersDict = LittleDict{String,LiveOrderState}

function Base.lock(state::LiveOrderState)
    lock(state.lock)
end

function Base.lock(func::Function, state::LiveOrderState)
    lock(func, state.lock)
end

function Base.unlock(state::LiveOrderState)
    unlock(state.lock)
end

function active_orders(ii)
    @something get(ii, :live_active_orders, nothing) @inlock ii @lget! ii :live_active_orders InstrumentOrdersDict()
end

@doc """ Computes the average price of an order.

$(TYPEDSIGNATURES)

It calculates the average price by summing the value and amount of each trade in the order,
and then dividing the total value by the total amount.
If no trades exist, it returns the original order price.

"""
avgprice(o::Order) =
    let order_trades = trades(o)
        isempty(order_trades) && return o.price
        val = zero(DFT)
        amt = zero(DFT)
        for t in order_trades
            val += t.value
            amt += t.amount
        end
        iszero(amt) && return o.price
        return val / amt
    end

@doc "Stores and order id in the recently orders cache."
record_order!(s::LiveStrategy, ii, id::String) =
    let lro = recent_orders(s, ii)
        lro[id] = nothing
    end
@doc "Stores and order in the recently orders cache."
record_order!(s::LiveStrategy, ii, o::Order) = record_order!(s, ii, o.id)
@doc "Tests if an order id has been recently processed."
isprocessed_order(s::LiveStrategy, ii, id::String) = id ∈ keys(recent_orders(s, ii))
@doc "Tests if an order has been recently processed."
isprocessed_order(s::LiveStrategy, ii, o::Order) = isprocessed_order(o.id)

pending_orders(ii::InstrumentInstance) = @lget! ii :pending_orders 0
inc_pending_orders!(ii::InstrumentInstance) = ii[:pending_orders] = pending_orders(ii) + 1
dec_pending_orders!(ii::InstrumentInstance) = ii[:pending_orders] = pending_orders(ii) - 1
pending_trades(ii::InstrumentInstance) = @lget! ii :pending_trades 0
inc_pending_trades!(ii::InstrumentInstance) = ii[:pending_trades] = pending_trades(ii) + 1
dec_pending_trades!(ii::InstrumentInstance) = ii[:pending_trades] = pending_trades(ii) - 1

@doc """ Registers an active order in a live strategy.

$(TYPEDSIGNATURES)

This function sets an order as active for a given asset in a live strategy.
The order's state includes a lock, trade hashes, an update hash, and the average price.
The function ensures that the trade and orders watchers are running for the asset.

"""
function set_active_order!(s::LiveStrategy, ii, o; ap=avgprice(o))
    @debug "orders: set active" _module = LogWatchOrder o.id islocked(s) f = @caller
    state = @lget! active_orders(ii) o.id (;
        order=o,
        lock=SafeLock(),
        trade_hashes=UInt64[],
        update_hash=Ref{UInt64}(0),
        average_price=Ref(iszero(ap) ? avgprice(o) : ap)
    )
    watch_trades!(s, ii) # ensure trade watcher is running
    watch_orders!(s, ii) # ensure orders watcher is running
    @debug "orders: state" _module = LogWatchOrder ii o.id
    state
end

@doc "Remove order from the set of active orders."
function clear_order!(s::LiveStrategy, ii, o::Order)
    actord = active_orders(ii)
    @debug "orders: disactivating" _module = LogSyncOrder o.id
    delete!(actord, o.id)
    decommit!(s, o, ii)
    delete!(s, ii, o)
    record_order!(s, ii, o)
end

@doc """ Displays the active orders.

$(TYPEDSIGNATURES)

This function prints the active orders for a given asset in a live strategy.
Each order's id is printed along with its open status.

"""
function show_active_orders(s::LiveStrategy, ii)
    open_orders = fetch_open_orders(s, ii)
    open_ids = Set(resp_order_id.(open_orders))
    actord = active_orders(ii)
    for id in keys(actord)
        println(stdout, string(id, " open: ", id ∈ open_ids))
    end
    flush(stdout)
end

@doc """ Checks if an order is filled and performs actions if it is.

$(TYPEDSIGNATURES)

This macro checks if an order is filled.
If the order is filled, it decommits the order and deletes it from the active orders for a specified asset in a live strategy.

"""
macro _isfilled()
    expr = quote
        # fallback to local
        if isfilled(o)
            decommit!(s, o, ii)
            delete!(s, ii, o)
        end
    end
    esc(expr)
end

@doc """ Waits for all active orders to close.

$(TYPEDSIGNATURES)

This function waits until all active orders for a given asset in a live strategy are closed or until a specified timeout is reached.
If the orders are not closed by the time the timeout is reached, it attempts to sync the open orders.
If orders remain open after the sync attempt, it signals an error.

"""
function waitordclose(
    s::LiveStrategy, ii, waitfor=Second(5); t::Type{<:OrderSide}=BuyOrSell, synced=true
)::Bool
    try
        actord = active_orders(ii)
        slept = 0
        timeout = Millisecond(waitfor).value
        success = true
        @debug "wait ord close: waiting" _module = LogWaitOrder ii side = t
        while true
            if !isactive(s, ii; actord, side=t)
                @debug "wait ord close: done" _module = LogWaitOrder ii
                break
            elseif slept >= timeout
                success = false
                @debug "wait ord close: timedout" _module = LogWaitOrder ii side = t waitfor f = @caller
                if synced
                    @warn "wait ord close: syncing open orders!" ii side = t f = @caller
                    live_sync_open_orders!(s, ii; side=t, overwrite=false, exec=true)
                    success = if isactive(s, ii; side=t)
                        @error "wait ord close: orders still active" ii side = t n = orderscount(
                            s, ii, t
                        ) length(active_orders(ii)) isactive(s, ii; side=t)
                        false
                    else
                        true
                    end
                end
                break
            end
            sleep(0.1)
            slept += 100
        end
        if success
            if orderscount(s, ii, t) > 0
                @debug "wait ord close: syncing open orders! (2nd)" _module = LogWaitOrder ii orderscount(
                    s, ii, t
                ) f = @caller
                live_sync_open_orders!(s, ii; side=t, overwrite=false, exec=true)
                iszero(orderscount(s, ii, t))
            else
                true
            end
        else
            false
        end
    catch e
        e isa InterruptException && rethrow(e)
        @error "waitordclose: exception" exception = (e, catch_backtrace()) _module = LogWaitOrder
        false
    end
end

@doc """ Checks if there are active orders for a specific side.

$(TYPEDSIGNATURES)

This function determines if there are active orders for a specific side (Buy/Sell/BuyOrSell)
for a given asset in a live strategy.

"""
function isactive(s::LiveStrategy, ii; actord=active_orders(ii), side=BuyOrSell)
    for state in values(actord)
        orderside(state.order) == side && return true
    end
    return false
end

@doc """ Checks if a specific order is active.

$(TYPEDSIGNATURES)

This function determines if a specific limit order is active for a given asset in a live strategy.
"""
function isactive(
    s::LiveStrategy, ii, o::AnyLimitOrder; pt=pricetime(o), actord=active_orders(ii)
)
    haskey(s, ii, pt, o) && haskey(actord, o.id)
end

@doc """ Checks if a specific order is active.

$(TYPEDSIGNATURES)

This function determines if a specific order is active for a given asset in a live strategy.
"""
function isactive(s::LiveStrategy, ii, o; actord=active_orders(ii), kwargs...)
    haskey(actord, o.id)
end
