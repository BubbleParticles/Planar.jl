module MarginStrat
using Planar

const DESCRIPTION = "MarginStrat"
const EXC = :binance
const MARGIN = Isolated
const TF = tf"1d"

@strategyenv!
@contractsenv!

# Load required indicators
# using .Indicators
using OnlineTechnicalIndicators: RSI, EMA

call!(_::SC, ::WarmupPeriod) = Day(27 * 2)

# function qqe(close)
#     ot = RSI(close; period=14) |>
#     (x -> EMA(x; n=5)) |>
#     (x -> abs.(diff(x))) |>
#     (x -> EMA(x; n=27)) |>
#     (x -> EMA(x; n=27)) |>
#     (x -> x .* 4.236) |>
#     (x -> pushfirst!(x, NaN)) # because of `diff`
# end

function online_qqe(close)

    # Step 1: Calculate RSI
    rsi_period = 14
    rsi = RSI{DFT}(; period=rsi_period)
    rsi_values = Float64[]
    for price in close
        oti.fit!(rsi, price)
        push!(rsi_values, value(rsi))
    end

    # Step 2: Smooth RSI with EMA
    smoothed_rsi = EMA{DFT}(; period=5)

    # Step 3: Absolute Change in Smoothed RSI
    abs_change = (x, y) -> abs(x - y)

    # Step 4: Double 27-period EMA on absolute changes
    ema1 = EMA{DFT}(; period=27)
    ema2 = EMA{DFT}(; period=27)

    # Step 5: Multiply by 4.236 for slow trailing line
    slow_trailing_multiplier = 4.236

    oti.fit!(rsi, close)
    oti.fit!(smoothed_rsi, value(rsi))
    change = abs_change(value(smoothed_rsi), prev_smoothed_rsi)
    push!(ema1, change)
    push!(ema2, value(ema1))
    slow_trailing = value(ema2) * slow_trailing_multiplier

    # Main QQE line: value(smoothed_rsi)
    # Slow trailing line: slow_trailing

end

function qqe!(ohlcv, from_date)
    ohlcv = viewfrom(ohlcv, from_date; offset=-27 * 2)
    # shift by one to avoid lookahead # FIXME: this should not be needed
    [qqe(ohlcv.close);;] # it's a matrix
end

function call!(s::SC{<:ExchangeID,Sim}, ::ResetStrategy)
    call!(qqe!, s, InitData(); cols=(:qqe,), timeframe=tf"1d")
    @assert hasproperty(ohlcv(first(s.universe), tf"1d"), :qqe) "is ohlcv at 1d timeframe available?"
end

function handler(s, ai, ats, date)
    # Calculate QQE indicator
    call!(qqe!, s, ai, UpdateData(); cols=(:qqe,))

    data = ohlcv(ai, tf"1d")
    # Get trend direction
    v = data[ats, :qqe]
    trend = if v > 13.22
        -1
    elseif v < 8.96
        1
    else
        0
    end

    # Get current exposure
    pos = position(ai)
    exposure = pos === nothing ? 0.0 : cash(pos)
    # If the position is short, the value is negative
    @assert iszero(exposure) ||
        islong(pos) && exposure >= 0.0 ||
        isshort(pos) && exposure <= 0.0

    # Define constants
    target_size = ai.limits.cost.min * 10.0

    if trend > 0.0
        # Calculate target position size
        price = closeat(data, ats)
        target_pos = target_size / price

        # Calculate trade amount needed
        amount = target_pos - exposure

        if exposure < 0.0
            # close long position
            call!(s, ai, Short(), date, PositionClose())
        end

        # This check is not necessary, since the bot
        # validates the inputs. Calling call! with an amount too low
        # would make the call return `nothing`.
        if amount * price > ai.limits.cost.min
            call!(s, ai, MarketOrder{Buy}; amount=amount, date)
        end

    elseif trend < 0.0
        # Calculate target position size
        price = closeat(data, ats)
        target_pos = -target_size / price

        # Calculate trade size needed
        amount = target_pos + exposure

        if exposure > 0.0
            # close long position
            call!(s, ai, Long(), date, PositionClose())
        end

        if amount * price < -ai.limits.cost.min
            # Submit sell order
            call!(s, ai, ShortMarketOrder{Sell}; amount, date)
        end
    end
end

function call!(s::SC, ts::DateTime, ctx)
    ats = available(s.timeframe, ts)
    foreach(s.universe) do ai
        handler(s, ai, ats, ts)
    end
end

function call!(::Type{<:Union{SC,S}}, ::StrategyMarkets)
    ["BTC/USDT:USDT"]
end

end # module
