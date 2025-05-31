using Statistics: mean, std, cov
using Strategies.Data.DataFrames: DataFrame
using Strategies: asset_bysym, DateTime
using Strategies.Lang: @lget!

# --- Pairs Trading State and Functions ---

mutable struct PairsTradingState{T<:AbstractFloat}
    timestamp::DateTime
    sma::SMA{T}
    stddev::StdDev{T}
    df::DataFrame
    function PairsTradingState(timestamp::DateTime, lookback::Int, df::DataFrame=DataFrame(timestamp=T[], spread=T[], spread_mean=T[], spread_std=T[], zscore=T[], signal=T[]))
        new{T}(timestamp, SMA{T}(period=lookback), StdDev{T}(period=lookback), df)
    end
end

"""
    pairs_trading_signal_step(price1, price2, sma, std_dev; lookback=20, zscore_threshold=2.0)

Streaming step for pairs trading signal generation. Updates indicators with the latest prices and returns the signal and stats.

# Arguments
- `price1`, `price2`: Latest prices for asset 1 and asset 2
- `sma`, `std_dev`: OnlineTechnicalIndicators SMA and StdDev objects (stateful)
- `lookback`: Lookback period for statistics
- `zscore_threshold`: Z-score threshold for entering trades

# Returns
- `(signal, zscore, mean, std)`: Signal (+1, -1, 0), z-score, mean, std

# Example
```julia
sma = SMA{DFT}(period=20)
std_dev = StdDev{DFT}(period=20)
for (p1, p2) in zip(prices1, prices2)
    signal, z, m, s = pairs_trading_signal_step(p1, p2, sma, std_dev; lookback=20, zscore_threshold=2.0)
end
```
"""
function pairs_trading_signal_step(price1, price2, sma, std_dev; lookback=20, zscore_threshold=2.0)
    spread = price1 / price2
    fit!(sma, spread)
    fit!(std_dev, spread)
    if sma.n >= lookback && std_dev.n >= lookback && std_dev.value > 0
        z = (spread - sma.value) / std_dev.value
        if abs(z) < zscore_threshold/2
            signal = 0
        elseif z > zscore_threshold
            signal = -1
        elseif z < -zscore_threshold
            signal = 1
        else
            signal = 0
        end
        return signal, z, sma.value, std_dev.value
    else
        return 0, NaN, NaN, NaN
    end
end

"""
    pairs_trading_signals(prices::Tuple{AbstractVector,AbstractVector}, lookback::Int=20; 
                         zscore_threshold::Float64=2.0, tail=nothing)

Generate trading signals for a pairs trading strategy using Z-score with OnlineTechnicalIndicators.
Supports both batch and streaming (online) operation.

# Arguments
- `prices`: Tuple of (asset1_prices, asset2_prices)
- `lookback`: Lookback period for calculating statistics
- `zscore_threshold`: Z-score threshold for entering trades
- `tail`: If provided, only the last `tail` prices are used (default: nothing, use all)

# Returns
- A DataFrame with signals (1 for long, -1 for short, 0 for neutral)
"""
function pairs_trading_signals(prices::Tuple{AbstractVector,AbstractVector}, lookback::Int=20; 
                              zscore_threshold::Float64=2.0, tail=nothing)
    p1, p2 = prices
    length(p1) != length(p2) && error("Price series must have the same length")
    if tail !== nothing
        p1 = @view p1[end-tail+1:end]
        p2 = @view p2[end-tail+1:end]
    end
    n = length(p1)
    # Initialize indicators
    sma = SMA{DFT}(period=lookback)
    std_dev = StdDev{DFT}(period=lookback)
    spread_means = fill(NaN, n)
    spread_stds = fill(NaN, n)
    zscores = fill(NaN, n)
    signals = zeros(n)
    for i in 1:n
        signal, z, m, s = pairs_trading_signal_step(p1[i], p2[i], sma, std_dev; lookback=lookback, zscore_threshold=zscore_threshold)
        signals[i] = signal
        zscores[i] = z
        spread_means[i] = m
        spread_stds[i] = s
    end
    return DataFrame(
        timestamp = 1:n,
        spread = p1 ./ p2,
        spread_mean = spread_means,
        spread_std = spread_stds,
        zscore = zscores,
        signal = signals
    )
end

"""
    pairs_trading_signals(s::Strategy, asset1_sym::AbstractString, asset2_sym::AbstractString; 
                         lookback::Int=20, zscore_threshold::Float64=2.0, tf::TimeFrame=s.timeframe, tail=lagsbytf(tf))

Generate trading signals for a pairs trading strategy using Z-score, pulling data from a strategy instance.

# Arguments
- `s`: Strategy instance containing the asset data
- `asset1_sym`: String symbol for the first asset
- `asset2_sym`: String symbol for the second asset
- `lookback`: Lookback period for calculating statistics
- `zscore_threshold`: Z-score threshold for entering trades
- `tf`: TimeFrame to use for OHLCV data (defaults to strategy's timeframe)
- `tail`: If provided, only the last `tail` prices are used (default: lagsbytf(tf))

# Returns
- A DataFrame with signals (1 for long, -1 for short, 0 for neutral)
"""
function pairs_trading_signals(s::st.Strategy, asset1_sym::AbstractString, asset2_sym::AbstractString; 
                              lookback::Int=20, zscore_threshold::Float64=2.0, tf::TimeFrame=s.timeframe, tail=lagsbytf(tf))
    # Get asset instances from strategy
    ai1 = asset_bysym(s, asset1_sym)
    ai2 = asset_bysym(s, asset2_sym)
    # Check if assets exist in strategy
    isnothing(ai1) && error("Asset $asset1_sym not found in strategy")
    isnothing(ai2) && error("Asset $asset2_sym not found in strategy")
    # Get price data from asset instances at specified timeframe
    df1 = ai1.data[tf]
    df2 = ai2.data[tf]
    # Apply tail if provided (before computing common_dates)
    if tail !== nothing
        df1 = @view df1[end-tail+1:end, :]
        df2 = @view df2[end-tail+1:end, :]
    end
    # Find common dates between both assets
    common_dates = intersect(df1.timestamp, df2.timestamp)
    isempty(common_dates) && error("No common dates found between assets")
    # Align the price series
    p1 = @view df1[df1.timestamp .∈ (common_dates,), :close]
    p2 = @view df2[df2.timestamp .∈ (common_dates,), :close]
    # Verify alignment
    length(p1) == length(p2) || error("Price series have different lengths after alignment")
    # Call the base function with the aligned price data
    df = pairs_trading_signals((p1, p2), lookback; zscore_threshold)
    df.timestamp = common_dates
    return df
end

"""
    pairs_trading_signal_step!(state::PairsTradingState, ts_idx, price1, price2; lookback=20, zscore_threshold=2.0)

Streaming step for pairs trading signal generation. Updates indicators and appends a new row to the state's DataFrame.

# Arguments
- `state`: PairsTradingState instance
- `ts_idx`: Timestamp or index for the new row
- `price1`, `price2`: Latest prices for asset 1 and asset 2
- `lookback`: Lookback period for statistics
- `zscore_threshold`: Z-score threshold for entering trades
"""
function pairs_trading_signal_step!(state::PairsTradingState, ts_idx, price1, price2; lookback=20, zscore_threshold=2.0)
    spread = price1 / price2
    fit!(state.sma, spread)
    fit!(state.stddev, spread)
    state.timestamp = ts_idx
    if state.sma.n >= lookback && state.stddev.n >= lookback && state.stddev.value > 0
        z = (spread - state.sma.value) / state.stddev.value
        if abs(z) < zscore_threshold/2
            signal = 0
        elseif z > zscore_threshold
            signal = -1
        elseif z < -zscore_threshold
            signal = 1
        else
            signal = 0
        end
        push!(state.df, (ts_idx, spread, state.sma.value, state.stddev.value, z, signal))
    else
        push!(state.df, (ts_idx, spread, NaN, NaN, NaN, 0.0))
    end
    return state
end

function pairs_trading_state(s::st.Strategy, asset1_sym::AbstractString, asset2_sym::AbstractString)
    pairs_dict = @lget! s :pairs_trading Dict{Tuple{String,String}, PairsTradingState}()
    key = (asset1_sym, asset2_sym)
    return get!(pairs_dict, key) do
        PairsTradingState(ts_idx, lookback)
    end
end

# Update the strategy-based step function to use the state
function pairs_trading_signal_step!(s, asset1_sym, asset2_sym, ts_idx; lookback=20, zscore_threshold=2.0, tf=s.timeframe)
    state = pairs_trading_state(s, asset1_sym, asset2_sym)
    ai1 = asset_bysym(s, asset1_sym)
    ai2 = asset_bysym(s, asset2_sym)
    isnothing(ai1) && return nothing
    isnothing(ai2) && return nothing
    df1 = ai1.data[tf]
    df2 = ai2.data[tf]
    # This uses dataframes indexing based on dates defined in Data.DFUtils
    idx1 = @view df1[ts_idx, :]
    idx2 = @view df2[ts_idx, :]
    if isnothing(idx1) || isnothing(idx2)
        @warn "pairs_trading_signal_step! no data for $asset1_sym or $asset2_sym at $ts_idx"
        return state
    end
    price1 = idx1.close
    price2 = idx2.close
    pairs_trading_signal_step!(state, ts_idx, price1, price2; lookback=lookback, zscore_threshold=zscore_threshold)
    return state
end 