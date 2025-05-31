module OnlineCrossCorr

using Strategies: Strategies as st, DFT, DateTime, @lget!
using ..FeatureSelection: center_data, ratio!, lagsbytf, tickers, raw, metadata, DataFrame, roc_to_ratio
using .st.Data.DataFrames: DataFrame, select!, metadata!
using OnlineTechnicalIndicators: ROC, OnlineTechnicalIndicators as oti
export OnlineCrossCorrelation, fit!, value, crosscorr_assets_online

mutable struct OnlineCrossCorrelation{T}
    window::Int # Window size for rolling or total size for batch
    xbuf::Vector{T}
    ybuf::Vector{T}
    sumx::T
    sumy::T
    sumxx::T
    sumyy::T
    sumxy::T
    idx::Int
    count::Int # Total count of data points received in this instance
    demean::Bool
    date::DateTime # Timestamp of the last fitted data point
    x_roc_calculator::ROC{T}
    y_roc_calculator::ROC{T}
end

function OnlineCrossCorrelation(window::Int, roc_period::Int, T::Type=DFT; demean::Bool=true)
    OnlineCrossCorrelation{T}(window, zeros(T, window), zeros(T, window),
        zero(T), zero(T), zero(T), zero(T), zero(T), 1, 0, demean, DateTime(0),
        ROC{T}(period=roc_period), ROC{T}(period=roc_period))
end

function fit!(occ::OnlineCrossCorrelation{T}, x_price::T, y_price::T, timestamp::DateTime) where {T}
    # Fit the internal ROC calculators with raw prices
    oti.fit!(occ.x_roc_calculator, x_price)
    oti.fit!(occ.y_roc_calculator, y_price)

    # Get the ratio values from the fitted ROCs
    x_ratio_val = if !ismissing(occ.x_roc_calculator.value) && isfinite(occ.x_roc_calculator.value)
                      (occ.x_roc_calculator.value >= 0) ? (1.0 + occ.x_roc_calculator.value) : (1.0 / (1.0 - occ.x_roc_calculator.value))
                  else
                      NaN
                  end

    y_ratio_val = if !ismissing(occ.y_roc_calculator.value) && isfinite(occ.y_roc_calculator.value)
                      (occ.y_roc_calculator.value >= 0) ? (1.0 + occ.y_roc_calculator.value) : (1.0 / (1.0 - occ.y_roc_calculator.value))
                  else
                      NaN
                  end

    # Only update cross-correlation buffers if both ratio values are valid
    if !ismissing(x_ratio_val) && !ismissing(y_ratio_val) && isfinite(x_ratio_val) && isfinite(y_ratio_val)
        # If buffer is full (count reached window size), remove the oldest data point
        if occ.count == occ.window
            xold, yold = occ.xbuf[occ.idx], occ.ybuf[occ.idx]
            occ.sumx -= xold
            occ.sumy -= yold
            occ.sumxx -= xold^2
            occ.sumyy -= yold^2
            occ.sumxy -= xold * yold
        else
            # Only increment count if still filling the initial window
            occ.count += 1
        end
        # Add new data point to the circular buffer
        occ.xbuf[occ.idx] = x_ratio_val
        occ.ybuf[occ.idx] = y_ratio_val
        # Update sums with the new data point
        occ.sumx += x_ratio_val
        occ.sumy += y_ratio_val
        occ.sumxx += x_ratio_val^2
        occ.sumyy += y_ratio_val^2
        occ.sumxy += x_ratio_val * y_ratio_val
        # Move the circular buffer index
        occ.idx = occ.idx % occ.window + 1
        # Update the last fitted date
        occ.date = timestamp
    end
    return occ
end

function value(occ::OnlineCrossCorrelation, lag::Integer=0)
    n = occ.count # Use the current count of data points in the window/buffer
    if n < 2 || abs(lag) >= n
        return NaN
    end
    # Get the current buffer content in order, up to the current count
    x = circbuf_to_vec(occ.xbuf, occ.idx, n)
    y = circbuf_to_vec(occ.ybuf, occ.idx, n)

    if lag < 0
        xview = @view x[1:end+lag]
        yview = @view y[1-lag:end]
    elseif lag > 0
        xview = @view x[1+lag:end]
        yview = @view y[1:end-lag]
    else
        xview = x
        yview = y
    end

    # Calculate correlation over the lagged view of the current data in buffer
    return _cor(xview, yview, occ.demean)
end

function value(occ::OnlineCrossCorrelation, lags::AbstractVector{<:Integer})
    [value(occ, lag) for lag in lags]
end

# Helper: convert circular buffer to ordered vector
function circbuf_to_vec(buf, idx, n)
    if n == 0
        return eltype(buf)[]
    end
     # This logic correctly handles extracting up to 'n' elements from the circular buffer 'buf'
     # starting from 'idx'. If n is the full buffer size, it gets all; if n is less, it gets the recent 'n'.
    if idx == 1
        return buf[1:n]
    else
        # Handle wrap-around: take from idx to end, then from beginning up to needed elements
        len_from_idx = length(buf) - idx + 1
        if n <= len_from_idx
            return buf[idx:idx+n-1]
        else
            return vcat(buf[idx:end], buf[1:n-len_from_idx])
        end
    end
end

# Helper: correlation for two vectors, with/without demeaning
function _cor(x, y, demean)
    n = length(x)
    if n < 2
        return NaN
    end
    if demean
        # These sums are over the input vectors x, y (the views)
        sx = sum(x)
        sy = sum(y)
        sxx = sum(abs2, x)
        syy = sum(abs2, y)
        sxy = sum(x .* y)
        # Using (sum of products - sum x * sum y / n) / (n-1) (Bessel's correction for sample covariance)
        denom = n > 1 ? n - 1 : n # Avoid division by zero for n=1
        covxy = (sxy - sx * sy / n) / denom
        # Using (sum of squares - (sum)^2 / n) / (n-1) (Bessel's correction for sample variance)
        varx = (sxx - sx^2 / n) / denom
        vary = (syy - sy^2 / n) / denom
    else
        # Using sum of products / n
        covxy = sum(x .* y) / n
        # Using sum of squares / n
        varx = sum(abs2, x) / n
        vary = sum(abs2, y) / n
    end
    if varx <= 0 || vary <= 0
        return NaN
    end
    return covxy / sqrt(varx * vary)
end

# Helper function to get filtered assets and split into x and y
function _get_filtered_assets(s, tf, min_vol, x_num)
    local_assets_dict = st.symsdict(s)
    if isempty(local_assets_dict)
        # Fill with the strategy's assets
        for ai in s.universe
            local_assets_dict[raw(ai)] = ai
        end
    end

    assets = let vec = tickers(st.getexchange!(s.exchange), s.qc; min_vol=min_vol, as_vec=true)
        [el for el in vec if haskey(local_assets_dict, el)]
    end

    # Check if there are enough assets to form x_assets and y_assets
    if length(assets) <= x_num
         @warn "Not enough assets ($(length(assets))) to select $x_num x_assets and remaining y_assets."
         return nothing, nothing, nothing # Indicate failure
    end

    # Ensure x_num is not negative and does not exceed the number of assets
    effective_x_num = max(0, min(x_num, length(assets)))

    # Split assets: y_assets get the first part, x_assets get the last part
    y_assets = assets[begin:(end - effective_x_num)]
    x_assets = assets[(end - effective_x_num + 1):end]

    # Check if there are enough assets for x and y
    if length(x_assets) == 0 || length(y_assets) == 0
         @warn "Not enough assets ($length(assets)) to select $x_num x_assets and remaining y_assets."
         return nothing, nothing, nothing # Indicate failure
    end

    return x_assets, y_assets, local_assets_dict
end

# Helper function to get and align OHLCV data
function _get_aligned_ohlcv_data(s, tf, assets, local_assets_dict)
    # Collect dataframes for relevant assets and timeframe
    # Use the local_assets_dict which points to the strategy's asset dictionary
    asset_dfs = Dict(asset_name => local_assets_dict[asset_name].data[tf] for asset_name in assets if haskey(local_assets_dict[asset_name].data, tf) && !isempty(local_assets_dict[asset_name].data[tf]))

    if isempty(asset_dfs)
        @warn "No data found for specified assets and timeframe."
        return nothing, nothing, nothing # Indicate failure
    end

    # Find the common time index range across all relevant dataframes
    # This is a simplified approach; a proper time alignment might be needed
    first_date = maximum(df.timestamp[1] for df in values(asset_dfs) if !isempty(df))
    last_date = minimum(df.timestamp[end] for df in values(asset_dfs) if !isempty(df))

    # Find indices corresponding to the common date range for each asset
    # And collect all timestamps within the common range
    all_timestamps_in_range = Set{eltype(first(values(asset_dfs)).timestamp)}()
    time_indices = Dict()
    for (asset_name, df) in asset_dfs
        start_idx = findfirst(==(first_date), df.timestamp)
        end_idx = findfirst(==(last_date), df.timestamp)
        if isnothing(start_idx) || isnothing(end_idx) || start_idx > end_idx
            @warn "Could not find common date range for asset $asset_name. Skipping." color=:yellow
            delete!(asset_dfs, asset_name) # Remove asset if its data doesn't cover the common range
            continue
        end
        time_indices[asset_name] = (start_idx, end_idx)
         # Collect timestamps within this asset's common range
        union!(all_timestamps_in_range, @view df.timestamp[start_idx:end_idx])
    end

     if isempty(asset_dfs) # Check again after filtering
         @warn "No assets remaining after finding common date range." color=:yellow
         return Dict()
     end

    # Sort the unique timestamps to get the aligned time steps
    aligned_timestamps = sort(collect(all_timestamps_in_range))
    nrow = length(aligned_timestamps)

    # Return the aligned dataframes, time indices, and the number of rows
    return asset_dfs, time_indices, nrow, aligned_timestamps # Also return aligned_timestamps
end

# Helper function to initialize OnlineCrossCorrelation objects
function _initialize_online_corrs(y_assets_filtered, x_assets_filtered, corr_window, roc_period, demean)
    # Prepare ROC objects for each asset
    roc_ratiers = Dict{String, ROC{DFT}}()
    for asset_name in vcat(y_assets_filtered, x_assets_filtered)
         # Initialize ROC for all relevant assets
        roc_ratiers[asset_name] = ROC{DFT}(period=roc_period)
    end

    # Prepare OnlineCrossCorrelation objects for each (y, x) pair
    corrs = Dict{Tuple{String,String}, OnlineCrossCorrelation{DFT}}()
    for y in y_assets_filtered, x in x_assets_filtered
        # Pass both window and roc_period here
        corrs[(y, x)] = OnlineCrossCorrelation(corr_window, roc_period, DFT; demean=demean)
    end

    # Return initialized ROC and correlation objects
    return roc_ratiers, corrs
end

# Helper function to process historical data and fit online correlators
function _process_historical_data!(online_corrs, roc_ratiers, asset_dfs, time_indices, assets, y_assets_filtered, x_assets_filtered, effective_window, start_t_idx_relative, aligned_timestamps)
    # Feed data point by point, updating ROC ratios and then cross-correlations
    # Iterate through the aligned timestamps, starting from the calculated start index
    for (t_idx_relative, current_timestamp) in enumerate(aligned_timestamps[start_t_idx_relative:end])
        for asset_name in assets # Use the original filtered assets list before checking for dataframes
             if haskey(asset_dfs, asset_name) # Only process assets with dataframes
                 df = asset_dfs[asset_name]
                 # Find the exact index for the current timestamp in this dataframe
                 current_df_idx = findfirst(==(current_timestamp), df.timestamp)
                 if !isnothing(current_df_idx) # Ensure timestamp exists in this dataframe
                      price = df.close[current_df_idx]
                      if !ismissing(price) && isfinite(price)
                         oti.fit!(roc_ratiers[asset_name], price) # Update ROC ratio for this asset
                      end
                 end
             end
        end

        for y in y_assets_filtered, x in x_assets_filtered # Use filtered lists
             if haskey(online_corrs, (y, x)) # Only process for valid pairs
                 y_roc_val = oti.value(roc_ratiers[y])
                 x_roc_val = oti.value(roc_ratiers[x])

                 # Calculate ratio using the roc_to_ratio function
                 y_ratio_val = roc_to_ratio(y_roc_val)
                 x_ratio_val = roc_to_ratio(x_roc_val)

                 if !ismissing(y_ratio_val) && !ismissing(x_ratio_val) && isfinite(y_ratio_val) && isfinite(x_ratio_val)
                    fit!(online_corrs[(y, x)], y_ratio_val, x_ratio_val, current_timestamp) # Update cross-correlation with ratio values and timestamp
                 else
                    @debug "Skipping fit! for ($y, $x) due to invalid ratio values"
                 end
             end
        end
    end
end

# Helper function to compute lagged correlations and format output
function _compute_lagged_correlations(online_corrs, lags, x_assets_filtered, y_assets_filtered)
    # Compute correlations for each lag
    corr_dict = Dict()
    for (li, lag) in enumerate(lags)
        # Initialize matrix with dimensions x_assets_filtered x y_assets_filtered
        m = Array{Float64}(undef, length(x_assets_filtered), length(y_assets_filtered))
        # Need to map x_assets_filtered and y_assets_filtered back to their indices for matrix m
        x_asset_indices = Dict(name => idx for (idx, name) in enumerate(x_assets_filtered))
        y_asset_indices = Dict(name => idx for (idx, name) in enumerate(y_assets_filtered))

        for x in x_assets_filtered, y in y_assets_filtered # Iterate through x_assets (rows), y_assets (columns)
             if haskey(online_corrs, (y, x)) # Only process for valid pairs
                j = x_asset_indices[x] # Row index in the matrix
                i = y_asset_indices[y] # Column index in the matrix
                m[j, i] = value(online_corrs[(y, x)], lag)
             else
                m[j, i] = NaN # Or some other indicator for missing correlation
             end
        end

        # Create DataFrame with y_assets_filtered as column names
        df = DataFrame(m, y_assets_filtered)
        # Add x_assets_filtered as the first column
        df.x_asset = x_assets_filtered
        select!(df, vcat("x_asset", y_assets_filtered)) # Ensure x_asset is the first column
        metadata!(df, "lag", lag; style=:note)
        metadata!(df, "x_assets", x_assets_filtered; style=:note)
        # The batch version also has y_assets metadata on the DataFrame, let's add that
        metadata!(df, "y_assets", y_assets_filtered; style=:note)
        corr_dict[lag] = df
    end
    return corr_dict
end

"""
    crosscorr_assets_online(s::st.Strategy, tf=s.timeframe; min_vol=1e6, x_num=5, demean=false, lags=lagsbytf(tf), window=100, roc_period::Int=1)

Compute streaming cross-correlation matrices for selected asset pairs using OnlineCrossCorrelation.
Returns a Dict mapping each lag to a DataFrame of correlations (rows: x_assets, columns: y_assets).
The `window` parameter controls the size of the rolling window for the cross-correlation calculation.
"""
function crosscorr_assets_online(
    s::st.Strategy,
    tf=s.timeframe;
    min_vol=1e6,
    x_num=5,
    demean=false,
    lags=lagsbytf(tf),
    window=100, # Window for rolling cross-correlation
    roc_period::Int=1 # Period for the OnlineROCRatio
)
    # Get filtered assets and split into x and y
    x_assets, y_assets, local_assets_dict = _get_filtered_assets(s, tf, min_vol, x_num)
    if isnothing(x_assets) # Check if filtering failed
        return Dict() # Return empty dict on failure
    end

    # Get and align OHLCV data, and retrieve the number of rows
    asset_dfs, time_indices, nrow, aligned_timestamps = _get_aligned_ohlcv_data(s, tf, vcat(x_assets, y_assets), local_assets_dict)
    if isnothing(asset_dfs) # Check if data alignment failed
        return Dict() # Return empty dict on failure
    end

    # Determine the effective window size
    local effective_window::Int
    # The effective window is simply the minimum of the requested window and the available data length
    effective_window = min(window, nrow)
    if window > nrow
         @warn "Rolling window size ($window) is greater than total data length ($nrow). Using total data length ($nrow)." color=:yellow
     end
    corr_window = effective_window

    # Initialize ROC and OnlineCrossCorrelation objects
    roc_ratiers, online_corrs = _initialize_online_corrs(y_assets, x_assets, corr_window, roc_period, demean)
    if isnothing(online_corrs) # Check if initialization failed (shouldn't happen with current _initialize_online_corrs logic, but kept for safety)
        return Dict() # Return empty dict on failure
    end

    # Determine the starting index for processing based on effective window
    # We need enough data to fill the effective window, so start processing from (nrow - effective_window + 1)
    # If effective_window is 0 (e.g., nrow is 0), start_t_idx_relative should be 1 to avoid empty range
    local start_t_idx_relative::Int = max(1, nrow - effective_window + 1)

    # Process historical data and fit online correlators
    _process_historical_data!(online_corrs, roc_ratiers, asset_dfs, time_indices, vcat(x_assets, y_assets), y_assets, x_assets, effective_window, start_t_idx_relative, aligned_timestamps)

    # Compute lagged correlations and format output
    return _compute_lagged_correlations(online_corrs, lags, x_assets, y_assets)
end

end