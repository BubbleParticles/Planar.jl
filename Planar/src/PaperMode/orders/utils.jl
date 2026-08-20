using PlanarCore.SimMode: create_sim_market_order, marketorder!, AnyFOKOrder, AnyIOCOrder
using PlanarCore.Fetch: orderbook
using .Instances.Exchanges: ticker!
using PlanarCore.OrderTypes: ordertype, positionside, NotEnoughLiquidity, isimmediate
using .Executors: isfilled
using .Executors.TimeTicks: now

@doc "A buy limit order is triggered when the price is lower than the limit."
_istriggered(o::AnyLimitOrder{Buy}, price) = price <= o.price
@doc "A sell limit order is triggered when the price is higher than the limit."
_istriggered(o::AnyLimitOrder{Sell}, price) = price >= o.price
@doc "Market orders are always triggered."
_istriggered(::AnyMarketOrder, args...) = true

@doc "Use the base currency volume from the ticker."
function _basevol(ii)
    tkr = ticker!(ii.asset.raw, ii.exchange)
    # Debug - log what we got
    @debug "ticker result" tkr_type=typeof(tkr) tkr_keys=isa(tkr, AbstractDict) ? keys(tkr) : "not-a-dict"
    # Convert to AbstractDict if needed
    if !isa(tkr, AbstractDict)
        try
            tkr = Dict{String, Any}(tkr)
        catch e
            e isa InterruptException && rethrow(e)
            @error "ticker not convertible to dict" typeof=typeof(tkr) exception = (e, catch_backtrace())
            return one(DFT)
        end
    end
    # Get volume - handle both Python None and Julia nothing
    vol = get(tkr, "baseVolume", missing)
    @debug "baseVolume" vol=vol typeof=typeof(vol)
    if ismissing(vol) || vol === nothing
        return one(DFT)
    end
    # Convert to number if it's a string or other type
    try
        if vol isa AbstractString
            return DFT(parse(Float64, vol))
        end
        DFT(vol)
    catch e
        e isa InterruptException && rethrow(e)
        @error "basevol conversion error" exception = (e, catch_backtrace())
        return one(DFT)
    end
end
function _ticker_volume(ii)
    (Ref(apply(tf"1d", now())), Ref(zero(DFT)), Ref(_basevol(ii)))
end

_paper_liquidity(s, ii) = @lget! s[:paper_liquidity] ii _ticker_volume(ii)
@doc """ Limits the volume of order execution to the daily limit of the asset.

$(TYPEDSIGNATURES)

The function checks the liquidity and updates the daily volume, total volume, and taken volume accordingly.
It fails the market order if the daily volume for the current pair is exceeded.
The function uses the `@lget!` macro to get the values of `day_vol`, `taken_vol`, and `total_vol` from the `:paper_liquidity` attribute of the simulation `s`.
The function also uses the `_basevol` and `_ticker_volume` functions to get the base volume and ticker volume respectively.

"""
function volumecap!(s, ii; amount)
    # Validate amount > 0
    amount <= zero(DFT) && return false
    # Check there is enough liquidity
    day_vol, taken_vol, total_vol = _paper_liquidity(s, ii)
    let this_day = apply(tf"1d", now())
        if this_day > day_vol[]
            day_vol[] = this_day
            total_vol[] = _basevol(ii)
            taken_vol[] = 0.0
        end
    end
    # Atomically reserve the amount if within daily volume limit
    # Use a compare-and-swap-like pattern for thread safety
    while true
        current_taken = taken_vol[]
        new_taken = current_taken + amount
        if new_taken > total_vol[]
            return false
        end
        # Use == for Float64 value comparison (=== compares bit patterns, problematic for FP)
        if taken_vol[] == current_taken
            # No other task modified it, try to update
            taken_vol[] = new_taken
            return true
        end
        # Another task modified it, retry
        yield()
    end
end

@doc """ Release a previously reserved volume capacity."""
function volrelease!(s, ii; amount)
    # Validate amount > 0
    amount <= zero(DFT) && return false
    day_vol, taken_vol, total_vol = _paper_liquidity(s, ii)
    while true
        current_taken = taken_vol[]
        new_taken = max(DFT(0), current_taken - amount)
        if taken_vol[] == current_taken
            taken_vol[] = new_taken
            return true
        end
        yield()
    end
end

function orderbook_side(ii, t::Type{<:Order})
    ob = orderbook(ii.exchange, raw(ii); limit=100)
    side = ifelse(t <: AnyBuyOrder, :asks, :bids)
    @debug "papermode: obside" t side
    getproperty(ob, side)
end

@doc """ Simulates price and volume for an order from the live orderbook.

$(TYPEDSIGNATURES)

The function fetches the orderbook for the given asset and exchange.
It then calculates the volume-weighted average price (VWAP) based on how much of the orderbook the order sweeps.
If the order is a limit order and the average price exceeds the limit order price, the function terminates.
If the order is a Fill or Kill (FOK) order and the volume is less than the order amount, the function cancels the order.
The function updates the taken volume after each order.

"""
function from_orderbook(obside, s, ii, o::Order; amount, date)
    _, taken_vol, total_vol = _paper_liquidity(s, ii)
    n_prices = length(obside)
    # Gracefully handle empty orderbook
    if n_prices <= 0
        @debug "paper from ob: empty orderbook"
        volrelease!(s, ii; amount=amount)
        return zero(DFT), zero(DFT), nothing
    end
    price_idx = max(1, trunc(Int, taken_vol[] * n_prices / total_vol[]))
    this_price, this_vol = obside[price_idx]
    @debug "paper from ob: idx" price_idx this_price this_vol
    this_vol = min(amount, this_vol)
    islimit = o isa AnyLimitOrder
    if islimit && !_istriggered(o, this_price)
        @debug "paper from ob: limit order not triggered" this_price o
        volrelease!(s, ii; amount=amount)
        return zero(DFT), zero(DFT), nothing
    end
    # calculate the vwap based on how much orderbook we sweep
    avg_price = this_price * this_vol
    while this_vol < amount
        price_idx += 1
        if price_idx > n_prices
            @debug "paper from ob: out of depth (!)" this_vol amount avg_price
            break
        end
        ob_price, ob_vol = obside[price_idx]
        # If it is a limit order terminate the loop as soon as avg_price
        # exceeds the limit order avg_price
        if islimit && !_istriggered(o, ob_price)
            @debug "paper from ob: limit order partially filled" o.price this_price amount this_vol avg_price
            volrelease!(s, ii; amount=amount - this_vol)
            break
        end
        inc_vol = min(ob_vol, amount - this_vol)
        avg_price += ob_price * inc_vol
        this_vol += inc_vol
    end
    # Gracefully handle zero volume edge case
    if this_vol <= zero(DFT)
        @debug "paper from ob: zero volume"
        volrelease!(s, ii; amount=amount)
        return zero(DFT), zero(DFT), nothing
    end
    avg_price /= this_vol
    ob_trade::Union{Nothing,<:Trade} = nothing
    if o isa AnyFOKOrder && this_vol < amount
        @debug "paper from ob: fok order no volume" o.price this_price amount this_vol
        cancel!(s, o, ii; err=NotEnoughLiquidity())
        # Release the reserved volume since FOK order failed
        volrelease!(s, ii; amount=amount)
        return avg_price, zero(DFT), nothing
    end
    prev_cash = s.cash.value
    ob_trade = trade!(
        s, o, ii; date, price=avg_price, actual_amount=this_vol, slippage=false
    )
    @debug "paper from ob:" s.cash.value - avg_price prev_cash this_vol ob_trade.value
    if isnothing(ob_trade)
        @debug "paper from ob: trade failed" o.price this_price amount this_vol
        cancel!(s, o, ii; err=OrderFailed((; o, obside)))
        # Release the reserved volume since trade failed
        volrelease!(s, ii; amount=amount)
    end
    # Gracefully handle edge case instead of asserting
    if !(o.amount ≈ this_vol) &&
       !(o isa AnyLimitOrder) &&
       !(sum(entry[2] for entry in obside) < o.amount)
        @warn "paper from ob: volume mismatch" o.amount this_vol
    end
    # Volume already reserved by volumecap!, don't double-count
    @debug "paper from ob: done" avg_price this_vol taken_vol[]
    return avg_price, this_vol, ob_trade
end