using .OrderTypes: LimitOrderType, ordertype
using .Strategies: Strategies as st
using .Misc: DFT
using .Lang: @ifdebug

"""
Debug state attached to strategy instead of globals to avoid race conditions.
"""
struct SimDebugState
    ctr::Ref{Int}
    cto::Ref{Int}
    price_checks::Ref{Int}
    vol_checks::Ref{Int}
    cash_tracking::Vector{DFT}
end

function _init_debug_state(s)
    s.attrs[:sim_debug_state] = SimDebugState(Ref(0), Ref(0), Ref(0), Ref(0), DFT[])
end

function _get_debug_state(s)
    get(s.attrs, :sim_debug_state, nothing)
end

_vv(v) = v isa Vector ? (isempty(v) ? nothing : v[end]) : v

function _showcash(s, ai)
    @show s.cash s.cash_committed cash(ai) committed(ai)
end

function _showorder(o)
    display(("price: ", o.price))
    display(("comm: ", _vv(o.attrs.committed)))
    display(("unfill: ", _vv(o.attrs.unfilled)))
    display(("amount: ", o.amount))
    display(("trades: ", length(o.attrs.trades)))
end

function _globals(s)
    ds = _get_debug_state(s)
    isnothing(ds) && return nothing
    @show ds.price_checks[] ds.vol_checks[] ds.ctr[] ds.cto[]
    nothing
end

function _resetglobals!(s)
    ds = _get_debug_state(s)
    if !isnothing(ds)
        ds.ctr[] = 0
        ds.cto[] = 0
        ds.price_checks[] = 0
        ds.vol_checks[] = 0
        empty!(ds.cash_tracking)
    else
        _init_debug_state(s)
    end
    s[:debug_afterorder] = _afterorder
    s[:debug_beforetrade] = _beforetrade
    s[:debug_aftertrade] = _aftertrade
    s[:debug_check_committments] = _check_committments
end

function _afterorder(s)
    ds = _get_debug_state(s)
    !isnothing(ds) && (ds.cto[] += 1)
end

function _beforetrade(s, ai, o, trade, actual_price)
    @ifdebug @assert trade.size != DFT(0.0) "Trade must not be empty, size was $(trade.size)."
    ds = _get_debug_state(s)
    !isnothing(ds) && (ds.ctr[] += 1)
    ds = _get_debug_state(s)
    !isnothing(ds) && push!(ds.cash_tracking, actual_price)
    get(s.attrs, :verbose, false) || return nothing
    _showcash(s, ai)
    _showorder(o)
end

function _aftertrade(s, ai, o)
    get(s.attrs, :verbose, false) || return nothing
    _showorder(o)
    _showcash(s, ai)
    println("\n")
    ds = _get_debug_state(s)
    !isnothing(ds) && get(s.attrs, :debug_maxtrades, Inf) == ds.ctr[] && @error "Debug max trades reached"
end

function _check_committments(s::Strategy, ai)
    ds = _get_debug_state(s)
    cash_comm = DFT(0.0)
    n = 0
    for (_, ords) in s.buyorders
        for (_, o) in ords
            o isa ShortBuyOrder && continue
            cash_comm += committed(o)
            n += 1
        end
    end
    for (_, ords) in s.sellorders
        for (_, o) in ords
            if o isa ShortSellOrder
                cash_comm += committed(o)
                n += 1
            end
        end
    end
    @ifdebug @assert if orderscount(s) == 0
        iszero(cash_comm) && approxzero(s.cash_committed)
    else
        isapprox(cash_comm, s.cash_committed, atol=2s.cash_committed.precision) || haskey(s.attrs, :sim_fees)
    end (; cash_comm, s.cash_committed.value, ai, n)
end

function _check_committments(s, ai::AssetInstance, t::Trade)
    get(s.attrs, :verbose, false) && begin
        @show (@something ai.longpos ai).cash_committed
        @show (@something ai.shortpos ai).cash_committed
    end
    orders_long = DFT(0.0)
    orders_short = DFT(0.0)
    for (_, o) in orders(s, ai, positionside(t)())
        @ifdebug @assert o.asset == ai.asset
        if o isa SellOrder
            @ifdebug @assert positionside(o) == Long o
            orders_long += committed(o)
        elseif o isa ShortBuyOrder
            @ifdebug @assert positionside(o) == Short o
            orders_short += committed(o)
        end
    end
    asset_long = committed(ai, Long())
    asset_short = committed(ai, Short())
    if t isa ShortBuyTrade
        asset_short -= committed(t.order)
    end
    @ifdebug @assert isapprox(orders_long, asset_long, atol=1e-6) (; orders_long, asset_long, Long)
    @ifdebug @assert isapprox(orders_short, asset_short, atol=1e-6) (; orders_short, asset_short, Short)
end