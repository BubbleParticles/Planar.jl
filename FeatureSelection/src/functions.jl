using Statistics: quantile, mean, std, var, cov
using Clustering: kmeans, kmedoids
using Distributions: Normal, cdf
using LinearAlgebra: eigen, Symmetric

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
    pairs_trading_signals(prices::Tuple{AbstractVector,AbstractVector}, lookback::Int=20; 
                         zscore_threshold::Float64=2.0)

Generate trading signals for a pairs trading strategy using Z-score with OnlineTechnicalIndicators.

# Arguments
- `prices`: Tuple of (asset1_prices, asset2_prices)
- `lookback`: Lookback period for calculating statistics
- `zscore_threshold`: Z-score threshold for entering trades

# Returns
- A DataFrame with signals (1 for long, -1 for short, 0 for neutral)
"""
function pairs_trading_signals(prices::Tuple{AbstractVector,AbstractVector}, lookback::Int=20; 
                              zscore_threshold::Float64=2.0)
    p1, p2 = prices
    length(p1) != length(p2) && error("Price series must have the same length")
    
    # Calculate spread (price ratio or difference)
    spread = p1 ./ p2
    
    # Initialize indicators
    sma = SMA(period=lookback)
    std_dev = StdDev(period=lookback)
    
    # Initialize arrays to store results
    n = length(spread)
    spread_means = fill(NaN, n)
    spread_stds = fill(NaN, n)
    zscores = fill(NaN, n)
    
    # Calculate rolling statistics using OnlineTechnicalIndicators
    for i in 1:n
        # Update indicators with current spread value
        fit!(sma, spread[i])
        fit!(std_dev, spread[i])
        
        # Only store values once we have enough data
        if i >= lookback
            spread_means[i] = sma.value
            spread_stds[i] = std_dev.value
            
            # Calculate z-score if we have both mean and std
            if !isnan(spread_means[i]) && !isnan(spread_stds[i]) && spread_stds[i] > 0
                zscores[i] = (spread[i] - spread_means[i]) / spread_stds[i]
            end
        end
    end
    
    # Generate signals based on z-scores
    signals = zeros(n)
    for i in 1:n
        if !isnan(zscores[i])
            if zscores[i] > zscore_threshold
                signals[i] = -1  # Short the spread
            elseif zscores[i] < -zscore_threshold
                signals[i] = 1   # Long the spread
            end
            
            # Exit position if z-score is close to zero
            if abs(zscores[i]) < zscore_threshold/2
                signals[i] = 0
            end
        end
    end
    
    return DataFrame(
        timestamp = 1:n,
        spread = spread,
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
    clusters = kmedoids(transpose(features), n_regimes)
    
    # Smooth the regime labels with a rolling window
    smoothed_regimes = zeros(Int, n)
    for i in window:n
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

export sort_col_byrowsum!, quantile_df, cluster_df, find_cointegrated_prices