using .OrderTypes
using .Misc: IsolatedMargin, CrossMargin, NoMargin, IsolatedHedged, CrossHedged, DFT, ZERO
const ot = OrderTypes

_execfunc(f, args...; kwargs...) = f(args...; kwargs...)
_execfunc_timeout(f, args...; timeout, kwargs...) = f(args...; kwargs...)
_execfunc(f::Function, args...; kwargs...) = f(args...; kwargs...)

get_str(v, k) = something(get(v, string(k), nothing), "") |> string
get_float(v, k) = _get_float_or(v, string(k), 0.0)
get_bool(v, k) = something(get(v, string(k), false), false) === true

# Returns the numeric value if key exists and is a number, otherwise `def`.
# Correctly handles JSON `null` and missing keys (AGENTS.md Gotcha #8/#12):
# a `null`/absent value yields `def` rather than a hardcoded `0.0`.
function _get_float_or(v, k, def)
    val = get(v, k, nothing)
    val isa Number ? Float64(val) : def
end


function _option_float(o, k; nonzero=false)
    val = get(o, string(k), nothing)
    if isnothing(val)
        return nothing
    end
    if val isa AbstractString
        isempty(val) && return nothing
        f = tryparse(Float64, val)
        isnothing(f) && return nothing
        return nonzero && iszero(f) ? nothing : f
    end
    if val isa Number
        f = Float64(val)
        return nonzero && iszero(f) ? nothing : f
    end
    return nothing
end

function get_float(resp, k, def, args...; ii)
    _get_float_or(resp, string(k), def)
end

get_timestamp(py, keys=("lastUpdateTimestamp", "timestamp")) =
    for k in keys
        v = get(py, string(k), nothing)
        v !== nothing && return v
    end

_tryasdate(v) = tryparse(DateTime, rstrip(string(v), 'Z'))
pytodate(py) = pytodate(py, "lastUpdateTimestamp", "timestamp")
function pytodate(py, keys...)
    for k in keys
        v = get(py, string(k), nothing)
        v === nothing && continue
        parsed = if v isa AbstractString
            _tryasdate(v)
        elseif v isa Integer
            Int(v) |> TimeTicks.dt
        elseif v isa Number
            DFT(v) |> TimeTicks.dt
        else
            nothing
        end
        parsed === nothing && continue
        return parsed
    end
    nothing
end
function pytodate(py, ::EIDType, args...; kwargs...)
    pytodate(py, args...; kwargs...)
end
get_time(v, keys...) = @something pytodate(v, keys...) TimeTicks.now()

_pystrsym(v::String) = uppercase(v)
_pystrsym(v::Symbol) = uppercase(string(v))
_pystrsym(ii::InstrumentInstance) = ii.bc

_ccxtordertype(::ot.LimitOrderType) = "limit"
_ccxtordertype(::ot.MarketOrderType) = "market"
_ccxtorderside(::BySide{Buy}) = "buy"
_ccxtorderside(::BySide{Sell}) = "sell"
_ccxtobside(::BySide{Buy}) = "bids"
_ccxtobside(::BySide{Sell}) = "asks"
_ccxtorderside(::Union{AnyBuyOrder,Type{<:AnyBuyOrder}}) = "buy"
_ccxtorderside(::Union{AnySellOrder,Type{<:AnySellOrder}}) = "sell"
_ccxtmarginmode(::IsolatedMargin{<:Any}) = "isolated"
_ccxtmarginmode(::CrossMargin{<:Any}) = "cross"
_ccxtmarginmode(::NoMargin) = nothing
_ccxtmarginmode(v) = marginmode(v) |> _ccxtmarginmode
ordertype_fromccxt(resp, eid::EIDType) =
    let v = resp_order_type(resp, eid)
        if string(v) == "market"
            if resp_order_reduceonly(resp, eid)
                ot.ForcedOrderType
            else
                ot.MarketOrderType
            end
        elseif string(v) == "limit"
            ordertype_fromtif(resp, eid)
        else
            nothing
        end
    end

function _ccxttif(exc, type)
    if has(exc, :timeInForce)
        tif = get(exc, :timeInForce, nothing)
        if tif isa Dict
            return get(tif, string(type), nothing)
        end
    end
    nothing
end

ordertype_fromtif(o, eid::EIDType) =
    let tif = resp_order_tif(o, eid)
        if tif == "PO" || string(tif) == "PO"
            ot.PostOnlyOrderType
        elseif tif == "GTC" || string(tif) == "GTC"
            ot.GTCOrderType
        elseif tif == "FOK" || string(tif) == "FOK"
            ot.FOKOrderType
        elseif tif == "IOC" || string(tif) == "IOC"
            ot.IOCOrderType
        end
    end

_orderside(o, eid) =
    let v = resp_order_side(o, eid)
        if string(v) == "buy"
            Buy
        elseif string(v) == "sell"
            Sell
        end
    end

_orderid(o, eid::EIDType) =
    let v = resp_order_id(o, eid)
        if v isa AbstractString
            return string(v)
        else
            v = resp_order_clientid(o, eid)
            if v isa AbstractString
                return string(v)
            end
        end
    end

function _checkordertype(exc, sym)
    @assert has(exc, sym) "Exchange $(nameof(exc)) doesn't support $sym orders."
end

function _ccxtordertype(exc, type)
    if has(exc, :orderTypes)
        ot_map = exc[:orderTypes]
        if ot_map isa Dict
            return get(ot_map, string(type), nothing)
        end
    end
    string(type)
end

time_in_force_value(::Exchange, v) = v
time_in_force_key(::Exchange) = "timeInForce"

function resp_isfilled(resp, ::EIDType)
    # An order is fully filled when nothing remains and some amount was filled.
    rem = get_float(resp, "remaining")
    filled = get_float(resp, "filled")
    iszero(rem) && filled > zero(DFT)
end

function isorder_synced(o, ii, resp, eid::EIDType=exchangeid(ii))
    if !resp_isfilled(resp, eid)
        return false
    end
    filled = resp_order_filled(resp, eid)
    o_filled = filled_amount(o)
    isorder_synced_result = isequal(ii, filled, o_filled, Val(:amount))
    return isorder_synced_result
end
function _ccxt_sidetype(
    resp, eid::EIDType; o=nothing, getter=resp_trade_side, def::Type{<:OrderSide}=Sell
)::Type{<:OrderSide}
    side = getter(resp, eid)
    if string(side) == "buy"
        Buy
    elseif string(side) == "sell"
        Sell
    elseif applicable(orderside, o)
        orderside(o)
    else
        def
    end
end

_ccxtisstatus(status::String, what) = status == what
function _ccxtisstatus(resp, statuses::Vararg{String})
    this_statuses = isempty(statuses) ? ("open", "closed", "canceled", "rejected", "expired") : statuses
    s = string(resp)
    any(x -> s == x, this_statuses)
end
function _ccxtisstatus(resp, status::String, eid::EIDType)
    string(resp_order_status(resp, eid)) == status
end
function _ccxtisstatus(resp, eid::EIDType)
    _ccxtisstatus(resp_order_status(resp, eid), "open", "closed", "canceled", "rejected", "expired")
end
_ccxtisopen(resp, eid::EIDType) = string(resp_order_status(resp, eid)) == "open"
function _ccxtisopen(resp, eid::EIDType, ::Val{:status})
    status = string(resp_order_status(resp, eid))
    status == "open", status
end
function _ccxtisclosed(resp, eid::EIDType)
    string(resp_order_status(resp, eid)) == "closed"
end

balance_type(s::NoMarginStrategy) = attr(s, :balance_type, :spot)
balance_type(s::MarginStrategy) = attr(s, :balance_type, :swap)

function _ccxt_balance_args(s, kwargs)
    merge(
        Dict{String,Any}("type" => string(balance_type(s))),
        Dict{String,Any}(string(k) => v for (k, v) in pairs(kwargs)),
    )
end

resp_trade_cost(resp, ::EIDType)::DFT = get_float(resp, "cost")
resp_trade_amount(resp, ::EIDType)::DFT = get_float(resp, Trf.amount)
resp_trade_amount(resp, ::EIDType, ::Type{Any}) = get(resp, Trf.amount, nothing)
resp_trade_price(resp, ::EIDType)::DFT = get_float(resp, Trf.price)
resp_trade_price(resp, ::EIDType, ::Type{Any}) = get(resp, Trf.price, nothing)
resp_trade_timestamp(resp, ::EIDType) = something(get(resp, Trf.timestamp, 0), 0)
resp_trade_timestamp(resp, ::EIDType, ::Type{DateTime}) = get_time(resp)
resp_trade_symbol(resp, ::EIDType) = something(get(resp, Trf.symbol, ""), "")
resp_trade_id(resp, ::EIDType) = something(get(resp, Trf.id, ""), "")
resp_trade_side(resp, ::EIDType) = get(resp, Trf.side, nothing)
resp_trade_fee(resp, ::EIDType) = get(resp, Trf.fee, nothing)
resp_trade_fees(resp, ::EIDType) = get(resp, Trf.fees, nothing)
resp_trade_order(resp, ::EIDType) = get(resp, Trf.order, nothing)
resp_trade_order(resp, ::EIDType, ::Type{String}) = string(something(get(resp, Trf.order, ""), ""))
resp_trade_type(resp, ::EIDType) = get(resp, Trf.type, nothing)
resp_trade_tom(resp, ::EIDType) = get(resp, Trf.takerOrMaker, nothing)
resp_trade_info(resp, ::EIDType) = get(resp, "info", nothing)

resp_order_remaining(resp, ::EIDType)::DFT = get_float(resp, "remaining")
resp_order_remaining(resp, ::EIDType, ::Type{Any}) = get(resp, "remaining", nothing)
resp_order_filled(resp, ::EIDType)::DFT = get_float(resp, "filled")
resp_order_filled(resp, ::EIDType, ::Type{Any}) = get(resp, "filled", nothing)
resp_order_cost(resp, ::EIDType)::DFT = get_float(resp, "cost")
resp_order_cost(resp, ::EIDType, ::Type{Any}) = get(resp, "cost", nothing)
resp_order_average(resp, ::EIDType)::DFT = get_float(resp, "average_price")
resp_order_average(resp, ::EIDType, ::Type{Any}) = get(resp, "average_price", nothing)
resp_order_price(resp, ::EIDType, ::Type{Any}) = get(resp, "price", nothing)
function resp_order_price(resp, ::EIDType, args...; kwargs...)::DFT
    get_float(resp, "price", args...; kwargs...)
end
resp_order_amount(resp, ::EIDType, ::Type{Any}) = get(resp, "amount", nothing)
function resp_order_amount(resp, ::EIDType, args...; kwargs...)::DFT
    get_float(resp, "amount", args...; kwargs...)
end
resp_order_trades(resp, ::EIDType) = get(resp, "trades", nothing)
resp_order_type(resp, ::EIDType) = something(get(resp, "type", ""), "")
resp_order_tif(resp, ::EIDType) = something(get(resp, "timeInForce", ""), "")
resp_order_lastupdate(resp, ::EIDType) = get(resp, "lastUpdateTimestamp", nothing)
resp_order_timestamp(resp, ::EIDType) = pytodate(resp)
resp_order_timestamp(resp, ::EIDType, ::Type{Any}) = get(resp, "timestamp", nothing)
resp_order_id(resp, ::EIDType) = something(get(resp, "id", ""), "")
resp_order_id(resp, eid::EIDType, ::Type{String})::String =
    string(something(resp_order_id(resp, eid), ""))
resp_order_clientid(resp, ::EIDType) = something(get(resp, "clientOrderId", ""), "")
resp_order_symbol(resp, ::EIDType) = something(get(resp, "symbol", ""), "")
resp_order_side(resp, ::EIDType) = get(resp, Trf.side, nothing)
resp_order_status(resp, ::EIDType) = something(get(resp, "status", ""), "")
function resp_order_status(resp, eid::EIDType, ::Type{String})
    string(something(resp_order_status(resp, eid), ""))
end
resp_order_loss_price(resp, ::EIDType)::Option{DFT} =
    _option_float(resp, "stopLossPrice"; nonzero=true)
resp_order_profit_price(resp, ::EIDType)::Option{DFT} =
    _option_float(resp, "takeProfitPrice"; nonzero=true)
resp_order_stop_price(resp, ::EIDType)::Option{DFT} =
    _option_float(resp, "stopPrice"; nonzero=true)
resp_order_trigger_price(resp, ::EIDType)::Option{DFT} =
    _option_float(resp, "triggerPrice"; nonzero=true)
resp_order_info(resp, ::EIDType) = get(resp, "info", nothing)
resp_order_reduceonly(resp, ::EIDType) = something(get(resp, "reduceOnly", false), false) == true

resp_position_symbol(resp, ::EIDType) = get(resp, Pos.symbol, nothing)
function resp_position_symbol(resp, ::EIDType, ::Type{String})
    string(something(get(resp, Pos.symbol, ""), ""))
end
resp_position_contracts(resp, ::EIDType)::DFT = get_float(resp, Pos.contracts)
resp_position_entryprice(resp, ::EIDType)::DFT = get_float(resp, Pos.entryPrice)
resp_position_mmr(resp, ::EIDType)::DFT = get_float(resp, "maintenanceMarginPercentage")
resp_position_side(resp, ::EIDType) = lowercase(string(something(get(resp, Pos.side, ""), "")))
resp_position_unpnl(resp, ::EIDType)::DFT = get_float(resp, Pos.unrealizedPnl)
resp_position_leverage(resp, ::EIDType)::DFT = get_float(resp, Pos.leverage)
resp_position_liqprice(resp, ::EIDType)::DFT = get_float(resp, Pos.liquidationPrice)
resp_position_initial_margin(resp, ::EIDType)::DFT = get_float(resp, Pos.initialMargin)
resp_position_maintenance_margin(resp, ::EIDType)::DFT =
    get_float(resp, Pos.maintenanceMargin)
resp_position_collateral(resp, ::EIDType)::DFT = get_float(resp, Pos.collateral)
resp_position_notional(resp, ::EIDType)::DFT = get_float(resp, Pos.notional)
resp_position_lastprice(resp, ::EIDType)::DFT = get_float(resp, Pos.lastPrice)
resp_position_markprice(resp, ::EIDType)::DFT = get_float(resp, Pos.markPrice)
@doc """ Get whether the position response indicates hedged mode.
Ccxt does not include a \"hedged\" field in standard position responses — hedge
mode is an account-level setting (set via `setPositionMode`), not a per-position field.
Returns `nothing` when the field is absent so callers can fall back to the local
instance margin mode as the authoritative source.
"""
resp_position_hedged(resp, ::EIDType)::Option{Bool} = get(resp, Pos.hedged, nothing)
resp_position_timestamp(resp, ::EIDType)::DateTime = get_time(resp)
resp_position_margin_mode(resp, ::EIDType) = get(resp, Pos.marginMode, nothing)
function resp_position_margin_mode(resp, eid::EIDType, ::Val{:parsed})
    mm = get(resp, Pos.marginMode, nothing)
    isnothing(mm) && return nothing
    hedged = resp_position_hedged(resp, eid)
    # `hedged` may be `nothing` (ccxt doesn't always include a per-position
    # hedged flag — it's an account-level setting). Fall back to `false` so
    # we return the base mode; callers that care about hedged mode should
    # use the local instance margin mode as authoritative.
    hedged = something(hedged, false)
    if string(mm) == "isolated"
        hedged ? IsolatedHedged() : Isolated()
    elseif string(mm) == "cross"
        hedged ? CrossHedged() : Cross()
    else
        nothing
    end
end

resp_code(resp, ::EIDType) = get(resp, "code", nothing)
resp_ticker_price(resp, ::EIDType, k) = get(resp, string(k), nothing)
resp_event_type(resp, eid::EIDType) =
    begin
        if islist(resp) && !isempty(resp) && let v = first(resp)
            first(v) isa Integer && length(v) == 6
        end
            ot.OHLCVUpdated
        elseif applicable(haskey, resp, "clientOrderId")
            if haskey(resp, "clientOrderId")
                if iszero(resp_order_amount(resp, eid))
                    ot.ExchangeEvent{eid}
                else
                    ot.Order
                end
            elseif haskey(resp, "order")
                ot.Trade
            elseif haskey(resp, "contracts")
                ot.PositionEvent
            elseif haskey(resp, "total") &&
                haskey(resp, "free") &&
                haskey(resp, "used")
                ot.BalanceUpdated
            else
                nothing
            end
        else
            nothing
        end
    end