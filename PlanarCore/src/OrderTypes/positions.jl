using .Misc: DFT

abstract type PositionEvent{E} <: ExchangeEvent{E} end

@doc "A position snapshot represents the state of a position *after* some `ExchangeEvent` has happened.

$(FIELDS)
"
struct PositionUpdated{E} <: PositionEvent{E}
    tag::Symbol
    group::Symbol
    asset::String
    side_status::Tuple{PositionSide,Bool}
    timestamp::DateTime
    liquidation_price::DFT
    entryprice::DFT
    maintenance_margin::DFT
    initial_margin::DFT
    leverage::DFT
    notional::DFT
end

@doc "Updating the margin of a position implies also adjusting its liquidation price.

$(FIELDS)
"
struct MarginUpdated{E} <: PositionEvent{E}
    tag::Symbol
    group::Symbol
    asset::String
    side::PositionSide
    timestamp::DateTime
    mode::String
    from::DFT
    value::DFT
end

@doc "Updating the leverage of a position implies also adjusting its liquidation price, notional, .

$(FIELDS)
"
struct LeverageUpdated{E} <: PositionEvent{E}
    tag::Symbol
    group::Symbol
    asset::String
    side::PositionSide
    timestamp::DateTime
    from::DFT
    value::DFT
end

@doc "An order event representing a liquidation or similar order-related event."
struct OrderEvent{E} <: PositionEvent{E}
    tag::Symbol
    group::Symbol
    asset::String
    side_status::Tuple{PositionSide,Bool}
    date::DateTime
    price::DFT
    max_price::DFT
    qty::DFT
    max_qty::DFT
    leverage::DFT
    entry_price::DFT
end

function OrderEvent(tag, group, asset, side_status, date, price, max_price, qty, max_qty, leverage, entry_price)
    return OrderEvent{:default}(tag, group, asset, side_status, date, price, max_price, qty, max_qty, leverage, entry_price)
end

@doc "A margin change event."
struct MarginEvent{E} <: PositionEvent{E}
    tag::Symbol
    group::Symbol
    asset::String
    side::PositionSide
    date::DateTime
    mode::String
    amount::DFT
    new_amount::DFT
end

function MarginEvent(tag, group, asset, side, date, mode, amount, new_amount)
    return MarginEvent{:default}(tag, group, asset, side, date, mode, amount, new_amount)
end

@doc "A leverage change event."
struct LeverageEvent{E} <: PositionEvent{E}
    tag::Symbol
    group::Symbol
    asset::String
    side::PositionSide
    date::DateTime
    from::DFT
    value::DFT
end

function LeverageEvent(tag, group, asset, side, date, from, value)
    return LeverageEvent{:default}(tag, group, asset, side, date, from, value)
end

import Base: getproperty

function getproperty(pe::OrderEvent, s::Symbol)
    if s === :side
        return getfield(pe, :side_status)[1]
    elseif s === :reduce_only
        return getfield(pe, :side_status)[2]
    elseif s === :date
        return getfield(pe, :date)
    else
        return getfield(pe, s)
    end
end

function getproperty(me::MarginEvent, s::Symbol)
    if s === :date
        return getfield(me, :date)
    else
        return getfield(me, s)
    end
end

function getproperty(le::LeverageEvent, s::Symbol)
    if s === :date
        return getfield(le, :date)
    else
        return getfield(le, s)
    end
end
