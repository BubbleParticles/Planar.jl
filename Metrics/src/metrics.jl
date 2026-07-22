using .Statistics: std
using Base: negate
using .st: trades_count

const DAYS_IN_YEAR = 365
@doc "All the metrics that supported."
const METRICS = Set((
    :total, :sharpe, :sortino, :calmar, :drawdown, :expectancy, :cagr, :trades
))

@doc """ Generates code to calculate the cumulative total balance for a given set of trades over a given timeframe.

$(SIGNATURES)

This macro generates code that calculates the cumulative total balance for a given set of trades `s` over a given timeframe `tf`.
It first gets a DataFrame of balances for `s` and `tf` using the `trades_balance` function.
If this DataFrame is `nothing` (which means there are no trades), it immediately returns `-Inf`.
Otherwise, it extracts the `cum_total` column from the DataFrame, which represents the cumulative total balance, and assigns this to `balance`.
The generated code is then returned.
"""
macro balance_arr()
    s = esc(:s)
    tf = esc(:tf)
    quote
        $(esc(:balance)) = let balance_df = trades_balance($s; $tf)
            isnothing(balance_df) && return -Inf
            balance_df.cum_total
        end
    end
end

@doc """ Calculates the simple returns for an array of prices.

$(SIGNATURES)

This function takes an array of prices `arr` as a parameter, calculates the differences between successive prices, divides each difference by the corresponding previous price, and returns the resulting array of simple returns.
Please note that the first element of the return array would be `NaN` due to the lack of a previous price for the first element in `arr`.
"""
function _returns_arr(arr)
    n_series = length(arr)
    n_series <= 1 && return eltype(arr)[]
    first_price = arr[1]
    iszero(first_price) && return fill(NaN, n_series - 1)
    diff(arr) ./ replace(v -> iszero(v) ? one(v) : v, view(arr, 1:(n_series - 1)))
end

@doc """ Annualizes a volatility value.

$(SIGNATURES)

This function takes a volatility value `v` and a timeframe `tf` as parameters.
It multiplies `v` by the square root of the ratio of the number of days in a year times the period of `tf` to the period of a day.
This effectively converts `v` from a volatility per `tf` period to an annual volatility.
"""
_annualize(v, tf) = v * sqrt(DAYS_IN_YEAR * period(tf) / period(tf"1d"))

@doc """ Computes the non-annualized Sharpe ratio.

$(TYPEDSIGNATURES)

Calculates the Sharpe ratio given an array of `returns`.
The ratio is computed as the excess of the mean return over the risk-free rate `rfr`, divided by the standard deviation of the `returns`.
`tf` specifies the timeframe for the returns and defaults to one day.

"""
function _rawsharpe(returns; rfr=0.0, tf=tf"1d")
    length(returns) < 2 && return 0.0
    avg_returns = mean(returns)
    std_ret = std(returns)
    iszero(std_ret) && return 0.0  # no risk = no Sharpe
    ratio = (avg_returns - rfr) / std_ret
    _annualize(ratio, tf)
end

@doc """ Computes the Sharpe ratio for a given strategy.

$(TYPEDSIGNATURES)

Calculates the Sharpe ratio for a `Strategy` `s` over a specified timeframe `tf`, defaulting to one day.
The risk-free rate `rfr` can be specified, and defaults to 0.0.

"""
function sharpe(s::Strategy, tf=tf"1d"; rfr=0.0)
    @balance_arr
    returns = _returns_arr(balance)
    _rawsharpe(returns; rfr, tf)
end

@doc """ Computes the non-annualized Sortino ratio.

$(TYPEDSIGNATURES)

Calculates the Sortino ratio given an array of `returns`.
The ratio is the excess of the mean return over the risk-free rate `rfr`, divided by the standard deviation of the negative `returns`.
`tf` specifies the timeframe for the returns and defaults to one day.

"""
function _rawsortino(returns; rfr=0.0, tf=tf"1d")
    avg_returns = mean(returns)
    downside_idx = returns .< 0.0
    if sum(downside_idx) < 2
        # Zero or single downside return → no downside risk = perfect Sortino → return 0.0
        return 0.0
    end
    downside_returns = view(returns, downside_idx)
    downside_std = std(downside_returns)
    iszero(downside_std) && return 0.0  # no downside deviation = perfect Sortino
    ratio = (avg_returns - rfr) / downside_std
    _annualize(ratio, tf)
end

@doc """ Computes the Sortino ratio for a given strategy.

$(TYPEDSIGNATURES)

Calculates the Sortino ratio for a `Strategy` `s` over a specified timeframe `tf`, defaulting to one day.
The risk-free rate `rfr` can be specified, and defaults to 0.0.

"""
function sortino(s::Strategy, tf=tf"1d"; rfr=0.0)
    @balance_arr
    returns = _returns_arr(balance)
    _rawsortino(returns; rfr, tf)
end

@doc """ Computes the non-annualized Calmar ratio.

$(TYPEDSIGNATURES)

Calculates the Calmar ratio given an array of `returns`.
The ratio is the annual return divided by the maximum drawdown.
`tf` specifies the timeframe for the returns and defaults to one day.

"""
function _rawcalmar(returns; tf=tf"1d")
    isempty(returns) && return 0.0
    max_drawdown = maxdd(returns).dd
    iszero(max_drawdown) && return 0.0  # no drawdown = perfect Calmar
    annual_returns = mean(returns) * DAYS_IN_YEAR
    isnan(annual_returns) && return 0.0
    negate(annual_returns) / max_drawdown
end

@doc """ Computes the maximum drawdown for a series of returns.

$(TYPEDSIGNATURES)

Calculates the maximum drawdown given an array of `returns`.
The drawdown is the largest percentage drop in the cumulative product of 1 plus the returns.

"""
function maxdd(returns)
    isempty(returns) && return (; dd=0.0, ath=NaN, cum_returns=returns)
    length(returns) == 1 && return (; dd=0.0, ath=first(returns), cum_returns=returns)
    @deassert all(x >= -1.0 for x in returns)
    cum_returns = cumprod(1.0 .+ returns)
    ath = first(cum_returns)
    dd = typemax(eltype(cum_returns))
    for n in eachindex(cum_returns)
        bal = cum_returns[n]
        if bal > ath
            ath = bal
        elseif bal < ath
            this_dd = bal / ath
            if this_dd < dd
                dd = this_dd
            end
        end
    end
    dd = dd == typemax(eltype(cum_returns)) ? 0.0 : -(1.0 - dd)
    (; dd, ath, cum_returns)
end

@doc """ Computes the Calmar ratio for a given strategy.

$(TYPEDSIGNATURES)

Calculates the Calmar ratio for a `Strategy` `s` over a specified timeframe `tf`, defaulting to one day.

"""
function calmar(s::Strategy, tf=tf"1d")
    @balance_arr
    returns = _returns_arr(balance)
    _rawcalmar(returns; tf)
end

@doc """ Computes the trading expectancy.

$(TYPEDSIGNATURES)

Calculates the trading expectancy given an array of `returns`.
This is a measure of the mean value of both winning and losing trades.
It takes into account both the probability and the average win/loss of trades.

"""
function _rawexpectancy(returns)
    isempty(returns) && return 0.0

    ups_idx = returns .> 0.0
    ups = view(returns, ups_idx)
    isempty(ups) && return 0.0

    downs = view(returns, xor.(ups_idx, true))
    avg_up = mean(ups)
    isempty(downs) && return 1.0  # no losing trades → perfect expectancy
    avg_down = mean(abs.(downs))
    risk_reward_ratio = avg_down == 0.0 ? Inf : avg_up / avg_down
    up_rate = length(ups) / length(returns)

    return ((1.0 + risk_reward_ratio) * up_rate) - 1.0
end

@doc """ Computes the trading expectancy for a given strategy.

$(TYPEDSIGNATURES)

Calculates the trading expectancy for a `Strategy` `s` over a specified timeframe `tf`, defaulting to one day.

"""
function expectancy(s::Strategy, tf=tf"1d")
    @balance_arr
    returns = _returns_arr(balance)
    _rawexpectancy(returns)
end

@doc """ Computes the Compound Annual Growth Rate (CAGR) for a given strategy.

$(TYPEDSIGNATURES)

Calculates the CAGR for a `Strategy` `s` over a specified `Period` `prd`, defaulting to the period of the strategy's trades.
The initial cash amount `initial` and the pricing function `price_func` can also be specified.

"""
function cagr(
    s::Strategy,
    prd::Period=st.tradesperiod(s),
    initial=s.initial_cash,
    price_func=st.lasttrade_price_func,
)
    iszero(initial) && return NaN
    final = st.current_total(s, price_func)
    iszero(final) && return NaN
    total_return = final / initial - 1.0
    total_return < -1.0 && return NaN
    (final / initial)^inv(prd / Day(DAYS_IN_YEAR)) - 1.0
end

@doc """ Returns a dict of calculated metrics for a given strategy.

$(TYPEDSIGNATURES)

For a `Strategy` `s`, calculates specified `metrics` over a specified timeframe `tf`, defaulting to one day.
If `normalize` is `true`, the metrics are normalized with respect to `norm_max`.

"""
function multi(
    s::Strategy, metrics::Vararg{Symbol}; tf=tf"1d", normalize=false, norm_max=(;)
)
    balance = let df = trades_balance(s; tf)
        isnothing(df) &&
            return Dict(m => ifelse(normalize, 0.0, typemin(DFT)) for m in metrics)
        df.cum_total
    end
    returns = _returns_arr(balance)
    if isempty(returns)
        return [zero(DFT) for _ in metrics]
    end
    # Sanitize metric values: NaN -> 0.0, Inf -> sign(v)*1e6
    _sanitize(v) = isnan(v) ? 0.0 : (isinf(v) ? sign(v)*1e6 : v)
    maybenorm = normalize ? normalize_metric : (x, _...) -> x
    Dict((m => let v = if m == :sharpe
            _rawsharpe(returns; tf)
        elseif m == :sortino
            _rawsortino(returns; tf)
        elseif m == :calmar
            _rawcalmar(returns; tf)
        elseif m == :drawdown
            maxdd(returns).dd
        elseif m == :expectancy
            _rawexpectancy(returns)
        elseif m == :cagr
            cagr(s)
        elseif m == :total
            balance[end]
        elseif m == :trades
            trades_count(s, Val(:liquidations))[1]
        else
            error("$m is not a valid metric")
        end
        v = _sanitize(v)
        norm_args = if m in norm_max
            (norm_max[m],)
        else
            ()
        end
        maybenorm(v, Val(m), norm_args...)
    end for m in metrics)...)
end

_zeronan(v) = isnan(v) ? 0.0 : v
_sanitize(v) = isnan(v) ? 0.0 : (isinf(v) ? sign(v)*1e6 : v)
_clamp_metric(v, max) = clamp(_sanitize(v / max), zero(v), one(v))
@doc """ Normalize a metric. Based on the value of `max`. """
normalize_metric(v, ::Val{:total}, max=1e6) = _clamp_metric(v, max)
normalize_metric(v, ::Val{:drawdown}, max=1e6) = _clamp_metric(v, max)
normalize_metric(v, ::Val{:sharpe}, max=1e1) = _clamp_metric(v, max)
normalize_metric(v, ::Val{:sortino}, max=1e1) = _clamp_metric(v, max)
normalize_metric(v, ::Val{:calmar}, max=1e1) = _clamp_metric(v, max)
normalize_metric(v, ::Val{:expectancy}, max=1e1) = _clamp_metric(v, max)
normalize_metric(v, ::Val{:cagr}, max=1e2) = _clamp_metric(v, max)
normalize_metric(v, ::Val{:trades}, max=1e6) = _clamp_metric(v, max)

export sharpe, sortino, calmar, expectancy, cagr, multi
