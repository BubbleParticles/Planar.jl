using Statistics: quantile, mean, std, var, cov
using Clustering: kmeans, kmedoids
using Distributions: Normal, cdf
using LinearAlgebra: eigen, Symmetric
using Distances: pairwise, Euclidean
using StatsBase: mode
using Strategies: asset_bysym
using Strategies: DateTime
using Strategies.Lang: @lget!

mutable struct PairsTradingState{T<:AbstractFloat}
    timestamp::DateTime
    sma::SMA{T}
    stddev::StdDev{T}
    df::DataFrame
    function PairsTradingState(timestamp::DateTime, lookback::Int, df::DataFrame=DataFrame(timestamp=T[], spread=T[], spread_mean=T[], spread_std=T[], zscore=T[], signal=T[]))
        new{T}(timestamp, SMA{T}(period=lookback), StdDev{T}(period=lookback), df)
    end
end

function sort_col_byrowsum!(df)
    # first calculate row sum
    rowsums = sum.(abs.(v) for v in eachcol(df))
    # then sort by row sum
    indices = sortperm(rowsums)
    select!(df, indices)
end

# a function that quantiles a dataframe
function quantile_df(df, q)
    sort_col_byrowsum!(df)
    ans = DFT[]
    for row in eachrow(df)
        push!(ans, quantile(row, q))
    end
    return ans
end

function cluster_df(df, n=2)
    idx = kmeans(Matrix(df), n).assignments
    colnames = names(df)
    groups = []
    for i in 1:n
        push!(groups, colnames[idx .== i])
    end
    return groups
end

"""
    find_lead_lag_pairs(corr_dict::Dict, threshold::Float64=0.7; max_lag::Int=3)

Identify lead-lag relationships between assets based on cross-correlation.

# Arguments
- `corr_dict`: Dictionary of correlation DataFrames with lags as keys
- `threshold`: Minimum absolute correlation to consider a relationship
- `max_lag`: Maximum lag to consider for lead-lag relationships

# Returns
- A DataFrame with columns [:asset1, :asset2, :lag, :correlation] showing significant lead-lag pairs
"""
function find_lead_lag_pairs(corr_dict::Dict, threshold::Float64=0.7; max_lag::Int=3)
    pairs = DataFrame(asset1=String[], asset2=String[], lag=Int[], correlation=Float64[])
    
    for (lag, df) in corr_dict
        abs(lag) > max_lag && continue
        
        x_assets = metadata(df, "x_assets")
        y_assets = names(df)
        
        for (i, y_asset) in enumerate(y_assets)
            for (j, x_asset) in enumerate(x_assets)
                corr_val = df[i, j]
                if abs(corr_val) >= threshold
                    push!(pairs, (x_asset, y_asset, lag, corr_val))
                end
            end
        end
    end
    
    return sort(pairs, :correlation, rev=true)
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
    detect_correlation_regime(corr_matrix::AbstractMatrix, window::Int=20; n_regimes::Int=2)

Detect market regimes based on changes in correlation structure.

# Arguments
- `corr_matrix`: Time series of correlation matrices (3D array or vector of matrices)
- `window`: Rolling window for regime detection
- `n_regimes`: Number of regimes to detect

# Returns
- A vector of regime labels for each time period
"""
function detect_correlation_regime(corr_matrices::AbstractArray, window::Int=20; n_regimes::Int=2)
    n = size(corr_matrices, 3)
    features = zeros(n, size(corr_matrices, 1) * size(corr_matrices, 2))
    
    # Flatten correlation matrices into feature vectors
    for i in 1:n
        features[i, :] = vec(corr_matrices[:, :, i])
    end
    
    # Use k-medoids for regime detection
    dist = pairwise(Euclidean(), features; dims=2)
    clusters = kmedoids(dist, n_regimes)

    # Smooth the regime labels with a rolling window
    smoothed_regimes = ones(Int, n)
    for i in window:size(dist, 1)
        window_regimes = clusters.assignments[(i-window+1):i]
        smoothed_regimes[i] = mode(window_regimes)
    end
    
    # Fill the beginning with the first detected regime
    smoothed_regimes[1:window-1] .= smoothed_regimes[window]
    
    return smoothed_regimes
end

"""
    find_cointegrated_pairs(prices::Dict{String,Vector{Float64}}; pvalue_threshold::Float64=0.05)

Find cointegrated pairs of assets using the Engle-Granger test.

# Arguments
- `prices`: Dictionary of price series with asset names as keys
- `pvalue_threshold`: Maximum p-value to consider a pair cointegrated

# Returns
- A DataFrame with cointegrated pairs and test statistics
"""
function find_cointegrated_prices(prices::Dict{String,Vector{Float64}}; pvalue_threshold::Float64=0.05)
    assets = collect(keys(prices))
    n = length(assets)
    results = DataFrame(
        asset1=String[], asset2=String[], 
        coint_pvalue=Float64[], adf_pvalue=Float64[], 
        half_life=Float64[]
    )
    
    for i in 1:(n-1)
        for j in (i+1):n
            asset1, asset2 = assets[i], assets[j]
            p1, p2 = prices[asset1], prices[asset2]
            
            # Test for cointegration using Engle-Granger test
            # (Implementation depends on your statistical package)
            # This is a placeholder - replace with actual cointegration test
            coint_pvalue = 0.0  # Replace with actual test
            
            if coint_pvalue < pvalue_threshold
                # Calculate half-life of mean reversion
                spread = p1 .- p2
                spread_lag = [NaN; spread[1:end-1]]
                delta = spread[2:end] .- spread_lag[2:end]
                beta = cov(delta, spread_lag[2:end]) / var(spread_lag[2:end])
                half_life = -log(2) / beta
                
                # Add to results
                push!(results, (asset1, asset2, coint_pvalue, 0.0, half_life))
            end
        end
    end
    
    return sort(results, :coint_pvalue)
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

export sort_col_byrowsum!, quantile_df, cluster_df, find_cointegrated_prices, pairs_trading_signals