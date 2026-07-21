module TwoParameters
using Planar
const DESCRIPTION = "TwoParameters"
const EXC = :okx
const MARGIN = NoMargin
const TF = tf"15m"
@strategyenv!
using OnlineTechnicalIndicators: RSI, EMA, fit!

SignalD = Dict{inst.AssetInstance,Union{Type{Buy},Type{Sell},Nothing}}

function indicators!(s, args...; timeframe=tf"15m")
    for (n, func) in s[:params]
        call!(
            (args...) -> func(args...; n),
            s,
            args...;
            cols=(Symbol(nameof(func), n),),
            timeframe,
        )
    end
end
function call!(t::Type{<:SC}, config, ::LoadStrategy)
    config.min_timeframe = tf"15m"
    config.timeframes = [tf"15m", tf"1h", tf"1d"]
    st.default_load(@__MODULE__, t, config)
end
function call!(s::SC, ::ResetStrategy)
    s[:signals] = SignalD()
    s[:params] = ((20, ind_ema), (40, ind_ema), (14, ind_rsi))
    indicators!(s, InitData())
end
function call!(_::SC, ::WarmupPeriod)
    Hour(80)
end
function call!(s::SC, ts::DateTime, _)
    ats = available(s.timeframe, ts)
    signals = s[:signals]
    foreach(s.universe) do ai
        indicators!(s, ai, UpdateData())
        signals[ai] = signal(s, ai, ats)
    end
    action = resolve(signals)
    if isnothing(action)
        return nothing
    end
    eth = s[m"eth"]
    @linfo 1 "Resolved signal" action sym = raw(eth)
    price = closeat(ohlcv(eth, s.timeframe), ats)
    closed = isdust(eth, price)
    if action == Buy && closed
        amount = freecash(s) / price - maxfees(eth)
        call!(s, eth, MarketOrder{Buy}; date=ts, amount)
    elseif action == Sell && !closed
        call!(s, eth, CancelOrders())
        call!(s, eth, MarketOrder{Sell}; date=ts, amount=float(eth))
    end
end
function call!(::Type{<:SC}, ::StrategyMarkets)
    String["BTC/USDT", "ETH/USDT"]
end

function signal(s, ai, ats)
    data = ohlcv(ai, tf"15m")
    idx = dateindex(data, ats)
    ind_ema_short = data.ind_ema20[idx]
    ind_ema_long = data.ind_ema40[idx]
    ind_rsi = data.ind_rsi14[idx]
    if ind_ema_short > ind_ema_long && ind_rsi < 40
        Buy
    elseif ind_ema_short < ind_ema_long && ind_rsi > 60
        Sell
    end
end

function resolve(signals)
    vals = values(signals)
    if all(v == Buy for v in vals)
        Buy
    elseif all(v == Sell for v in vals)
        Sell
    end
end

function ind_ema(ohlcv, from_date; n)
    ohlcv = viewfrom(ohlcv, from_date; offset=-n)
    ema = EMA{DFT}(period=n)
    vec = Union{Missing,DFT}[]
    for price in ohlcv.close
        fit!(ema, price)
        push!(vec, ema.value)
    end
    [vec;;]
end
function ind_rsi(ohlcv, from_date; n=14)
    @assert timeframe!(ohlcv) == tf"15m"
    ohlcv = viewfrom(ohlcv, from_date; offset=-n)
    rsi = RSI{DFT}(period=n)
    vec = Union{Missing,DFT}[]
    for price in ohlcv.close
        fit!(rsi, price)
        push!(vec, rsi.value)
    end
    [vec;;]
end
end
