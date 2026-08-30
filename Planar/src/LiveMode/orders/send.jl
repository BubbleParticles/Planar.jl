using .Executors.Instruments: freecash
using .Executors: @price!, @amount!
using .Data: default_value

@doc "Represents a trigger order with fields for the order type, price, and trigger condition."
const TriggerOrderTuple = NamedTuple{(:type, :price, :trigger)}

@doc """ Converts a trigger order to a dictionary compatible with ccxt.

$(TYPEDSIGNATURES)

The function transforms the order type, price, and trigger price into a Python dictionary.
This dictionary is compatible with the ccxt cryptocurrency trading library.
"""
function trigger_dict(exc, v)
    out = Dict{String,Any}()
    out["type"] = _ccxtordertype(exc, v.type)
    out["price"] = v.price
    out["triggerPrice"] = v.trigger
    out
end

@doc """ Checks if there is enough free cash to execute an increase order.

$(TYPEDSIGNATURES)

The function compares the absolute value of free cash in the strategy to the absolute value of the required cash for the order, which is the product of the amount and price.
"""
function check_available_cash(s, ii, amount, price, o::Type{<:IncreaseOrder})
    lev = abs(leverage(ii, posside(o)))
    required = if iszero(lev) 0.0 else abs(amount) * price / lev end
    @debug "check avl cash: inc" _module = LogState freecash(s) amount lev required
    abs(freecash(s)) >= required
end

@doc """ Checks if there is enough free cash to execute a reduce order.

$(TYPEDSIGNATURES)

The function compares the absolute value of free cash in the asset instance to the absolute value of the required cash for the order, which is the amount.
"""
function check_available_cash(_, ii, amount, _, o::Type{<:ReduceOrder})
    abs(freecash(ii, posside(o))) >= abs(amount)
end

@doc """ Ensure margin mode on exchange matches asset margin mode.


"""
function ensure_marginmode(s::LiveStrategy, ii::MarginInstance)
    exc = exchange(ii)
    mm = marginmode(ii)
    last_mm = get(ii, :live_margin_mode, missing)
    if ismissing(last_mm) || last_mm != mm
        @debug "margin mode: updating" mm last_mm exc = nameof(exc)
        hedged = ishedged(ii)
        # `mm` is an instance (e.g. IsolatedMargin{NotHedged}()); pass its string
        # form ("isolated"/"cross") so `marginmode!` accepts it. Using
        # `Symbol(string(typeof(mm)))` produced "IsolatedMargin{NotHedged}" and made
        # `marginmode!` throw "Invalid margin mode ...".
        remote_mode = _ccxtmarginmode(ii)
        return if marginmode!(exc, remote_mode, raw(ii); hedged)
            ii[:live_margin_mode] = mm
            event!(exc, MarginUpdated(Symbol(:margin_mode_set_, remote_mode), s, position(ii, Long)))
            event!(
                exc, MarginUpdated(Symbol(:margin_mode_set_, remote_mode), s, position(ii, Short))
            )
            true
        else
            false
        end
    end
    true
end

function ensure_marginmode(s::LiveStrategy, ii)
    true
end

function pygetorconvert!(params, k, v)
    this_v = get(params, k, nothing)
    if isnothing(this_v)
        params[k] = if v isa Type
            default_value(v)
        else
            v
        end
    end
end

# TODO: split into multiple functions according to order type
@doc """ Sends a live order and performs checks for sufficient cash and order features.

$(TYPEDSIGNATURES)

This function initiates a live order in the specified strategy and asset instance.
It first checks available cash and whether certain order features are supported.
It then sends the order to the exchange, retries if exceptions occur, and handles the response.
"""
function live_send_order(
    s::LiveStrategy,
    ii::InstrumentInstance,
    t::Type{<:Order}=GTCOrder{Buy},
    args...;
    skipchecks=false,
    amount,
    price=lastprice(s, ii, t),
    post_only=false,
    reduce_only=false,
    stop_price=nothing,
    profit_price=nothing,
    stop_loss::Option{TriggerOrderTuple}=nothing,
    take_profit::Option{TriggerOrderTuple}=nothing,
    trigger_price=nothing,
    trigger_direction=nothing,
    trailing_percent=nothing, # 1.0 == 1/100
    trailing_amount=nothing, # in quote currency
    trailing_trigger_price=nothing, # `price` is used if not set
    trailing_trigger_amount=nothing, # fallback to price if set
    kwargs...,
)
    # sanitize amount (since asset cash can be negative and could be used as input)
    amount = abs(amount)
    if !isnothing(trailing_amount)
        trailing_amount = abs(trailing_amount)
    end
    # NOTE: this should not be needed, but some exchanges can be buggy
    # might be used in a specialized function for problematic exchanges
    # @price! ii stop_loss stop_price price profit_price take_profit
    # @amount! ii amount
    if !skipchecks
        if !check_available_cash(s, ii, amount, price, t)
            @warn "send order: not enough cash" this_cash = cash(ii, posside(t)) ai_comm = committed(
                ii, posside(t)
            ) ai_free = freecash(ii, posside(t)) strat_cash = cash(s) strat_comm = committed(
                s
            ) order_cash = amount t lev = leverage(ii, posside(t))
            return nothing
        end
        if !ensure_marginmode(s, ii)
            @warn "send order: margin mode mismatch" this_mm = marginmode(ii) exc = nameof(
                exchange(ii)
            ) reduce_only
            if !reduce_only
                return nothing
            end
        end
    end
    sym = raw(ii)
    exc = exchange(ii)
    side = _ccxtorderside(t)
    type = _ccxtordertype(exc, t)
    params = Dict{String,Any}(string(k) => v for (k, v) in kwargs)
    tif = _ccxttif(exc, t)
    if !isempty(tif)
        tif_k = string(time_in_force_key(exc))
        tif_v = string(time_in_force_value(exc, asset(ii), tif))
        pygetorconvert!(params, tif_k, tif_v)
    end
    function supportmsg(feat)
        @warn "send order: not supported" feat exc = nameof(exc)
    end

    postOnly = "postOnly"
    reduceOnly = "reduceOnly"
    stopLoss = "stopLoss"
    stopLossPrice = "stopLossPrice"
    takeProfitPrice = "takeProfitPrice"
    triggerPrice = "triggerPrice"
    triggerDirection = "triggerDirection"

    if has(exc, :createPostOnlyOrder)
        pygetorconvert!(params, postOnly, post_only)
    elseif get(params, postOnly, false) == true
        supportmsg("post only")
        delete!(params, postOnly)
    end
    if s isa MarginStrategy
        if has(exc, :createReduceOnlyOrder)
            pygetorconvert!(params, reduceOnly, reduce_only)
        elseif get(params, reduceOnly, false) == true
            supportmsg("reduce only")
            delete!(params, reduceOnly)
        end
        # Hedge mode: ccxt requires `positionSide` to target the correct side.
        # Without it, closing a Long sends a sell that the exchange treats as
        # opening a Short (one-way semantics). Set it for every hedged order so
        # both increase and reduce hit the intended position side.
        if ishedged(ii)
            pygetorconvert!(params, "positionSide", _ccxtposside(posside(t)))
        end
    end
    if !isnothing(trigger_price)
        if has(exc, :createTriggerOrder)
            pygetorconvert!(params, triggerPrice, trigger_price)
            pygetorconvert!(
                params,
                triggerDirection,
                @something(
                    trigger_direction, ifelse(
                        # NOTE: strict equality
                        orderside(t) === Buy,
                        "below",
                        "above",
                    )
                )
            )
        elseif haskey(params, triggerPrice)
            supportmsg("trigger order")
            delete!(params, triggerPrice)
            delete!(params, triggerDirection)
        end
    end
    if !isnothing(stop_price)
        if has(exc, :createStopLossOrder)
            pygetorconvert!(params, stopLossPrice, stop_price)
        elseif haskey(params, stopLossPrice)
            supportmsg("stop loss order (close position)")
            delete!(params, stopLossPrice)
        end
    end
    if !isnothing(profit_price)
        if has(exc, :createTakeProfitOrder)
            pygetorconvert!(params, takeProfitPrice, profit_price)
        elseif haskey(params, takeProfitPrice)
            supportmsg("take profit order (close position)")
            delete!(params, takeProfitPrice)
        end
    end
    if !isnothing(stop_loss) && !isnothing(take_profit)
        if has(exc, :createOrderWithTakeProfitAndStopLoss)
            pygetorconvert!(params, stopLoss, stop_loss)
            pygetorconvert!(params, takeProfit, take_profit)
        elseif haskey(params, stopLoss) || haskey(params, takeProfit)
            supportmsg("conditional trigger order")
            delete!(params, stopLoss)
            delete!(params, takeProfit)
        end
    elseif !isnothing(stop_loss) || !isnothing(take_profit)
        @warn "send order: conditional trigger needs both stop_loss and take_profit input parameters"
    end
    trailing = if !isnothing(trailing_percent)
        if has(exc, :createTrailingPercentOrder)
            pygetorconvert!(params, "trailingPercent", trailing_percent)
        else
            supportmsg("trailing percent order")
        end
    elseif !isnothing(trailing_amount)
        if has(exc, :createTrailingAmountOrder)
            pygetorconvert!(params, "trailingAmount", trailing_amount)
        else
            supportmsg("trailing amount order")
        end
    end
    if !isnothing(trailing)
        if !isnothing(trailing_trigger_price)
            pygetorconvert!(params, "trailingTriggerPrice", trailing_trigger_price)
        elseif !isnothing(trailing_trigger_amount)
            if !(price isa Number)
                @warn "send order: trailing amount order needs price input parameter" price
                price = lastprice(ii)
            end
            pygetorconvert!(params, "trailingTriggerPrice", price)
        end
    end
    # start monitoring before sending the create request
    watch_orders!(s, ii)
    watch_trades!(s, ii)
    @debug "send order: create" _module = LogSendOrder sym type price amount side params args
    inc_pending_orders!(ii)
    resp = nothing
    try
        resp = create_order(s, sym, args...; side, type, price, amount, params)
    finally
        # Trace response for debugging stub mismatches
        if !(isnothing(resp) || resp isa Exception)
            @start_task IdDict() try
                try
                    @debug "send order: response raw" _module = LogSendOrder resp
                    resp_id = try resp_order_id(resp, exchangeid(ii)) catch e; e isa InterruptException && rethrow(e); nothing end
                    resp_price = try resp_order_price(resp, exchangeid(ii)) catch e; e isa InterruptException && rethrow(e); nothing end
                    resp_cost = try resp_order_cost(resp, exchangeid(ii)) catch e; e isa InterruptException && rethrow(e); nothing end
                    resp_filled = try resp_order_filled(resp, exchangeid(ii)) catch e; e isa InterruptException && rethrow(e); nothing end
                    resp_avg = try resp_order_average(resp, exchangeid(ii)) catch e; e isa InterruptException && rethrow(e); nothing end
                    resp_remaining = try resp_order_remaining(resp, exchangeid(ii)) catch e; e isa InterruptException && rethrow(e); nothing end
                    resp_status = try resp_order_status(resp, exchangeid(ii)) catch e; e isa InterruptException && rethrow(e); nothing end
                    @debug "send order: response trace" _module = LogSendOrder req_price = price req_amount = amount resp_id resp_price resp_cost resp_filled resp_avg resp_remaining resp_status
                catch err
                    err isa InterruptException && rethrow(err)
                    @warn "send order: response trace failed" err = err
                end
            catch e
                e isa InterruptException && rethrow(e)
                @error "send order: response trace task failed" exception = (e, catch_backtrace())
            end
        end
    end
    return if isnothing(resp) || resp isa Exception
        @warn "send order: failed" sym ii exception = resp args params
        dec_pending_orders!(ii)
        resp
    elseif isnothing(resp_order_id(resp, exchangeid(ii)))
        dec_pending_orders!(ii)
        nothing
    else
        resp
    end
end
