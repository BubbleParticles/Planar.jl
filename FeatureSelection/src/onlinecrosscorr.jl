module OnlineCrossCorr

using Strategies: Strategies as st, DFT, DateTime, @lget!, Option
using ..FeatureSelection: center_data, ratio!, lagsbytf, tickers, raw, metadata, DataFrame, roc_to_ratio
using .st.Data.DataFrames: DataFrame, select!, metadata!
using OnlineTechnicalIndicators: ROC, OnlineTechnicalIndicators as oti
using StatsBase: crosscor
export OnlineCrossCorrelation, fit!, value, crosscorr_assets_online

# Struct to cache reusable containers for crosscorr_assets_online
mutable struct CrossCorrOnlineCache
    current_ratios::Dict{String, DFT} # Revert to using a dictionary for current ratios
    # Dictionary to hold lagged correlation matrices
    lagged_corr_matrices::Dict{Int, Array{Float64, 2}}

    # Constructor
    function CrossCorrOnlineCache(lags::AbstractVector{<:Integer})
        new(Dict{String, DFT}(), Dict{Int, Array{Float64, 2}}())
    end
end

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
end

function OnlineCrossCorrelation(window::Int, roc_period::Int, T::Type=DFT; demean::Bool=true)
    # The roc_period parameter is no longer used for initializing OnlineCrossCorrelation,
    # but keep it in the constructor signature for compatibility if needed elsewhere.
    # The actual ROC calculation happens outside this struct now.
    OnlineCrossCorrelation{T}(window, zeros(T, window), zeros(T, window),
        zero(T), zero(T), zero(T), zero(T), zero(T), 1, 0, demean, DateTime(0))
end

function fit!(occ::OnlineCrossCorrelation{T}, x_ratio_val::T, y_ratio_val::T, timestamp::DateTime) where {T}
    # Directly use the provided ratio values
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

    # Calculate correlation directly from the circular buffer
    # Indices in the buffer are 1-based
    # We need to compute sums over a lagged window of size n - abs(lag)
    window_size = n - abs(lag)
    if window_size <= 0
        return NaN
    end

    sx = zero(DFT)
    sy = zero(DFT)
    sxx = zero(DFT)
    syy = zero(DFT)
    sxy = zero(DFT)

    # Determine the starting index in the circular buffer for the current data point (most recent)
    current_buf_end_idx = occ.idx == 1 ? occ.window : occ.idx - 1 # The index where the last data point was inserted

    for i in 0:(window_size - 1)
        # Calculate the index for the current data point in the x and y series
        # This accounts for wrap-around and starts from the most recent data backwards
        x_current_data_idx = current_buf_end_idx - i
        if x_current_data_idx <= 0
            x_current_data_idx += occ.window # Wrap around
        end

        # Calculate the index for the lagged data point in the y series
        y_lagged_data_idx = current_buf_end_idx - i - lag
        # Handle wrap-around for lagged index
        while y_lagged_data_idx <= 0
            y_lagged_data_idx += occ.window
        end
         while y_lagged_data_idx > occ.window
            y_lagged_data_idx -= occ.window
        end

        x_val = occ.xbuf[x_current_data_idx]
        y_val = occ.ybuf[y_lagged_data_idx]

        sx += x_val
        sy += y_val
        sxx += x_val^2
        syy += y_val^2
        sxy += x_val * y_val
    end

    if occ.demean
        # Using (sum of products - sum x * sum y / n) / (n-1) (Bessel's correction for sample covariance)
        # Here n is window_size for the lagged correlation
        denom = window_size > 1 ? window_size - 1 : window_size # Avoid division by zero for window_size=1
        covxy = (sxy - sx * sy / window_size) / denom
        # Using (sum of squares - (sum)^2 / n) / (n-1) (Bessel's correction for sample variance)
        varx = (sxx - sx^2 / window_size) / denom
        vary = (syy - sy^2 / window_size) / denom
    else
        # Using sum of products / n
        covxy = sxy / window_size
        # Using sum of squares / n
        varx = sxx / window_size
        vary = syy / window_size
    end

    if varx <= 0 || vary <= 0
        return NaN
    end

    # Ensure the result is a finite number
    result = covxy / sqrt(varx * vary)
    return isfinite(result) ? result : NaN
end

function value(occ::OnlineCrossCorrelation, lags::AbstractVector{<:Integer})
    n = occ.count # Use the current count of data points in the window/buffer
    if n < 2 || isempty(lags) || maximum(abs, lags) >= n
        return [NaN for _ in lags] # Return array of NaN for each requested lag
    end

    # Determine the starting index in the circular buffer for the current data point (most recent)
    current_buf_end_idx = occ.idx == 1 ? occ.window : occ.idx - 1 # The index where the last data point was inserted

    # Initialize sums for each lag. Use a dictionary for easy access by lag value.
    # Each entry is a NamedTuple of sums (sx, sy, sxx, syy, sxy)
    lag_sums = Dict{Int, NamedTuple{(:sx, :sy, :sxx, :syy, :sxy), Tuple{DFT, DFT, DFT, DFT, DFT}}}()
    # Initialize with zeros for all requested lags
    for lag in lags
        lag_sums[lag] = (sx=zero(DFT), sy=zero(DFT), sxx=zero(DFT), syy=zero(DFT), sxy=zero(DFT))
    end

    # Iterate backwards through the circular buffer up to the full effective window size
    # The maximum index we need to access is determined by the maximum lag and the window size.
    # We need to consider data points from the most recent back to cover the window for the largest absolute lag.
    # The number of points required is `n` for the unlagged series. For a lag `l`, the lagged series
    # will access points up to `l` steps further back. So we need to iterate back up to `n - 1 + max(abs, lags)` points
    # in terms of positions relative to the current end. However, the correlation for lag `l` only uses `n - abs(l)` pairs.
    # The outer loop should iterate over the pairs used for the correlation, which is `n - abs(lag)`.
    # The most efficient way is to iterate over the *buffer indices* that are part of the current window of size `n`.
    # For each buffer index `i` (representing a data point in time), calculate its corresponding lagged partner index.

    # Iterate over the indices of the current valid data in the circular buffer (size `n`)
    for i_relative_time in 0:(n - 1)
        # Calculate the buffer index for the current data point (x series, lag 0)
        x_current_buf_idx = current_buf_end_idx - i_relative_time
        if x_current_buf_idx <= 0
            x_current_buf_idx += occ.window # Wrap around
        end
        x_val = occ.xbuf[x_current_buf_idx]

        # For each lag, calculate the corresponding y buffer index and update sums
        for lag in lags
            # The current data point is at relative time `i_relative_time`.
            # The corresponding lagged data point for lag `l` is at relative time `i_relative_time + l`.
            # We need to check if this pair is within the valid window for lag `l`, which is `n - abs(l)`.
            # The number of pairs used for lag `l` is `n - abs(l)`. We are iterating from the most recent
            # point (i_relative_time = 0) back to the oldest (i_relative_time = n - 1).
            # For a positive lag `l`, we need pairs (x[t], y[t-l]). If we are at index `i_relative_time` in the buffer (from most recent),
            # the corresponding x is at `current_buf_end_idx - i_relative_time`. The corresponding y is at
            # `current_buf_end_idx - i_relative_time - l`. This pair is included if `i_relative_time < n - abs(l)`.

            if i_relative_time < n - abs(lag)
                y_lagged_buf_idx = current_buf_end_idx - i_relative_time - lag
                 # Handle wrap-around for lagged index
                 while y_lagged_buf_idx <= 0
                    y_lagged_buf_idx += occ.window
                 end
                  while y_lagged_buf_idx > occ.window
                    y_lagged_buf_idx -= occ.window
                 end

                y_val = occ.ybuf[y_lagged_buf_idx]

                current_sums = lag_sums[lag]
                lag_sums[lag] = (
                    sx = current_sums.sx + x_val,
                    sy = current_sums.sy + y_val,
                    sxx = current_sums.sxx + x_val^2,
                    syy = current_sums.syy + y_val^2,
                    sxy = current_sums.sxy + x_val * y_val
                )
            end
        end
    end

    # Calculate correlations for each lag using the precomputed sums
    results = Dict{Int, DFT}()
    for lag in lags
        current_sums = lag_sums[lag]
        sx, sy, sxx, syy, sxy = current_sums.sx, current_sums.sy, current_sums.sxx, current_sums.syy, current_sums.sxy
        window_n = n - abs(lag) # The number of pairs used for this lag

        if window_n < 2
            results[lag] = NaN
            continue
        end

        if occ.demean
            denom = window_n > 1 ? window_n - 1 : window_n
            covxy = (sxy - sx * sy / window_n) / denom
            varx = (sxx - sx^2 / window_n) / denom
            vary = (syy - sy^2 / window_n) / denom
        else
            covxy = sxy / window_n
            varx = sxx / window_n
            vary = syy / window_n
        end

        correlation_value = if varx <= 0 || vary <= 0
            NaN
        else
            covxy / sqrt(varx * vary)
        end

       results[lag] = isfinite(correlation_value) ? correlation_value : NaN
    end

    # Return results in the order of the input lags
    return [get(results, lag, NaN) for lag in lags]
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
function _get_aligned_ohlcv_data(
    s::st.Strategy,
    tf,
    assets::AbstractVector,
    local_assets_dict::AbstractDict
)
    # Collect dataframes for relevant assets and timeframe
    # Use the local_assets_dict which points to the strategy's asset dictionary
    asset_dfs = Dict{String, DataFrame}()
    for asset_name in assets
        if haskey(local_assets_dict, asset_name) && haskey(local_assets_dict[asset_name].data, tf) && !isempty(local_assets_dict[asset_name].data[tf])
             asset_dfs[asset_name] = local_assets_dict[asset_name].data[tf]
        end
    end

    if isempty(asset_dfs)
        @warn "No data found for specified assets and timeframe." color=:yellow # Changed to yellow as it's not always an error
        return nothing, nothing, nothing, nothing # Indicate failure, return all four expected outputs as nothing
    end

    # Find the common time index range across all relevant dataframes
    # This is a simplified approach; a proper time alignment might be needed
    first_date = maximum(df.timestamp[1] for df in values(asset_dfs) if !isempty(df))
    last_date = minimum(df.timestamp[end] for df in values(asset_dfs) if !isempty(df))

    # Find indices corresponding to the common date range for each asset
    # And collect all timestamps within the common range
    all_timestamps_in_range = Set{eltype(first(values(asset_dfs)).timestamp)}()
    time_indices = Dict{String, Tuple{Int, Int}}()
    filtered_asset_dfs = Dict{String, DataFrame}() # Use a new dict for filtered assets
    for (asset_name, df) in asset_dfs
        start_idx = findfirst(==(first_date), df.timestamp)
        end_idx = findfirst(==(last_date), df.timestamp)
        if isnothing(start_idx) || isnothing(end_idx) || start_idx > end_idx
            @warn "Could not find common date range for asset $asset_name. Skipping." color=:yellow
            continue # Skip this asset
        end
        time_indices[asset_name] = (start_idx, end_idx)
         # Collect timestamps within this asset's common range
        union!(all_timestamps_in_range, @view df.timestamp[start_idx:end_idx])
        filtered_asset_dfs[asset_name] = df # Keep the dataframe for filtered assets
    end

     if isempty(filtered_asset_dfs) # Check again after filtering
         @warn "No assets remaining after finding common date range." color=:yellow
         return nothing, nothing, nothing, nothing
     end

    # Sort the unique timestamps to get the aligned time steps
    aligned_timestamps = sort(collect(all_timestamps_in_range))
    nrow = length(aligned_timestamps)

    # Return the aligned dataframes (filtered), time indices, the number of rows, and aligned_timestamps
    return filtered_asset_dfs, time_indices, nrow, aligned_timestamps # Return filtered_asset_dfs
end

function _calculate_ratios_for_timestamp!(
    cache::CrossCorrOnlineCache,
    roc_ratiers::Dict{String, ROC{DFT}},
    asset_dfs::Dict{String, DataFrame},
    asset_timestamp_indices::Dict{String, Vector{Int}},
    assets::AbstractVector{String},
    t_idx_relative_in_aligned::Int
)
    # Calculate and store ratios for all assets for the current timestamp
    empty!(cache.current_ratios) # Clear for reuse from cache
    for asset_name in assets # Use the original filtered assets list before checking for dataframes
         if haskey(asset_dfs, asset_name) && haskey(asset_timestamp_indices, asset_name)
             df = asset_dfs[asset_name]
             # Get the index in the original dataframe for this aligned timestamp
             current_df_idx = asset_timestamp_indices[asset_name][t_idx_relative_in_aligned]

             # Check if the index is valid (not the -1 sentinel value)
             if current_df_idx != -1
                  price = df.close[current_df_idx]
                  if !ismissing(price) && isfinite(price)
                     if haskey(roc_ratiers, asset_name)
                        oti.fit!(roc_ratiers[asset_name], price) # Use asset_name as key for roc_ratiers dict
                        # Calculate ratio after fitting ROC and store it in the vector
                        roc_val = oti.value(roc_ratiers[asset_name]) # Use asset_name as key for roc_ratiers dict
                        ratio_val = roc_to_ratio(roc_val)
                        if ismissing(ratio_val)
                            cache.current_ratios[asset_name] = NaN # Use asset_name as key
                        else
                            cache.current_ratios[asset_name] = ratio_val # Use asset_name as key
                        end
                     else
                         @warn "ROC ratiers not found for asset $(asset_name). Skipping." color=:yellow
                         cache.current_ratios[asset_name] = NaN # Use asset_name as key
                      end
                   else
                       cache.current_ratios[asset_name] = NaN # Use asset_name as key
                   end
               else
                   cache.current_ratios[asset_name] = NaN # Use asset_name as key # Handle case where aligned timestamp has no corresponding data
               end
         else
             cache.current_ratios[asset_name] = NaN # Use asset_name as key # Handle case where asset_dfs or asset_timestamp_indices is missing asset
         end
    end
    return nothing
end

function _fit_online_correlators!(
    online_corrs::Dict{Tuple{String,String}, OnlineCrossCorrelation{DFT}},
    cache::CrossCorrOnlineCache,
    current_timestamp::DateTime
)
     # Iterate directly over the online_corrs dictionary and fit each OCC object
    for ((y, x), occ) in online_corrs
         # Retrieve ratio values from the vector using the index mapping
         # Add checks to ensure keys exist before accessing
         if haskey(cache.current_ratios, y) && haskey(cache.current_ratios, x)
             y_ratio_val = cache.current_ratios[y]
             x_ratio_val = cache.current_ratios[x]

             if !ismissing(y_ratio_val) && !ismissing(x_ratio_val) && isfinite(y_ratio_val) && isfinite(x_ratio_val)
                fit!(occ, y_ratio_val, x_ratio_val, current_timestamp) # Update cross-correlation with ratio values and timestamp
             else
                @debug "Skipping fit! for ($(y), $(x)) due to invalid ratio values" color=:yellow
             end
         else
              @debug "Skipping fit! for ($(y), $(x)) due to missing ratio data for one or both assets" color=:yellow
         end
    end
    return nothing
end

# Helper function to process a single historical data point (timestamp)
function _process_single_timestamp!(
    online_corrs::Dict{Tuple{String,String}, OnlineCrossCorrelation{DFT}},
    roc_ratiers::Dict{String, ROC{DFT}},
    asset_dfs::Dict{String, DataFrame}, # Added type annotation
    asset_timestamp_indices::Dict{String, Vector{Int}}, # Added type annotation
    assets::AbstractVector{String},
    current_timestamp::DateTime,
    cache::CrossCorrOnlineCache,
    t_idx_relative_in_aligned::Int # Renamed for clarity
)
    # Calculate and store ratios for all assets for the current timestamp
    _calculate_ratios_for_timestamp!(cache, roc_ratiers, asset_dfs, asset_timestamp_indices, assets, t_idx_relative_in_aligned)

    # Iterate directly over the online_corrs dictionary and fit each OCC object
    _fit_online_correlators!(online_corrs, cache, current_timestamp)

    return nothing
end

# Helper function to process historical data and fit online correlators
function _process_historical_data!(
    online_corrs::Dict{Tuple{String,String}, OnlineCrossCorrelation{DFT}},
    roc_ratiers::Dict{String, ROC{DFT}},
    asset_dfs::Dict{String, DataFrame}, # Added type annotation
    time_indices::Dict{String, Tuple{Int, Int}}, # Added type annotation
    assets::AbstractVector{String},
    y_assets_filtered::AbstractVector{String},
    x_assets_filtered::AbstractVector{String},
    effective_window::Int, # Added type annotation
    start_t_idx_relative::Int, # Added type annotation
    aligned_timestamps::AbstractVector{DateTime}, # Added type annotation
    cache::CrossCorrOnlineCache
)
    # Pre-calculate indices for faster access
    # Create a mapping from aligned timestamp index (relative to start_t_idx_relative) to the original dataframe index for each asset.
    asset_aligned_to_orig_indices = Dict{String, Vector{Int}}() # Maps asset_name to a vector of original df indices

    for asset_name in assets
        if haskey(asset_dfs, asset_name) && haskey(time_indices, asset_name)
            df = asset_dfs[asset_name]
            start_orig_idx, end_orig_idx = time_indices[asset_name]

            # Create a map from timestamp in the *aligned* range to the index in the *original* dataframe
            timestamp_to_orig_idx = Dict(t => idx for (idx, t) in enumerate(df.timestamp[start_orig_idx:end_orig_idx]))

            # Now map the aligned timestamps (from start_t_idx_relative) to these original indices
            asset_aligned_to_orig_indices[asset_name] = Int[] # Initialize vector
            for aligned_ts in aligned_timestamps[start_t_idx_relative:end]
                # Find the index in the *original* dataframe corresponding to this aligned timestamp
                 if haskey(timestamp_to_orig_idx, aligned_ts)
                     # Push the original dataframe index (1-based) for this aligned timestamp
                     push!(asset_aligned_to_orig_indices[asset_name], timestamp_to_orig_idx[aligned_ts] + start_orig_idx - 1)
                 else
                     # Use -1 or similar to indicate missing data for this timestamp and asset
                     push!(asset_aligned_to_orig_indices[asset_name], -1)
                 end
            end
         else
             # If asset_dfs or time_indices is missing the asset, create a vector of -1s
              asset_aligned_to_orig_indices[asset_name] = fill(-1, length(aligned_timestamps) - start_t_idx_relative + 1)
         end
    end

    # Feed data point by point, updating ROC ratios and then cross-correlations
    # Iterate through the aligned timestamps, starting from the calculated start index
    # Pre-allocate dictionary for current ratios to avoid repeated allocations
    for (t_idx_relative_in_aligned, current_timestamp) in enumerate(aligned_timestamps[start_t_idx_relative:end])
         # Pass the index relative to the start of the aligned timestamps being processed
         _process_single_timestamp!(online_corrs, roc_ratiers, asset_dfs, asset_aligned_to_orig_indices, assets, current_timestamp, cache, t_idx_relative_in_aligned)
    end
end

# Helper function to compute a single lagged correlation value and place it in the matrix
function _compute_single_correlation!(
    cache::CrossCorrOnlineCache,
    online_corrs::Dict{Tuple{String,String}, OnlineCrossCorrelation{DFT}}, # Added type annotation
    y::String,
    x::String,
    lag::Integer,
    x_asset_indices::Dict{String, Int},
    y_asset_indices::Dict{String, Int}
)
    # Ensure the key exists in online_corrs before accessing
    if haskey(online_corrs, (y, x))
        occ = online_corrs[(y, x)]
        correlation_value = value(occ, lag)
        # Ensure the lag key and asset keys exist in cache.lagged_corr_matrices before accessing
        if haskey(cache.lagged_corr_matrices, lag) && haskey(x_asset_indices, x) && haskey(y_asset_indices, y)
            cache.lagged_corr_matrices[lag][x_asset_indices[x], y_asset_indices[y]] = correlation_value
        else
             @debug "Skipping correlation assignment for ($(y), $(x)) at lag $(lag) due to missing cache entry or indices." color=:yellow
        end
    else
         @debug "Skipping correlation computation for pair ($(y), $(x)) as it's not in online_corrs." color=:yellow
    end
end

# Helper function to compute lagged correlations and format output
function _compute_lagged_correlations(
    online_corrs::Dict{Tuple{String,String}, OnlineCrossCorrelation{DFT}}, # Added type annotation
    x_assets_filtered::AbstractVector{String},
    y_assets_filtered::AbstractVector{String},
    asset_dfs::Dict{String, DataFrame}, # Added type annotation
    cache::CrossCorrOnlineCache,
    lags::AbstractVector{<:Integer}
)
    # Compute correlations for each lag
    corr_dict = Dict{eltype(lags), DataFrame}() # Added type annotation
    # Reuse lagged_corr_matrices from cache, ensuring correct dimensions
    local current_matrix_size = isempty(cache.lagged_corr_matrices) ? (0, 0) : size(first(values(cache.lagged_corr_matrices)))
    local expected_matrix_size = (length(x_assets_filtered), length(y_assets_filtered))
    local current_lags = isempty(cache.lagged_corr_matrices) ? Int[] : sort(collect(keys(cache.lagged_corr_matrices)))
    local expected_lags = sort(collect(Int.(lags)))

    if current_matrix_size != expected_matrix_size || current_lags != expected_lags
         @debug "Reinitializing lagged_corr_matrices due to size or lag mismatch." color=:yellow
         cache.lagged_corr_matrices = Dict(lag => Array{Float64}(undef, length(x_assets_filtered), length(y_assets_filtered)) for lag in lags) # Keys are lag values
    else
        # Clear existing data if dimensions and lags match
        for m in values(cache.lagged_corr_matrices)
             fill!(m, NaN) # Clear existing data
        end
    end

    # Need to map x_assets_filtered and y_assets_filtered back to their indices for the matrices
    x_asset_indices = Dict(name => idx for (idx, name) in enumerate(x_assets_filtered))
    y_asset_indices = Dict(name => idx for (idx, name) in enumerate(y_assets_filtered))

    # Filter online_corrs to include only pairs where both assets are in asset_dfs
    # This filtering is already done implicitly by iterating processed_online_corrs below
    # processed_online_corrs = Dict(
    #     (y, x) => occ for ((y, x), occ) in online_corrs
    #     if haskey(asset_dfs, y) && haskey(asset_dfs, x)
    # )

    # Iterate through each possible (y, x) pair and then each lag
    # Iterate based on x_assets_filtered and y_assets_filtered to match matrix dimensions
    for y in y_assets_filtered
        for x in x_assets_filtered
            # Ensure the pair exists in online_corrs (it should if _initialize_online_corrs worked)
            if haskey(online_corrs, (y, x))
                for lag in lags
                    _compute_single_correlation!(cache, online_corrs, y, x, lag, x_asset_indices, y_asset_indices)
                end
            else
                 @debug "Skipping correlation computation for pair ($(y), $(x)) as it's not in online_corrs (should not happen if initialization was correct)." color=:yellow
            end
        end
    end

    # Format output into Dict of DataFrames
    for (lag, m) in cache.lagged_corr_matrices
        df = DataFrame(m, y_assets_filtered)
        # Add x_assets_filtered as the first column
        df.x_asset = x_assets_filtered
        select!(df, vcat("x_asset", y_assets_filtered)) # Ensure x_asset is the first column
        metadata!(df, "lag", lag; style=:note)
        metadata!(df, "x_assets", x_assets_filtered; style=:note) # Ensure metadata uses filtered lists
        metadata!(df, "y_assets", y_assets_filtered; style=:note) # Ensure metadata uses filtered lists
        corr_dict[lag] = df
    end

    return corr_dict
end

# Helper function to initialize OnlineCrossCorrelation objects and their associated ROC ratiers
function _initialize_online_corrs(y_assets::AbstractVector{String}, x_assets::AbstractVector{String}, window::Int, roc_period::Int, demean::Bool)
    # Prepare ROC objects for each asset
    roc_ratiers = Dict{String, ROC{DFT}}()
    for asset_name in vcat(y_assets, x_assets)
         # Initialize ROC for all relevant assets
        roc_ratiers[asset_name] = ROC{DFT}(period=roc_period)
    end

    # Prepare OnlineCrossCorrelation objects for each (y, x) pair
    corrs = Dict{Tuple{String,String}, OnlineCrossCorrelation{DFT}}()
    for y in y_assets, x in x_assets
        # Only pass window and demean to OnlineCrossCorrelation constructor
        corrs[(y, x)] = OnlineCrossCorrelation(window, 1, DFT; demean=demean) # Pass 1 for roc_period as it's ignored now
    end

    # Return both dictionaries
    return roc_ratiers, corrs
end

"""
    crosscorr_assets_online(s::st.Strategy, tf=s.timeframe; min_vol=1e6, x_num=5, demean=false, lags=lagsbytf(tf), window=100, roc_period::Int=1, cache::Option{CrossCorrOnlineCache}=nothing)

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
    roc_period::Int=1
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

    # Get or initialize the cross-correlation state from the strategy's attributes dictionary using @lget!
    local crosscorr_cache = nothing
    local roc_ratiers = nothing
    local online_corrs = nothing
    local reinitialize_required = false

    # Attempt to retrieve existing state and validate it
    if haskey(s.attrs, :_crosscorr_state)
        local current_crosscorr_state = s.attrs[:_crosscorr_state]
        # Check if the retrieved state is a NamedTuple and has the expected fields
        if typeof(current_crosscorr_state) <: NamedTuple &&
           hasfield(typeof(current_crosscorr_state), :cache) &&
           hasfield(typeof(current_crosscorr_state), :roc_ratiers) &&
           hasfield(typeof(current_crosscorr_state), :online_corrs)

             # Extract components for type and parameter checking
             crosscorr_cache = current_crosscorr_state.cache
             roc_ratiers = current_crosscorr_state.roc_ratiers
             online_corrs = current_crosscorr_state.online_corrs

             # Check type compatibility
             if !(typeof(crosscorr_cache) <: CrossCorrOnlineCache) ||
                !(typeof(roc_ratiers) <: Dict{String, ROC{DFT}}) ||
                !(typeof(online_corrs) <: Dict{Tuple{String,String}, OnlineCrossCorrelation{DFT}})
                 @warn "Cached cross-correlation state components have incompatible types. Reinitializing." color=:red
                 reinitialize_required = true
             else
                 # Check parameters if types are compatible
                 # Check lags compatibility
                if sort(collect(keys(crosscorr_cache.lagged_corr_matrices))) != sort(collect(Int.(lags)))
                     @warn "Cached lags changed. Reinitializing cross-correlation state." color=:yellow
                     reinitialize_required = true
                 end

                 # Check online_corrs compatibility (window, demean)
                 if !isempty(online_corrs)
                      local example_corr_pair = first(online_corrs)
                      local example_corr = example_corr_pair.second
                      if example_corr.window != window || example_corr.demean != demean
                           @warn "Cached OnlineCrossCorrelation parameters (window or demean) changed. Reinitializing." color=:yellow
                           reinitialize_required = true
                       end
                 else
                      @warn "Cached OnlineCrossCorrelation objects are empty. Reinitializing." color=:yellow
                      reinitialize_required = true
                 end
             end
         else
             @warn "Cached cross-correlation state is not a NamedTuple or is missing fields. Reinitializing." color=:red
             reinitialize_required = true
          end
    else
        @debug "No existing cross-correlation state found in strategy attributes. Initializing new state."
        reinitialize_required = true
    end

    if reinitialize_required
        @debug "Reinitializing cross-correlation state and updating strategy attributes."
        # Create new objects and store them in the strategy's attributes dictionary
        # Initialize online correlators and extract the two components
        local initialized_roc_ratiers, initialized_online_corrs = _initialize_online_corrs(y_assets, x_assets, window, roc_period, demean)

        # Store state components in a NamedTuple
        current_crosscorr_state = (; # Use NamedTuple constructor syntax
            cache = CrossCorrOnlineCache(lags),
            roc_ratiers = initialized_roc_ratiers, # Store the extracted roc_ratiers dict
            online_corrs = initialized_online_corrs # Store the extracted online_corrs dict
        )
        s.attrs[:_crosscorr_state] = current_crosscorr_state # Store the new state

        # Update references to the newly created objects
        crosscorr_cache = current_crosscorr_state.cache
        roc_ratiers = current_crosscorr_state.roc_ratiers
        online_corrs = current_crosscorr_state.online_corrs

        # Also clear the cache's lagged matrices for reuse (reinitialize if dimensions changed or was empty or lags changed)
        # Check if matrix dimensions or lags are incompatible before clearing
        local current_matrix_size = isempty(crosscorr_cache.lagged_corr_matrices) ? (0, 0) : size(first(values(crosscorr_cache.lagged_corr_matrices)))
        local expected_matrix_size = (length(x_assets), length(y_assets))
        local current_lags = isempty(crosscorr_cache.lagged_corr_matrices) ? [] : sort(collect(keys(crosscorr_cache.lagged_corr_matrices)))
        local expected_lags = sort(collect(Int.(lags)))

        if current_matrix_size == expected_matrix_size && current_lags == expected_lags
             # Clear existing data if dimensions and lags match
             for m in values(crosscorr_cache.lagged_corr_matrices)
                  fill!(m, NaN) # Clear existing data
             end
        else # Reinitialize lagged_corr_matrices if dimensions changed or was empty or lags changed
             @debug "Reinitializing lagged_corr_matrices due to size or lag mismatch."
             crosscorr_cache.lagged_corr_matrices = Dict(lag => Array{Float64}(undef, length(x_assets), length(y_assets)) for lag in lags) # Keys are lag values
        end
    else
        @debug "Reusing compatible cross-correlation state from strategy attributes."
        # Assign variables from the successfully retrieved and validated state
        crosscorr_cache = current_crosscorr_state.cache
        roc_ratiers = current_crosscorr_state.roc_ratiers
        online_corrs = current_crosscorr_state.online_corrs

        # Reset online correlation objects for a new historical run if needed
        # In a live setting, you wouldn't reset, but for historical chunks, you might
        for occ in values(online_corrs)
            fit!(occ, NaN, NaN, DateTime(0)) # Reset to NaN values
        end
    end

    # Process historical data and update online correlators using the state
    _process_historical_data!(online_corrs, roc_ratiers, asset_dfs, time_indices, vcat(x_assets, y_assets), y_assets, x_assets, effective_window, 1, aligned_timestamps, crosscorr_cache)

    # Compute lagged correlations and format output using the updated state
    return _compute_lagged_correlations(online_corrs, x_assets, y_assets, asset_dfs, crosscorr_cache, lags)
end

end