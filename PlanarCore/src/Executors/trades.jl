@doc """Performs cleanups after a trade (attempt).

$(TYPEDSIGNATURES)

"""
aftertrade!(s, ii, o, t=nothing) =  nothing

with_slippage(args...; kwargs...) = nothing

maketrade(args...; kwargs...) = nothing

@doc """ Unconditionally dequeues immediate orders.

$(TYPEDSIGNATURES)

This function is called after a trade to remove filled 'Fill Or Kill' (FOK) or 'Immediate Or Cancel' (IOC) orders from the strategy's order queue.
"""
function aftertrade!(s::Strategy, ii, o::Union{AnyFOKOrder,AnyIOCOrder,AnyMarketOrder}, t=nothing)
    if t isa Trade
        position!(s, ii, t)
    end
    decommit!(s, o, ii, true)
    delete!(s, ii, o)
    isfilled(ii, o) || st.call!(s, o, NotEnoughCash(_cashfrom(s, ii, o)), ii)
end

@doc """ Removes a filled limit order from the queue

$(TYPEDSIGNATURES)

The function is used post-trade to clean up the strategy's order queue.
"""
aftertrade!(s::Strategy, ii, o::Order, t=nothing) = begin
    if t isa Trade
        position!(s, ii, t)
    end
    if isfilled(ii, o)
        decommit!(s, o, ii)
        delete!(s, ii, o)
    end
end


@doc """ Executes a trade with the given parameters and updates the strategy state.

$(TYPEDSIGNATURES)

This function executes a trade based on the given order and asset instance. It calculates the actual price, creates a trade using the `maketrade` function, and updates the strategy and asset instance. If the trade cannot be executed (e.g., not enough cash), the function updates the state as if the order was filled without creating a trade. The function returns the created trade or nothing if the trade could not be executed.

"""
function trade!(
    s::Strategy,
    o,
    ii;
    date,
    price,
    actual_amount,
    fees=maxfees(ii),
    slippage=true,
    kwargs...,
)
    @deassert abs(committed(o)) > 0.0
    @ifdebug s.debug_afterorder()
    if !isnothing(actual_amount)
        if o isa ReduceOnlyOrder
            actual_amount = min(actual_amount, ii.limits.amount.max)
        else
            @amount! ii actual_amount
        end
    end
    actual_price = slippage ? with_slippage(s, o, ii; date, price, actual_amount) : price
    @price! ii actual_price
    trade = maketrade(s, o, ii; date, actual_price, actual_amount, fees, kwargs...)
    isnothing(trade) && begin
        # unqueue or decommit order if filled
        aftertrade!(s, ii, o)
        return nothing
    end
    _update_from_trade!(s, ii, o, trade; actual_price)
end

function _update_from_trade!(s::Strategy, ii, o, trade; actual_price)
    @ifdebug s.debug_beforetrade(s, ii, o, trade, actual_price)
    # record trade
    @deassert !isdust(ii, o) committed(o), o
    # Fills the order
    fill!(s, ii, o, trade)
    push!(trades(ii), trade)
    push!(trades(o), trade)
    # update asset cash and strategy cash
    cash!(s, ii, trade)
    # unqueue or decommit order if filled
    # and update position state
    aftertrade!(s, ii, o, trade)
    call!(s, ii, trade, NewTrade())
    @ifdebug s.debug_aftertrade(s, ii, o)
    @ifdebug s.debug_check_committments(s, ii)
    @ifdebug s.debug_check_committments(s, ii, trade)
    return trade
end
