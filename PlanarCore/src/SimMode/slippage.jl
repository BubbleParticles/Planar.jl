using ..Lang: @ifdebug
using ..Strategies: MarginStrategy
using ..Executors: AnyBuyOrder, AnyMarketOrder, AnyLimitOrder
using ..Misc: toprecision, DFT
import ..Executors: with_slippage

@doc "The default slippage for the strategy."
spreadopt(::Val{:spread}, date, ii) = sml.spreadat(ii, date, Val(:opcl))
@doc "A raw float value (percentage) as slippage."
spreadopt(n::T, args...) where {T<:Real} = n
spreadopt(v, args...) = error("`base_slippage` option value not supported ($v)")

@doc """ Calculate the base slippage for a given strategy, date, and asset.

$(TYPEDSIGNATURES)

This function uses the `spreadopt` function to calculate the base slippage. 
The slippage is determined based on the strategy's attributes, the date, and the asset. 
It is used in the context of trading simulations to model the cost of executing a trade.

"""
_base_slippage
function _base_slippage(s::Strategy, date::DateTime, ii)
    spreadopt(s.attrs[:sim_base_slippage], date, ii)
end

@doc """ Returns a skew factor based on the actual amount and volume.

$(TYPEDSIGNATURES)

This function calculates a skew factor based on the `actual_amount` and `volume`.
If `volume` is <= 0.0, it returns 1.0.
Otherwise, it returns the minimum between 1.0 and the ratio of `actual_amount` to `volume`.

"""
_volumeskew(actual_amount, volume) =
    if volume <= DFT(0.0)
        DFT(1.0)
    else
        min(DFT(1.0), actual_amount / volume)
    end

@doc """ Calculates the price skew based on low and high values at a particular date.

$(TYPEDSIGNATURES)

This function finds the skewness of price for a particular asset `ii` at a given `date`.
The skewness is calculated as `1.0 - lowat(ii, date) / highat(ii, date)`.
The function `lowat` and `highat` are used to get the low and high prices respectively.

"""
_priceskew(ii, date) = begin
    h = highat(ii, date)
    l = lowat(ii, date)
    if h <= DFT(0.0)
        DFT(0.0)
    else
        DFT(1.0) - l / h
    end
end

@doc "Slippage makes price go down for buy orders."
_addslippage(::AnyLimitOrder{Buy}, price, slp) = price - slp
@doc "Slippage makes price go up for sell orders."
_addslippage(::AnyLimitOrder{Sell}, price, slp) = price + slp
@doc "Buy orders slippage is favorable when the close price is lower than the open price."
_isfavorable(::AnyLimitOrder{Buy}, ii, date) = closeat(ii, date) < openat(ii, date)
@doc "Sell orders slippage is favorable when the close price is higher than the open price."
_isfavorable(::AnyLimitOrder{Sell}, ii, date) = closeat(ii, date) > openat(ii, date)

@doc """ Apply slippage to limit orders based on various factors.

$(TYPEDSIGNATURES)

This function applies slippage to limit orders. It calculates the base slippage using `_base_slippage`
and adjusts it based on whether the slippage is favorable for the order. If the slippage is favorable,
it applies the full base slippage; otherwise, it applies a reduced slippage based on the volume skew.
The final price is clamped within the high and low prices of the asset for the given date.

"""
function _with_slippage(
    s::Strategy{<:Union{Paper,Sim}}, o::AnyLimitOrder, ii, ::Val{:skew}; date, kwargs...
)
    bs = _base_slippage(s, o.date, ii)
    vol = volumeat(ii, date)
    vol_skew = _volumeskew(o.amount, vol)
    slp = if _isfavorable(o, ii, date)
        bs
    else
        bs * vol_skew
    end
    _doclamp(o, _addslippage(o, clamp(priceat(s, o, ii, date), lowat(ii, date), highat(ii, date)), slp), ii, date)
end

@doc """ Apply slippage to limit orders based on spread.

$(TYPEDSIGNATURES)

This function applies slippage to limit orders based on the spread. The spread is calculated
using the `spreadat` function from the `Simulations` package. The final price is clamped
within the high and low prices of the asset for the given date.

"""
function _with_slippage(
    s::Strategy{<:Union{Paper,Sim}}, o::AnyLimitOrder, ii, ::Val{:spread}; date, kwargs...
)
    bs = _base_slippage(s, o.date, ii)
    _doclamp(o, _addslippage(o, priceat(s, o, ii, date), bs), ii, date)
end

@doc "Default slippage for limit orders uses skew."
function _with_slippage(
    s::Strategy{<:Union{Paper,Sim}}, o::AnyLimitOrder, ii; date, kwargs...
)
    _with_slippage(s, o, ii, s.attrs[:sim_base_slippage]; date, kwargs...)
end

@doc """ Apply slippage to market orders based on average price.

$(TYPEDSIGNATURES)

This function calculates the slippage for market orders based on the average price. 
The slippage is calculated as the average of the absolute differences between the open price and the close prices at the previous and next timeframes. 
The final price is then adjusted by the calculated slippage.

"""
function _with_slippage(
    s::Strategy{<:Union{Paper,Sim}}, o::AnyMarketOrder, ii, ::Val{:avg}; date, kwargs...
)
    m = openat(ii, date)
    diff1 = abs(closeat(ii, date - s.timeframe) - openat(ii, date))
    diff2 = abs(closeat(ii, date) - openat(ii, date + s.timeframe))
    slp = (diff1 + diff2) / 2.0
    _addslippage(o, m, slp)
end

@doc "Market buy orders price is increased by slippage."
_addslippage(::AnyMarketOrder{Buy}, price, slp) = price + slp
@doc "Market sell orders price is decreased by slippage."
_addslippage(::AnyMarketOrder{Sell}, price, slp) = price - slp

@doc """ Apply slippage to market orders based on skew.

$(TYPEDSIGNATURES)

This function calculates the slippage for market orders based on the skew. 
The skew is calculated as the sum of the volume skew and the price skew. 
The base slippage is then adjusted by the skew rate. 
The final price is clamped within the high and low prices of the asset for the given date, unless the volume skew is very small.

"""
function _with_slippage(
    s::Strategy{<:Union{Paper,Sim}},
    o::AnyMarketOrder,
    ii,
    ::Val{:skew};
    clamp_price,
    actual_amount,
    date,
)
    @deassert o.price == priceat(s, o, ii, date) ||
        o isa Union{LiquidationOrder,ReduceOnlyOrder}
    volume = volumeat(ii, date)
    volume_skew = _volumeskew(actual_amount, volume)
    price_skew = _priceskew(ii, date)
    # neg skew makes the price _increase_ while pos skew makes it decrease
    skew_rate = volume_skew + price_skew
    bs = _base_slippage(s, o.date, ii)
    slp = if skew_rate <= DFT(0.0)
        bs
    else
        bs_skew = clamp_price * skew_rate
        muladd(bs, bs_skew > DFT(10.0) ? log10(bs_skew) : bs_skew / DFT(10.0), bs)
    end
    @assert !isnan(slp)
    @deassert slp >= DFT(0.0)
    slp_price = _addslippage(o, clamp_price, slp)
    # We only go outside candle high/low boundaries if the candle
    # has very little volume, otherwise assume that liquidity is deep enough
    if volume_skew < DFT(1e-3) && !(o isa LiquidationOrder)
        clamp(slp_price, lowat(ii, date), highat(ii, date))
    else
        slp_price
    end
end

@doc """ Clamp the price within the high and low prices of the asset for the given date.

$(TYPEDSIGNATURES)

This function clamps the given `price` within the high and low prices of the asset `ii` for the specified `date`.

"""
function _doclamp(::Order{<:LimitOrderType}, price, ii, date)
    clamp(price, lowat(ii, date), highat(ii, date))
end

@doc "Market order price is never clamped."
_doclamp(::Order{<:MarketOrderType}, price, args...) = price

@doc """ Apply slippage to the given price with respect to a specific order, date, and amount.

$(TYPEDSIGNATURES)

This function applies slippage to the given `price` based on the order `o`, asset instance `ii`,
and the specified `date` and `actual_amount`. It dispatches to the appropriate slippage function
based on the order type and the strategy's slippage configuration.

"""
function _do_slippage(s, o, ii; date, price, actual_amount, kwargs...)
    if o isa AnyLimitOrder
        _with_slippage(s, o, ii; date, kwargs...)
    else
        slippage_mode = s.attrs[:sim_market_slippage]
        if slippage_mode isa Val
            _with_slippage(s, o, ii, slippage_mode; clamp_price=price, actual_amount, date)
        else
            _with_slippage(s, o, ii; date)
        end
    end
end

@doc """ Apply slippage to given `price` with respect to a specific order, date, and amount.

$(TYPEDSIGNATURES)

This function applies slippage to the given `price` based on the order `o`, asset instance `ii`,
and the specified `date` and `actual_amount`. It is the entry point for applying slippage in
simulation and paper trading modes.

"""
function Executors.with_slippage(s::Strategy{<:Union{Paper,Sim}}, o, ii; date, price, actual_amount)
    # Tick mode (set only by the Sim tick `start!`) fills at the exact tick price:
    # no slippage, ever. Paper mode never sets `:sim_tick_mode`, so it is unaffected.
    get(s.attrs, :sim_tick_mode, false) && return price
    _do_slippage(s, o, ii; date, price, actual_amount)
end