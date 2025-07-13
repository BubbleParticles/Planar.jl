using .oneAPI
using .Executors: orderscount
using .Executors: isoutof_orders
using .Instances.Data.DFUtils: lastdate
using .Misc.LoggingExtras
using Base: with_logger
using .st: universe, current_total, trades_count
using Pbar: @withpbar!, @pbupdate!, ProgressBar, addjob!, ProgressJob, pbar!, Progress, pbar
using .Progress: DescriptionColumn, CompletedColumn, SeparatorColumn, ProgressColumn, AbstractColumn
using Pbar.Term.Segments: Segment
using Pbar.Term.Measures: Measure
using Pbar.Term.Progress: Progress

import .Misc: start!, stop!

# Helper function to check oneAPI availability and functionality
function is_oneapi_functional()
    if !isdefined(Main, :oneAPI)
        return false
    end
    oneAPI_module = getfield(Main, :oneAPI)
    # Check for core oneAPI components needed by this module
    if !isdefined(oneAPI_module, :functional) ||
       !isdefined(oneAPI_module, :oneArray) ||
       !isdefined(oneAPI_module, :oneDeviceArray) || # Used in kernels
       !isdefined(oneAPI_module, :Array) ||
       !isdefined(oneAPI_module, Symbol("@oneapi"))
        return false
    end
    return oneAPI_module.functional()
end

# Helper function to ensure a value is a CPU scalar of a specific type
function ensure_cpu_scalar(val, target_type::Type{T}=DFT) where T
    if is_oneapi_functional()
        oneAPI_module = getfield(Main, :oneAPI)
        if isa(val, oneAPI_module.oneArray)
            # Assuming val is a 1-element oneArray if it's a scalar from GPU
            return convert(T, oneAPI_module.Array(val)[])
        end
    end
    return convert(T, val) # Assume it's already a CPU scalar or other compatible type
end

_lastupdate!(s, date) = s.attrs[:sim_last_orders_update] = date
_lastupdate(s) = s.attrs[:sim_last_orders_update]
function _check_update_date(s, date)
    _lastupdate(s) >= date &&
        error("Tried to update orders multiple times on the same date.")
end

using .Executors.Instances: leverage!, positionside, leverage
using .Executors: hasorders
using .Executors.OrderTypes: postoside
using .Lang: splitkws
import Executors: call!

function position_gpu!(s::IsolatedStrategy{Sim}, ai, date::DateTime, pos::Position=position(ai))
    # NOTE: Order of calls is important
    @deassert isopen(pos)
    p = posside(pos)
    @deassert notional(pos) != 0.0
    timestamp!(pos, date)
    if isliquidatable(s, ai, p, date)
        liquidate!(s, ai, p, date)
    else
        # position is still open
        call!(s, ai, date, pos, PositionUpdate())
    end
end

function positions_kernel(s, holdings, date)
    i = oneAPI.get_global_id()
    ai = holdings[i]
    @deassert isopen(ai) || hasorders(s, ai) ai
    if isopen(ai)
        position_gpu!(s, ai, date)
    end
end

function positions_gpu!(s::IsolatedStrategy{<:Union{Paper,Sim}}, date::DateTime)
    @ifdebug _checkorders(s)

    holdings_oneapi = oneAPI.oneArray(s.holdings)

    oneAPI.@oneapi items=length(holdings_oneapi) groups=256 positions_kernel(s, holdings_oneapi, date)

    @ifdebug _checkorders(s)
    @ifdebug for ai in universe(s)
        @assert !(isopen(ai, Short()) && isopen(ai, Long()))
        po = position(ai)
        @assert if !isnothing(po)
            ai ∈ s.holdings && !iszero(cash(po)) && isopen(po)
        else
            iszero(cash(ai, Long())) &&
                iszero(cash(ai, Short())) &&
                !isopen(ai, Long()) &&
                !isopen(ai, Short())
        end
    end
end

positions_gpu!(args...; kwargs...) = nothing

function update_gpu!(s::Strategy{Sim}, date, ::UpdateOrders)
    _check_update_date(s, date)
    positions_gpu!(s, date)
    for (ai, ords) in s.sellorders
        @ifdebug prev_sell_price = 0.0
        for (pt, o) in collect(ords) # Prefetch the orders since `order!` can unqueue
            @deassert prev_sell_price <= pt.price
            # Need to check again if it is queued in case of liquidation events
            isqueued(o, s, ai) || continue
            order!(s, o, date, ai)
            @ifdebug prev_sell_price = pt.price
        end
    end
    for (ai, ords) in s.buyorders
        @ifdebug prev_buy_price = Inf
        for (pt, o) in collect(ords) # Prefetch the orders since `order!` can unqueue
            @deassert prev_buy_price >= pt.price
            # Need to check again if it is queued in case of liquidation events
            isqueued(o, s, ai) || continue
            order!(s, o, date, ai)
            @ifdebug prev_buy_price = pt.price
        end
    end
    _lastupdate!(s, date)
end

function update_gpu!(s::Strategy{Sim}, date, ::UpdateOrdersShuffled)
    _check_update_date(s, date)
    positions_gpu!(s, date)
    let buys = orders(s, Buy), sells = orders(s, Sell)
        allorders = Tuple{eltype(s.holdings),Union{valtype(buys),valtype(sells)}}[]
        _dopush!(sells, allorders)
        _dopush!(buys, allorders)
        shuffle!(allorders)
        _doall!(s, allorders, date)
    end
    _lastupdate!(s, date)
end

function strategy_call_kernel(s, universe, current_time, ctx)
    i = oneAPI.get_global_id()
    ai = universe[i]
    call!(s, ai, current_time, ctx)
end

function call_gpu!(s::Strategy, current_time::DateTime, ctx)
    universe_oneapi = oneAPI.oneArray(s.universe)
    oneAPI.@oneapi items=length(universe_oneapi) groups=256 strategy_call_kernel(s, universe_oneapi, current_time, ctx)
end
