module SimpleStrategy
using Planar
const DESCRIPTION = "SimpleStrategy"
const EXC = :binance
const MARGIN = NoMargin
const TF = tf"1d"
@strategyenv!
using .Engine.Simulations: mean
function call!(t::Type{<:SC}, config, ::LoadStrategy)
    config.min_timeframe = tf"1d"
    config.timeframes = [tf"1d"]
    st.default_load(@__MODULE__, t, config)
end
function call!(s::SC, ::ResetStrategy)
    call!(s, WatchOHLCV())
end
function call!(_::SC, ::WarmupPeriod)
    Day(15)
end
function call!(s::SC, ts::DateTime, _)
    ats = available(s.timeframe, ts)
    foreach(s.universe) do ai
        df = ohlcv(ai)
        idx = dateindex(df, ats)
        if idx > 15
            ma7d = mean(@view df.close[(idx - 7):idx])
            ma15d = mean(@view df.close[(idx - 15):idx])
            side = ifelse(ma7d > ma15d, Buy, Sell)
            call!(s, ai, MarketOrder{side}; date=ts, amount=0.001)
        end
    end
end
const ASSETS = ["BTC/USDT"]
function call!(::Union{<:SC,Type{<:SC}}, ::StrategyMarkets)
    ASSETS
end
end
