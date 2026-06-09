using .OrderTypes
using .Misc: IsolatedMargin, CrossMargin, NoMargin, DFT, ZERO
const ot = OrderTypes

_execfunc(f, args...; kwargs...) = f(args...; kwargs...)
_execfunc_timeout(f, args...; timeout, kwargs...) = f(args...; kwargs...)
_execfunc(f::Function, args...; kwargs...) = f(args...; kwargs...)

get_str(v, k) = something(get(v, string(k), nothing), "") |> string
get_float(v, k) = Float64(something(get(v, string(k), 0.0), 0.0))
get_bool(v, k) = something(get(v, string(k), false), false) == true

function _option_float(o, k; nonzero=false)
    v = get(o, string(k), nothing)
    if v isa Number
        ans = Float64(v)
        if nonzero && iszero(ans)
            nothing
        else
            ans
        end
    else
        nothing
    end
end

function get_float(resp, k, def, args...; ai)
    v = _option_float(resp, k)
    if isnothing(v)
        def
    else
        if !ismissing(def) &&
            !isequal(ai, v, def, args...) &&
            !(
                @something(ordertype_fromccxt(resp, exchangeid(ai)), ot.LimitOrderType) <:
                ot.MarketOrderType
            )
            @warn "live: exchange order $k not matching request" ai v def
        end
        v
    end
end

get_timestamp(py, keys=("lastUpdateTimestamp", "timestamp")) =
    for k in keys
        v = get(py, string(k), nothing)
        v !== nothing && return v
    end

_tryasdate(v) = tryparse(DateTime, rstrip(string(v), 'Z'))
pytodate(py) = pytodate(py, "lastUpdateTimestamp", "timestamp")
function pytodate(py, keys...)
    v = get_timestamp(py, keys)
    if v isa AbstractString
        _tryasdate(v)
    elseif v isa Integer
        Int(v) |> TimeTicks.dt
    elseif v isa Number
        DFT(v) |> TimeTicks.dt
    end
end
function pytodate(py, ::EIDType, args...; kwargs...)
    pytodate(py, args...; kwargs...)
end
get_time(v, keys...) = @something pytodate(v, keys...) now()

_pystrsym(v::String) = uppercase(v)
_pystrsym(v::Symbol) = uppercase(string(v))
_pystrsym(ai::AssetInstance) = ai.bc

_ccxtordertype(::ot.LimitOrderType) = "limit"
_ccxtordertype(::ot.MarketOrderType) = "market"
_ccxtorderside(::BySide{Buy}) = "buy"
_ccxtorderside(::BySide{Sell}) = "sell"
_ccxtobside(::BySide{Buy}) = "bids"
_ccxtobside(::BySide{Sell}) = "asks"
_ccxtorderside(::Union{AnyBuyOrder,Type{<:AnyBuyOrder}}) = "buy"
_ccxtorderside(::Union{AnySellOrder,Type{<:AnySellOrder}}) = "sell"
_ccxtmarginmode(::IsolatedMargin) = "isolated"
_ccxtmarginmode(::NoMargin) = nothing
_ccxtmarginmode(::CrossMargin) = "cross"
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
    if type <: AnyPostOnlyOrder
        @assert has(exc, :createPostOnlyOrder) "Exchange $(nameof(exc)) doesn't support post only orders."
        "PO"
    elseif type <: AnyGTCOrder
        "GTC"
    elseif type <: AnyFOKOrder
        "FOK"
    elseif type <: AnyIOCOrder
        "IOC"
    elseif type <: AnyMarketOrder
        ""
    else
        @warn "Unable to choose time-in-force setting for order type $type (defaulting to GTC)."
        "GTC"
    end
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
    if type <: AnyLimitOrder
        _checkordertype(exc, :createLimitOrder)
        "limit"
    elseif type <: AnyMarketOrder
        _checkordertype(exc, :createMarketOrder)
        "market"
    else
        error("Order type $type is not valid.")
    end
end

time_in_force_value(::Exchange, v) = v
time_in_force_key(::Exchange) = "timeInForce"

function resp_isfilled(resp, ::EIDType)
    get_float(resp, "filled") == get_float(resp, "amount") &&
        iszero(get_float(resp, "remaining"))
end

function isorder_synced(o, ai, resp, eid::EIDType=exchangeid(ai))
    @debug "is order synced:" _module = LogSyncOrder filled_amount(o) resp_order_filled(
        resp, eid
    ) resp_order_trades(resp, eid)
    order_filled = resp_order_filled(resp, eid)
    v =
        isequal(ai, filled_amount(o), order_filled, Val(:amount)) ||
        let ntrades = length(resp_order_trades(resp, eid))
            order_trades = trades(o)
            if ntrades > 0
                ntrades == length(order_trades)
            elseif length(order_trades) > 0
                amt = sum(t.amount for t in order_trades)
                isequal(ai, amt, order_filled, Val(:amount))
            else
                false
            end
        end
    @debug "is order synced:" _module = LogSyncOrder v
    return v
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
    this_statuses = if isempty(statuses)
        ("open", "closed", "canceled", "rejected", "expired")
    else
        statuses
    end
    s = string(resp)
    any(x -> s == x, this_statuses)
end
function _ccxtisstatus(resp, status::String, eid::EIDType)
    string(resp_order_status(resp, eid)) == status
end
function _ccxtisstatus(resp, eid::EIDType)
    _ccxtisstatus(resp_order_status(resp, eid))
end
_ccxtisopen(resp, eid::EIDType) = string(resp_order_status(resp, eid)) == "open"
function _ccxtisopen(resp, eid::EIDType, ::Val{:status})
    status = string(resp_order_status(resp, eid))
    (status == "open", status)
end
function _ccxtisclosed(resp, eid::EIDType)
    string(resp_order_status(resp, eid)) == "closed"
end

balance_type(s::NoMarginStrategy) = attr(s, :balance_type, :spot)
balance_type(s::MarginStrategy) = attr(s, :balance_type, :swap)

function _ccxt_balance_args(s, kwargs)
    params, rest = split_params(kwargs)
    @lget! params "type" string(balance_type(s))
    (; params, rest)
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
resp_position_hedged(resp, ::EIDType)::Bool = get_bool(resp, Pos.hedged)
resp_position_timestamp(resp, ::EIDType)::DateTime = get_time(resp)
resp_position_margin_mode(resp, ::EIDType) = get(resp, Pos.marginMode, nothing)
function resp_position_margin_mode(resp, eid::EIDType, ::Val{:parsed})
    v = resp_position_margin_mode(resp, eid)
    if isnothing(v)
        nothing
    else
        marginmode(v)
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
