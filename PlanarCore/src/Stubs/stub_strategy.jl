module StubStrategy

using ..Stubs.Misc
using ..Stubs.TimeTicks
using ..SimMode.Strategies.Data
using ..SimMode.Strategies.Data.DFUtils
using ..SimMode.Strategies.Data.DataFrames

using ..Strategies
using ..Strategies.Instances.Instruments
using ..Strategies: Strategies as st
using ..Strategies.Exchanges.ExchangeTypes
using ..Strategies: Instances as inst
using ..SimMode.Executors
using ..SimMode.Executors: Executors, Executors as ect
using ..Strategies.OrderTypes
using ..SimMode.OrderTypes: BySide, ByPos

using ..Lang
using Random

const RNG = Random.default_rng()

# # NOTE: do not export anything
Strategies.@interface

const DESCRIPTION = "Strategy to generate stub data"
const EXC = :binanceusdm
const EXCID = ExchangeID(EXC)
const S{M} = Strategy{M,nameof(@__MODULE__),typeof(EXCID),NoMargin}
const SC{E,M,R} = Strategy{M,nameof(@__MODULE__()),E,R}
const TF = tf"1m"

# function __init__() end

function call!(::Type{<:S}, ::StrategyMarkets)
    ["ETH/USDT:USDT", "BTC/USDT:USDT", "SOL/USDT:USDT"]
end

function call!(t::Type{<:S}, config, ::LoadStrategy)
    syms = call!(S, StrategyMarkets())
    exc = st.Exchanges.getexchange!(config.exchange; sandbox=true)
    uni = st.InstrumentCollection(syms; load_data=false, timeframe=TF, exc, config.margin)
    s = Strategy(@__MODULE__, config.mode, config.margin, TF, exc, uni; config)
    s.attrs[:buydiff] = 1.01
    s.attrs[:selldiff] = 1.005
    s
end

call!(_::S, ::WarmupPeriod) = begin
    Day(1)
end

function call!(s::S, ts::DateTime, ctx)
    date = ts
    foreach(s.universe) do ii
        if isopen(ii)
            if rand(RNG, Bool)
                call!(s, ii, MarketOrder{Sell}; amount=cash(ii), date)
            end
        elseif cash(s) > ii.limits.cost.min && rand(RNG, Bool)
            call!(
                s,
                ii,
                MarketOrder{Buy};
                amount=max(ii.limits.amount.min, ii.limits.cost.min / closeat(ii, ts)),
                date,
            )
        end
    end
end

function buy!(s::S, ii, ats, ts)
    call!(s, ii, ect.CancelOrders(); t=Sell)
    @deassert ii.asset.qc == nameof(s.cash)
    price = closeat(ii.ohlcv, ats)
    amount = st.freecash(s) / 10.0 / price
    if amount > 0.0
        t = call!(s, ii, IOCOrder{Buy}; amount, date=ts)
    end
end

function sell!(s::S, ii, ats, ts)
    call!(s, ii, ect.CancelOrders(); t=Buy)
    amount = max(inv(closeat(ii, ats)), inst.freecash(ii))
    price = closeat(ii.ohlcv, ats)
    if amount > 0.0
        t = call!(s, ii, IOCOrder{Sell}; amount, date=ts)
    end
end

end
