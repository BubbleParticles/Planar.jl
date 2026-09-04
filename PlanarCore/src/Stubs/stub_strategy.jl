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

# Generic markets for any margin/exchange (covers Isolated/Cross tests via SC)
function call!(::Type{<:SC{E,M,R}}, ::StrategyMarkets) where {E,M,R}
    call!(S, StrategyMarkets())
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

# Generic LoadStrategy for SC (any margin) — delegates to S
function call!(t::Type{<:SC{E,M,R}}, config, ::LoadStrategy) where {E,M,R}
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
# Generic warmup for any margin
call!(_::SC{E,M,R}, ::WarmupPeriod) where {E,M,R} = Day(1)

# Explicit lifecycle no-ops for completeness (avoid @warn fallback in Paper/Live)
call!(_::S, ::Strategies.StartStrategy) = nothing
call!(_::SC{E,M,R}, ::Strategies.StartStrategy) where {E,M,R} = nothing
call!(_::S, ::Strategies.StopStrategy) = nothing
call!(_::SC{E,M,R}, ::Strategies.StopStrategy) where {E,M,R} = nothing
call!(_::S, ::Strategies.ResetStrategy) = nothing
call!(_::SC{E,M,R}, ::Strategies.ResetStrategy) where {E,M,R} = nothing

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

# Generic execution for any margin (Isolated/Cross); delegates to NoMargin logic
# Uses try/catch to never throw out of strategy main loop
function call!(s::SC{E,M,R}, ts::DateTime, ctx) where {E,M,R}
    try
        # Reuse S logic with safe guards
        date = ts
        foreach(s.universe) do ii
            try
                if isopen(ii)
                    if rand(RNG, Bool)
                        call!(s, ii, MarketOrder{Sell}; amount=cash(ii), date)
                    end
                elseif cash(s) > ii.limits.cost.min && rand(RNG, Bool)
                    amt = max(ii.limits.amount.min, ii.limits.cost.min / closeat(ii, ts))
                    call!(s, ii, MarketOrder{Buy}; amount=amt, date)
                end
            catch e
                e isa InterruptException && rethrow(e)
                @error "StubStrategy: per-asset call! failed for $(ii.asset.bc)" exception=(e, catch_backtrace())
            end
        end
    catch e
        e isa InterruptException && rethrow(e)
        @error "StubStrategy: call! failed at $ts" exception=(e, catch_backtrace())
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
