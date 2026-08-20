using .ect.OrderTypes: LiquidationTrade, LongTrade, ShortTrade
using .ect.Instances: _ohlcv_keys
using .Data: default_value
using .Data.Misc: OrderedDict

@doc """ Computes the average duration of trades for an asset instance.

$(TYPEDSIGNATURES)

Calculates the average duration between trades for an `InstrumentInstance` `ii`.
The `raw` parameter determines whether the result should be in raw format (in milliseconds) or a compact time format.
The function `f` is used to aggregate the durations and defaults to the mean.

"""
function trades_duration(ii::InstrumentInstance; raw=false, f=mean)
    isempty(ii.history) && return raw ? Millisecond(0) : compact(Millisecond(0))
    periods = getproperty.(ii.history, :date) |> diff
    periods_num = getproperty.(periods, :value) # milliseconds
    μ = if length(ii.history) > 1
        f(periods_num)
    else
        Millisecond(lastdate(ii) - first(ii.history).date).value
    end
    raw ? μ : compact(Millisecond(trunc(μ)))
end

@doc """ Computes the average duration of trades for a strategy.

$(TYPEDSIGNATURES)

Calculates the average duration between trades for a `Strategy` `s`.
The function `f` is used to aggregate the durations and defaults to the mean.

"""
function trades_duration(s::Strategy; f=mean)
    [trades_duration(ii; raw=true, f) for ii in s.universe] |>
    mean |>
    trunc |>
    Millisecond |>
    compact
end

@doc """ Computes the average trade size for an asset instance.

$(TYPEDSIGNATURES)

Calculates the average size of trades for an `InstrumentInstance` `ii`.
The function `f` is used to aggregate the sizes and defaults to the mean.

"""
function trades_size(ii::InstrumentInstance; f=mean)
    vals = getproperty.(ii.history, :size)
    isempty(vals) && return f(Int[])
    f(abs.(vals))
end

@doc """ Computes the average trade size for a strategy.

$(TYPEDSIGNATURES)

Calculates the average size of trades for a `Strategy` `s`.
The function `f` is used to aggregate the sizes and defaults to the mean.

"""
function trades_size(s::Strategy; f=mean)
    [trades_size(ii; f) for ii in s.universe] |> f
end

@doc """ Computes the average leverage for trades of an asset instance.

$(TYPEDSIGNATURES)

Calculates the average leverage of trades for an `InstrumentInstance` `ii`.
The function `f` is used to aggregate the leverages and defaults to the mean.

"""
function trades_leverage(ii::InstrumentInstance; f=mean)
    vals = getproperty.(ii.history, :leverage)
    isempty(vals) && return f(Float64[])
    f(abs.(vals))
end

@doc """ Computes the average hour of trades for an asset instance.

$(TYPEDSIGNATURES)

Calculates the average hour of trades for an `InstrumentInstance` `ii`.
The function `f` is used to aggregate the hours and defaults to the mean.

"""
function trades_hour(ii::InstrumentInstance; f=mean)
    h = Hour.(getproperty.(ii.history, :date))
    h = getproperty.(h, :value)
    isempty(h) && return Hour(0)
    f(h) |> trunc |> Hour
end

@doc """ Computes the average weekday of trades for an asset instance.

$(TYPEDSIGNATURES)

Calculates the average weekday of trades for an `InstrumentInstance` `ii`.
The function `f` is used to aggregate the weekdays and defaults to the mean.

"""
function trades_weekday(ii::InstrumentInstance; f=mean)
    w = dayofweek.(getproperty.(ii.history, :date))
    isempty(w) && return dayname(1)
    f(w) |> trunc |> Int |> dayname
end

@doc """ Computes the average day of the month for trades of an asset instance.

$(TYPEDSIGNATURES)

Calculates the average day of the month for trades for an `InstrumentInstance` `ii`.
The function `f` is used to aggregate the days and defaults to the mean.

"""
function trades_monthday(ii::InstrumentInstance; f=mean)
    w = dayofmonth.(getproperty.(ii.history, :date))
    isempty(w) && return 1
    f(w) |> trunc |> Int
end

macro cumbal()
    ex = quote
        let bal = trades_balance(ii; tf=first(_ohlcv_keys(ii)))
            isnothing(bal) ? nothing : bal.cum_total
        end
    end
    esc(ex)
end

function trades_drawdown(ii::InstrumentInstance; cum_bal=@cumbal(), kwargs...)
    isnothing(cum_bal) && return (; dd=NaN, ath=NaN, atl=NaN)
    isempty(cum_bal) && return (; dd=NaN, ath=NaN, atl=NaN)
    length(cum_bal) == 1 && return (; dd=zero(DFT), ath=first(cum_bal), atl=first(cum_bal))
    ath = atl = first(cum_bal)
    dd = zero(eltype(cum_bal))
    for v in cum_bal
        if v > ath
            ath = v
        elseif v < atl
            atl = v
        end
        if ath != zero(ath)
            this_dd = (ath - v) / ath
            if this_dd > dd
                dd = this_dd
            end
        end
    end
    (; dd, atl, ath)
end

function trades_pnl(returns; f=mean)
    losses = (v for v in returns if isfinite(v) && v <= 0.0)
    gains = (v for v in returns if isfinite(v) && v > 0.0)
    # Default for an empty partition must match the aggregator's result type.
    # `default_value(f)` returns `nothing` for aggregators without a zero-arg
    # method (e.g. `median`, `extrema`), which would:
    #   - leak `nothing` into the numeric stats DataFrame (mean/median case), or
    #   - crash with `nothing[1]` when the caller indexes an `extrema` tuple.
    # A strategy with only wins (or only losses) is realistic, so handle it.
    T = eltype(returns)
    empty_default = f isa typeof(extrema) ? (zero(T), zero(T)) : zero(T)
    fname = string(nameof(f))
    NamedTuple((
        Symbol(fname, "_loss") => isempty(losses) ? empty_default : f(losses),
        Symbol(fname, "_profit") => isempty(gains) ? empty_default : f(gains),
    ))
end
function trades_pnl(ii::InstrumentInstance; cum_bal=@cumbal(), returns=nothing, kwargs...)
    isnothing(cum_bal) && isnothing(returns) && return (; mean_loss=zero(DFT), mean_profit=zero(DFT))
    if isnothing(returns)
        isnothing(cum_bal) && return (; mean_loss=zero(DFT), mean_profit=zero(DFT))
        returns = _returns_arr(cum_bal)
    end
    isempty(returns) && return (; mean_loss=zero(DFT), mean_profit=zero(DFT))
    trades_pnl(returns; kwargs...)
end

function asset_stats!(res::DataFrame, ii::InstrumentInstance; extended=false)
    # Basic stats that are always computed
    avg_dur = trades_duration(ii; f=mean)
    avg_size = trades_size(ii; f=mean)
    avg_leverage = trades_leverage(ii; f=mean)

    trades = length(ii.history)
    liquidations = count(x -> x isa LiquidationTrade, ii.history)
    longs = count(x -> x isa LongTrade, ii.history)
    shorts = count(x -> x isa ShortTrade, ii.history)
    weekday = trades_weekday(ii; f=mean)
    monthday = trades_monthday(ii; f=mean)

    cum_bal = @cumbal()
    if isnothing(cum_bal)
        drawdown = NaN
        atl = NaN
        ATH = NaN
        returns = DFT[]
        avg_loss = zero(DFT)
        avg_profit = zero(DFT)
        end_balance = zero(DFT)
    else
        drawdown, atl, ATH = trades_drawdown(ii; cum_bal)
        returns = _returns_arr(cum_bal)
        avg_loss, avg_profit = trades_pnl(ii; returns, f=mean)
        end_balance = cum_bal[end]
    end

    # Create base stats dictionary with ordered keys
    stats = OrderedDict(
        :asset => ii.asset.raw,
        :trades => trades,
        :liquidations => liquidations,
        :longs => longs,
        :shorts => shorts,
        :avg_dur => avg_dur,
        :weekday => weekday,
        :monthday => monthday,
        :avg_size => avg_size,
        :avg_leverage => avg_leverage,
        :drawdown => drawdown,
        :ATH => ATH,
        :avg_loss => avg_loss,
        :avg_profit => avg_profit,
        :end_balance => end_balance,
    )

    # Add extended stats if requested
    if extended
        med_dur = trades_duration(ii; f=median)
        min_dur = trades_duration(ii; f=minimum)
        max_dur = trades_duration(ii; f=maximum)

        med_size = trades_size(ii; f=median)
        min_size = trades_size(ii; f=minimum)
        max_size = trades_size(ii; f=maximum)

        med_leverage = trades_leverage(ii; f=median)
        min_leverage = trades_leverage(ii; f=minimum)
        max_leverage = trades_leverage(ii; f=maximum)

        med_loss, med_profit = trades_pnl(ii; returns, f=median)
        loss_ext, profit_ext = trades_pnl(ii; returns, f=extrema)
        max_loss = loss_ext[1]
        max_profit = profit_ext[2]

        # Create new OrderedDict with all stats in the desired order
        stats = OrderedDict(
            :asset => ii.asset.raw,
            :trades => trades,
            :liquidations => liquidations,
            :longs => longs,
            :shorts => shorts,
            :avg_dur => avg_dur,
            :med_dur => med_dur,
            :min_dur => min_dur,
            :max_dur => max_dur,
            :weekday => weekday,
            :monthday => monthday,
            :avg_size => avg_size,
            :med_size => med_size,
            :min_size => min_size,
            :max_size => max_size,
            :avg_leverage => avg_leverage,
            :med_leverage => med_leverage,
            :min_leverage => min_leverage,
            :max_leverage => max_leverage,
            :drawdown => drawdown,
            :ATH => ATH,
            :avg_loss => avg_loss,
            :med_loss => med_loss,
            :avg_profit => avg_profit,
            :med_profit => med_profit,
            :max_loss => max_loss,
            :max_profit => max_profit,
            :end_balance => end_balance,
        )
    end

    push!(res, NamedTuple(stats); promote=false)
    
    # upcast periods for pretty print
    if nrow(res) == 1
        for prop in (:avg, :med, :min, :max)
            prop = Symbol("$(prop)_dur")
            haskey(stats, prop) || continue
            arr = getproperty(res, prop)
            setproperty!(res, prop, convert(Vector{Period}, arr))
        end
    end
end

function trades_stats(s::Strategy; extended=false, since=DateTime(0))
    res = DataFrame()
    for ii in s.universe
        isempty(ii.history) && continue
        if since >= first(ii.history).date
            hist = filter(x -> x.date >= since, copy(ii.history))
            isempty(hist) && continue
            ai_filtered = InstrumentInstance(ii.attrs, ii.asset, ii.data, hist, ii.lock, ii._internal_lock, ii.cash, ii.cash_committed, ii.exchange, ii.longpos, ii.shortpos, ii.lastpos, ii.limits, ii.precision, ii.fees)
            asset_stats!(res, ai_filtered; extended)
        else
            asset_stats!(res, ii; extended)
        end
    end
    res
end

function trades_perf(s::Strategy; sortby=[:drawdown])
    df = trades_stats(s)
    perf = select(df, occursin.(r"asset|drawdown|ATH|loss|profit|end_balance", names(df)))
    sort!(perf, sortby)
end
