using ..Executors.Instances: leverage!, positionside, leverage, MarginInstance
using ..Executors: hasorders
using ..Executors.OrderTypes: postoside
using ..Strategies: MarginStrategy, NoMarginStrategy
using ..Instances: ishedged, NoMarginInstance
using ..Lang: splitkws

const _PROTECTIONS_WARNING = """
!!! warning "Protections"
    Usually an exchange checks before executing a trade if right after the trade
    the position would be liquidated, and would prevent you to do such trade, however we
    always check after the trade, and liquidate accordingly, this is pessimistic since
    we can't ensure that all exchanges have such protections in place.
"""

function singlewaycheck(s, ii, t)
    # Hedged mode allows both sides simultaneously
    ishedged(ii) && return true
    pside = positionside(t)
    opside = opposite(pside)
    opside_inst = opside isa Type ? opside() : opside
    # HACK: see Instances `status!`
    if isopen(ii, opside) && !iszero(ii, opside_inst)
        return false
    end
    for (_, o) in orders(s, ii)
        if positionside(o) == opside
            return false
        end
    end
    return true
end
@doc "Creates a simulated limit order, updating a levarged position."
function call!(
    s::MarginStrategy{Sim},
    ii::MarginInstance,
    t::Type{<:AnyLimitOrder};
    amount,
    kwargs...,
)
    !singlewaycheck(s, ii, t) && return nothing
    fees_kwarg, order_kwargs = splitkws(:fees; kwargs)
    o = create_sim_limit_order(s, t, ii; amount, order_kwargs...)
    return if !isnothing(o)
        t = order!(s, o, o.date, ii; fees_kwarg...)
        @deassert abs(committed(o)) > DFT(0.0) || pricetime(o) ∉ keys(orders(s, ii, o))
        t
    end
end

@doc """"Creates a simulated market order, updating a levarged position.
$_PROTECTIONS_WARNING
"""
function call!(
    s::MarginStrategy{Sim},
    ii::MarginInstance,
    t::Type{<:AnyMarketOrder};
    amount,
    date,
    kwargs...,
)
    !singlewaycheck(s, ii, t) && return nothing
    fees_kwarg, order_kwargs = splitkws(:fees; kwargs)
    o = create_sim_market_order(s, t, ii; amount, date, order_kwargs...)
    isnothing(o) && return nothing
    marketorder!(s, o, ii, amount; date, fees_kwarg...)
end


@doc "Closes a leveraged position."
function call!(
    s::MarginStrategy{<:Union{Paper,Sim}},
    ii::MarginInstance,
    side::ByPos,
    date,
    ::PositionClose;
    kwargs...,
)::Bool
    # In hedged mode, cancel only orders on the side being closed to preserve the opposite side's active orders.
    call!(s, ii, CancelOrders(); t=ishedged(ii) ? postoside(side) : BuyOrSell)
    v = close_position!(s, ii, side, date; kwargs...)
    if !v
        @error "close_position! returned false (failed to close position)" ii=scalar(ii) side
        throw(ArgumentError("Failed to close position for $ii on side $side"))
    end
    @deassert !isopen(ii, side)
    v
end

@doc "Closes all strategy positions"
function call!(s::MarginStrategy{Sim}, side::ByPos, date, ::PositionClose; kwargs...)
    LittleDict(
        ii => call!(s, ii, side, date, PositionClose(); kwargs...) for ii in s.universe
    )
end
@doc "Closes all strategy positions (no margin)"
function call!(s::NoMarginStrategy{Sim}, side::ByPos, date, ::PositionClose; kwargs...)
    LittleDict(
        ii => call!(s, ii, side, date, PositionClose(); kwargs...) for ii in s.universe
    )
end

_lev_value(lev::Function) = lev()
_lev_value(lev) = lev

# TODO: implement leverage update mechanisms when position is open (and or has orders)
@doc "Update position leverage. Returns true if the update was successful, false otherwise.

The leverage is not updated when the position has pending orders or is open (and it will return false in such cases.)
"
function call!(
    s::MarginStrategy{<:Union{Sim,Paper}},
    ii::MarginInstance,
    lev,
    ::UpdateLeverage;
    pos::PositionSide,
    kwargs...,
)
    if isopen(ii, pos) || hasorders(s, ii, pos)
        false
    else
        leverage!(ii, _lev_value(lev), pos)
        @deassert isapprox(leverage(ii, pos), _lev_value(lev), atol=1e-1) (
            leverage(ii, pos), lev
        )
        true
    end
end

@doc "Closes a leveraged position (no margin)."
function call!(
    s::NoMarginStrategy{Sim},
    ii::NoMarginInstance,
    side::ByPos,
    date,
    ::PositionClose;
    kwargs...,
)::Bool
    true
end
