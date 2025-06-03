using OnlineTechnicalIndicators: ROC, OnlineStatsBase
using OnlineStats: fit!, value, Variance, Mean, LinReg, nobs, coef, CovMatrix, MovingWindow, StatLag, OnlineStats
using .OnlineStatsBase: OnlineStat, value, nobs, merge!, CircBuff, EqualWeight # Added CircBuff
using .da.DataFrames: DataFrame, metadata, names, findfirst, size, DataFrameRow, filter, nrow
using .st.Dates: DateTime
using .st.Misc: DFT, Option # Assuming DFT is in Misc
using .st: Strategy, AssetInstance, universe, raw # Added imports for strategy and asset access
using .da.DataStructures: BinaryHeap, isempty, push!, peek, pop! # Added for min-heap

# Helper function to calculate quote volume safely
function _calculate_quote_volume(df::DataFrame)::DFT
    if isempty(df) || !hasproperty(df, :close) || !hasproperty(df, :volume) || ismissing(df[end, :close]) || ismissing(df[end, :volume]) || isnan(df[end, :close]) || isnan(df[end, :volume])
        return DFT(-Inf) # Use -Inf to handle cases with missing/invalid data during sorting
    else
        return DFT(df[end, :close] * df[end, :volume])
    end
end

# Define a new OnlineStat for rolling variance
mutable struct RollingVariance{T <: Number, W <: EqualWeight} <: OnlineStat{T}
    buffer::CircBuff{T}
    sum_x::T
    sum_x2::T
    nobs::Int
    window::Int
    weight::W

    function RollingVariance{T}(window::Int, weight::W = EqualWeight()) where {T, W <: EqualWeight}
        window > 0 || error("Window size must be positive.")
        new{T, W}(CircBuff(T, window), zero(T), zero(T), 0, window, weight)
    end
end

# Constructor for convenience
RollingVariance(window::Int, T::Type = Float64) = RollingVariance{T}(window)

# Implement fit! for RollingVariance
function OnlineStats.fit!(o::RollingVariance{T}, x::T) where T
    oldest_x = zero(T)
    buffer_is_full = o.nobs == o.window

    if buffer_is_full
        oldest_x = o.buffer[1] # Get the oldest value before it's overwritten
        o.sum_x -= oldest_x
        o.sum_x2 -= oldest_x^2
    end

    fit!(o.buffer, x) # Add the new value to the circular buffer

    o.sum_x += x
    o.sum_x2 += x^2
    o.nobs = min(o.nobs + 1, o.window) # Increment nobs, capped at window size

    return o # Return the updated stat
end

# Implement nobs for RollingVariance
OnlineStats.nobs(o::RollingVariance) = o.nobs

# Implement value for RollingVariance
function OnlineStats.value(o::RollingVariance)
    if o.nobs < o.window
        return NaN # Or some other indicator that the window is not yet full
    end

    # Calculate variance using the current sum and sum of squares over the window
    # Formula for sample variance: (sum(x^2) - (sum(x)^2 / n)) / (n - 1)
    n = DFT(o.nobs) # Ensure calculations use DFT
    sum_x = DFT(o.sum_x)
    sum_x2 = DFT(o.sum_x2)

    variance = (sum_x2 - (sum_x^2 / n)) / (n - 1)
    return variance
end

# Although not strictly necessary for this rolling calculation, for a complete OnlineStat,
# we would also need to define merge! if we wanted to combine RollingVariance stats.
# merge!(o1::RollingVariance, o2::RollingVariance) = error("Merging RollingVariance is not supported")

# Define a new OnlineStat for rolling covariance matrix (for two variables)
mutable struct RollingCovMatrix{T <: Number} <: OnlineStat{Tuple{T, T}} # CovMatrix takes pairs (x, y)
    buffer::CircBuff{Tuple{T, T}}
    sum_x::T
    sum_y::T
    sum_x2::T # Needed for individual variances in CovMatrix calculation
    sum_y2::T # Needed for individual variances
    sum_xy::T # Needed for covariance
    nobs::Int
    window::Int
    weight::EqualWeight # Assuming EqualWeight for rolling window

    function RollingCovMatrix{T}(window::Int) where T
        window > 0 || error("Window size must be positive.")
        new{T}(CircBuff(Tuple{T, T}, window), zero(T), zero(T), zero(T), zero(T), zero(T), 0, window, EqualWeight())
    end
end

# Constructor for convenience
RollingCovMatrix(window::Int, T::Type = Float64) = RollingCovMatrix{T}(window)

# Implement fit! for RollingCovMatrix
function OnlineStats.fit!(o::RollingCovMatrix{T}, xy::Tuple{T, T}) where T
    x, y = xy
    oldest_xy = (zero(T), zero(T))
    buffer_is_full = o.nobs == o.window

    if buffer_is_full
        oldest_xy = o.buffer[1]
        oldest_x, oldest_y = oldest_xy
        o.sum_x -= oldest_x
        o.sum_y -= oldest_y
        o.sum_x2 -= oldest_x^2
        o.sum_y2 -= oldest_y^2
        o.sum_xy -= oldest_x * oldest_y
    end

    fit!(o.buffer, xy) # Add the new pair to the circular buffer

    o.sum_x += x
    o.sum_y += y
    o.sum_x2 += x^2
    o.sum_y2 += y^2
    o.sum_xy += x * y
    o.nobs = min(o.nobs + 1, o.window) # Increment nobs, capped at window size

    return o # Return the updated stat
end

# Implement nobs for RollingCovMatrix
OnlineStats.nobs(o::RollingCovMatrix) = o.nobs

# Implement value for RollingCovMatrix (returns CovMatrix equivalent or just the covariance value)
# Let's return a 2x2 covariance matrix
function OnlineStats.value(o::RollingCovMatrix{T}) where T
    if o.nobs < o.window
        # Return a matrix of NaNs or zeros to indicate insufficient data
        return fill(NaN, 2, 2)
    end

    n = DFT(o.nobs)
    sum_x = DFT(o.sum_x)
    sum_y = DFT(o.sum_y)
    sum_x2 = DFT(o.sum_x2)
    sum_y2 = DFT(o.sum_y2)
    sum_xy = DFT(o.sum_xy)

    # Calculate means
    mean_x = sum_x / n
    mean_y = sum_y / n

    # Calculate sums of squared differences from the mean (M2)
    # M2_x = sum((x - mean_x)^2) = sum(x^2) - 2 * mean_x * sum(x) + n * mean_x^2
    # A more stable way: sum(x^2) - sum(x)^2 / n
    m2_x = sum_x2 - sum_x^2 / n
    m2_y = sum_y2 - sum_y^2 / n

    # Calculate sum of products of differences from the mean (M2_xy)
    # M2_xy = sum((x - mean_x) * (y - mean_y)) = sum(xy - x*mean_y - y*mean_x + mean_x*mean_y)
    # = sum(xy) - mean_y*sum(x) - mean_x*sum(y) + n*mean_x*mean_y
    # A more stable way: sum(xy) - sum(x) * sum(y) / n
    m2_xy = sum_xy - sum_x * sum_y / n

    # Calculate sample covariance matrix (divide by n - 1)
    cov_xx = m2_x / (n - 1)
    cov_yy = m2_y / (n - 1)
    cov_xy = m2_xy / (n - 1)

    return [cov_xx cov_xy; cov_xy cov_yy]
end


# Define a new OnlineStat for rolling linear regression (y = β₀ + β₁x)
mutable struct RollingLinReg{T <: Number} <: OnlineStat{Tuple{T, T}} # Takes (y, x)
    buffer::CircBuff{Tuple{T, T}}
    sum_x::T # Sum of predictor (benchmark return)
    sum_y::T # Sum of response (asset return)
    sum_x2::T # Sum of squares of predictor
    sum_y2::T # Sum of squares of response (needed for R^2, but not strictly for coeffs)
    sum_xy::T # Sum of products of predictor and response
    nobs::Int
    window::Int
    weight::EqualWeight # Assuming EqualWeight for rolling window

    function RollingLinReg{T}(window::Int) where T
        window > 0 || error("Window size must be positive.")
        # Initialize sums and sum of squares to zero
        new{T}(CircBuff(Tuple{T, T}, window), zero(T), zero(T), zero(T), zero(T), zero(T), 0, window, EqualWeight())
    end
end

# Constructor for convenience
RollingLinReg(window::Int, T::Type = Float64) = RollingLinReg{T}(window)

# Implement fit! for RollingLinReg
function OnlineStats.fit!(o::RollingLinReg{T}, yx::Tuple{T, T}) where T
    y, x = yx # Note: LinReg usually takes (y, x)
    oldest_yx = (zero(T), zero(T))
    buffer_is_full = o.nobs == o.window

    if buffer_is_full
        oldest_yx = o.buffer[1]
        oldest_y, oldest_x = oldest_yx
        o.sum_y -= oldest_y
        o.sum_x -= oldest_x
        o.sum_y2 -= oldest_y^2
        o.sum_x2 -= oldest_x^2
        o.sum_xy -= oldest_y * oldest_x # y*x
    end

    fit!(o.buffer, yx) # Add the new pair to the circular buffer

    o.sum_y += y
    o.sum_x += x
    o.sum_y2 += y^2
    o.sum_x2 += x^2
    o.sum_xy += y * x # y*x
    o.nobs = min(o.nobs + 1, o.window) # Increment nobs, capped at window size

    return o # Return the updated stat
end

# Implement nobs for RollingLinReg
OnlineStats.nobs(o::RollingLinReg) = o.nobs

# Implement value for RollingLinReg (returns coefficients [β₀, β₁])
function OnlineStats.value(o::RollingLinReg{T}) where T
    if o.nobs < o.window || o.nobs < 2 # Need at least 2 points for regression
        # Return NaNs for coefficients
        return [NaN, NaN]
    end

    n = DFT(o.nobs)
    sum_x = DFT(o.sum_x)
    sum_y = DFT(o.sum_y)
    sum_x2 = DFT(o.sum_x2)
    sum_xy = DFT(o.sum_xy)

    # Calculate coefficients using formulas derived from minimizing sum of squared errors
    # β₁ = (n * sum(xy) - sum(x) * sum(y)) / (n * sum(x^2) - sum(x)^2)
    # β₀ = mean(y) - β₁ * mean(x) = (sum(y) - β₁ * sum(x)) / n

    denominator = n * sum_x2 - sum_x^2
    if abs(denominator) < eps(DFT) # Avoid division by zero (e.g., if all x are the same)
        return [NaN, NaN]
    end

    beta1 = (n * sum_xy - sum_x * sum_y) / denominator
    beta0 = (sum_y - beta1 * sum_x) / n

    return [beta0, beta1] # Return [intercept, slope (beta)]
end

# Implement coef for RollingLinReg for convenience
OnlineStats.coef(o::RollingLinReg) = value(o)

# Define a cache struct for online beta state using custom rolling stats
mutable struct BetaOnlineCache
    # Store state needed for online beta calculations using custom rolling stats
    cov_stats::Dict{String, RollingCovMatrix{DFT}} # Rolling covariance stat for each asset pair with benchmark
    benchmark_var_stat::RollingVariance{DFT} # Rolling variance stat for benchmark
    reg_stats::Dict{String, RollingLinReg{DFT}} # Rolling regression stat for each asset on benchmark
    benchmark_name::String # Name of the benchmark asset/type
    method::Symbol # :covariance, :regression, or :both
    window::Int # Rolling window size
    roc_period::Int # ROC period for percentage change (used for calculating returns)
    demean::Bool # Whether to demean returns
    last_timestamp::Option{DateTime} # Store the timestamp of the last processed data point
    # Cache for ROC indicators for all assets and the benchmark
    roc_indicators::Dict{String, ROC{DFT}}
    # New fields for caching the last calculated result
    last_calculated_beta::Dict{String, Any} # Store the last calculated beta values per asset. Using Any for flexibility with NamedTuples.
    last_calculation_timestamp::Option{DateTime} # Timestamp of the last beta calculation
end

# Helper function to initialize custom rolling stats objects
function _initialize_online_beta_stats(
    asset_names::Vector{String},
    benchmark_name::String,
    window::Int,
    method::Symbol # Need method here to initialize relevant stats
)::Tuple{Dict{String, RollingCovMatrix{DFT}}, RollingVariance{DFT}, Dict{String, RollingLinReg{DFT}}}
    cov_stats = Dict{String, RollingCovMatrix{DFT}}()
    reg_stats = Dict{String, RollingLinReg{DFT}}()

    # Initialize benchmark variance stat
    benchmark_var_stat = RollingVariance(window, DFT)

    # Initialize asset-specific stats based on method
    if method == :covariance || method == :both
        for asset in asset_names
            cov_stats[asset] = RollingCovMatrix(window, DFT)
        end
    end

    if method == :regression || method == :both
        for asset in asset_names
            reg_stats[asset] = RollingLinReg(window, DFT)
        end
    end

    return cov_stats, benchmark_var_stat, reg_stats
end

# Helper function to get latest OHLCV data since a timestamp from the strategy's universe
function _get_new_ohlcv_data(s::st.Strategy, tf, assets::Vector{String}, since_timestamp::Option{DateTime})::Dict{String, DataFrame}
    new_data_dfs = Dict{String, DataFrame}()
    # Access the strategy's universe to get asset instances
    strategy_universe = st.universe(s)

    for asset_name in assets
        # Find the AssetInstance for the current asset name
        ai = nothing
        for asset_instance in strategy_universe
            if st.raw(asset_instance) == asset_name
                ai = asset_instance
                break
            end
        end

        if isnothing(ai)
            @warn "Asset instance not found in strategy universe for $(asset_name)." color=:yellow
            continue # Skip this asset if not in the universe
        end

        # Access the OHLCV data for the specific timeframe from the asset instance
        if haskey(ai.data, tf)
            ohlcv_df = ai.data[tf]
            if !isempty(ohlcv_df) && "timestamp" in names(ohlcv_df)
                if isnothing(since_timestamp)
                    # If no since_timestamp, return all available data (initial load)
                    new_data_dfs[asset_name] = ohlcv_df
                else
                    # If since_timestamp is provided, filter for data after that timestamp
                    # Assuming timestamps are sorted in the DataFrame
                    new_rows = filter(row -> row.timestamp > since_timestamp, ohlcv_df)
                    if !isempty(new_rows)
                         new_data_dfs[asset_name] = DataFrame(new_rows) # Create a new DataFrame with filtered rows
                    end
                end
            else
                 @debug "OHLCV data for timeframe $(tf) is empty or missing timestamp column for asset $(asset_name)."
             end
        else
            @debug "OHLCV data for timeframe $(tf) not found for asset $(asset_name)."
        end
    end

    if isempty(new_data_dfs) && !isnothing(since_timestamp)
         @debug "No new data found since $(since_timestamp)."
     end

    return new_data_dfs
end

# Helper function to align dataframes by timestamp and calculate returns using cached ROCs
# Returns a Dict{DateTime, Dict{String, DFT}} where inner Dict is asset_name => return_value
# Optimized for processing incremental data in `dfs` using a min-heap
function _align_and_calculate_returns!(
    dfs::Dict{String, DataFrame},
    roc_indicators::Dict{String, ROC{DFT}},
    roc_period::Int,
    window::Int, # Add window as parameter
    timeframe # Add timeframe as parameter
)::Dict{DateTime, Dict{String, DFT}}
    aligned_returns = Dict{DateTime, Dict{String, DFT}}()

    # Item for the heap: (timestamp, asset_name, dataframe_row_index)
    # Collect initial heap items and find the maximum timestamp
    local heap_items = Vector{Tuple{DateTime, String, Int}}()
    local max_shared_timestamp::Option{DateTime} = nothing

    for (asset, df) in dfs
        if !isempty(df) && "timestamp" in names(df)
            # Assuming dataframes are sorted by timestamp
            push!(heap_items, (df[1, :timestamp], asset, 1))
            if isnothing(max_shared_timestamp) || df[end, :timestamp] > max_shared_timestamp
                max_shared_timestamp = df[end, :timestamp]
            end
        end
    end

    if isempty(heap_items) || isnothing(max_shared_timestamp)
        @debug "No data to process for alignment."
        return aligned_returns # No data to process
    end

    # Calculate the minimum acceptable timestamp based on the window and timeframe
    local min_acceptable_timestamp::DateTime
    
    # Assuming timeframe is a Dates.Period and supports multiplication by an integer
    try
         min_acceptable_timestamp = max_shared_timestamp - window * timeframe
         @info "Calculated minimum acceptable timestamp for window: $(min_acceptable_timestamp) (Latest: $(max_shared_timestamp), Window: $(window), Timeframe: $(timeframe))"
    catch e
         @warn "Could not calculate minimum acceptable timestamp based on timeframe and window." exception=e
         # Fallback: process all data if calculation fails
         min_acceptable_timestamp = DateTime(0) # Effectively no lower limit
    end

    # Create a min-heap ordered by timestamp
    min_heap = BinaryHeap(Base.By(x -> x[1]), heap_items)

    # Store original dataframes for easy access inside the loop
    original_dfs = Dict(asset => df for (asset, df) in dfs)
    # Store the set of all original asset names for strict alignment check
    original_asset_names = Set(keys(dfs))

    # Process data chronologically using the min-heap
    # We will build a list of aligned data points directly instead of a dictionary
    local aligned_data_points = Vector{Dict{String, DFT}}()
    local aligned_timestamps = Vector{DateTime}()

    while !isempty(min_heap)
        # Get the minimum timestamp item from the heap by popping
        # We will push it back if it's outside the acceptable window
        min_ts_item = pop!(min_heap)
        min_timestamp = min_ts_item[1]

        # If the minimum timestamp is older than the acceptable window, stop processing
        if min_timestamp < min_acceptable_timestamp
            @debug "Minimum heap timestamp $(min_timestamp) is older than acceptable window start $(min_acceptable_timestamp). Stopping processing."
            push!(min_heap, min_ts_item) # Push the item back as we are stopping
            break # Stop processing older data
        end

        # The min_ts_item has already been popped, now collect others with the same timestamp
        # Use the existing helper function to collect data at min_timestamp
        min_timestamp, assets_at_current_timestamp = _collect_and_align_timestamp_data!(min_heap, original_asset_names, min_ts_item, min_acceptable_timestamp) # Pass the already popped item

        if isnothing(min_timestamp)
             @debug "_collect_and_align_timestamp_data! returned nothing timestamp but heap is not empty."
             continue
         end

        # Calculate returns and add to a temporary dictionary for this timestamp
        local current_returns = Dict{String, DFT}()
        local all_assets_roc_ready = true

        for (asset, idx) in assets_at_current_timestamp
            df = original_dfs[asset]
            if idx <= nrow(df) && df[idx, :timestamp] == min_timestamp && "close" in names(df)
                close_price = df[idx, :close]

                if haskey(roc_indicators, asset)
                    fit!(roc_indicators[asset], close_price)
                    latest_return = value(roc_indicators[asset])

                    if nobs(roc_indicators[asset]) >= roc_period && !ismissing(latest_return) && !isnan(latest_return)
                        current_returns[asset] = latest_return
                    else
                        all_assets_roc_ready = false
                        # Do not break, continue to fit ROC for other assets
                    end
                else
                    @warn "ROC indicator not found for asset \"$(asset)\". Cannot calculate return."
                    all_assets_roc_ready = false
                    break # Cannot form a complete aligned data point
                end
            else
                @debug "Data missing or invalid for asset $(asset) at timestamp $(min_timestamp)."
                all_assets_roc_ready = false
                break
            end
        end

        # If all assets needed for this timestamp had their ROC ready, add the aligned data point
        if all_assets_roc_ready && !isempty(current_returns) && length(current_returns) == length(original_asset_names)
            push!(aligned_timestamps, min_timestamp)
            push!(aligned_data_points, current_returns)
        else
             @debug "Skipping timestamp $(min_timestamp) due to incomplete or unready ROC calculations for necessary assets."
         end

        # Add the next data point from the processed dataframes to the heap
        _add_next_data_to_heap!(min_heap, assets_at_current_timestamp, original_dfs, min_acceptable_timestamp)
    end

    # Convert the list of aligned data points and timestamps back to the required dictionary format
    # This step might still be slow for large datasets, but the processing loop is improved.
    # Further optimization might require changing the return type or how this is consumed.
    aligned_returns = Dict{DateTime, Dict{String, DFT}}()
    for i in 1:length(aligned_timestamps)
        aligned_returns[aligned_timestamps[i]] = aligned_data_points[i]
    end

    return aligned_returns
end

# Helper function to collect and align data points at the minimum timestamp
function _collect_and_align_timestamp_data!(
    min_heap::BinaryHeap{Tuple{DateTime, String, Int}}, # Specify heap type
    original_asset_names::Set{String},
    initial_item::Tuple{DateTime, String, Int}, # Accept the item already popped
    min_acceptable_timestamp::DateTime # Add min_acceptable_timestamp
)::Tuple{Option{DateTime}, Dict{String, Int}}

    if isempty(min_heap) && isnothing(initial_item)
        return nothing, Dict{String, Int}() # No data to process
    end

    # The minimum timestamp item is already provided
    min_timestamp, current_asset, current_idx = initial_item

    # Only process if the minimum timestamp is within the acceptable window
    if min_timestamp < min_acceptable_timestamp
        @debug "Skipping timestamp $(min_timestamp) in _collect_and_align_timestamp_data! as it is older than acceptable window start $(min_acceptable_timestamp)."
        # Do not collect other items at this timestamp, as we are discarding this timestamp
        return nothing, Dict{String, Int}()
    end

    # Collect all data points that share the same minimum timestamp
    assets_at_current_timestamp = Dict{String, Int}() # Store asset_name => index for this timestamp
    assets_at_current_timestamp[current_asset] = current_idx # Add the first asset at this timestamp

    # Use peek to check without removing, and extract if timestamp matches
    while !isempty(min_heap) && first(min_heap)[1] == min_timestamp
        next_ts, next_asset, next_idx = pop!(min_heap)
        assets_at_current_timestamp[next_asset] = next_idx
    end

    return min_timestamp, assets_at_current_timestamp
end

# Helper function to add the next data points to the heap
function _add_next_data_to_heap!(
    min_heap::BinaryHeap{Tuple{DateTime, String, Int}}, # Specify heap type
    assets_at_current_timestamp::Dict{String, Int},
    original_dfs::Dict{String, DataFrame},
    min_acceptable_timestamp::DateTime # Add min_acceptable_timestamp
)
    # Add the next data point from the processed dataframes to the heap
    for (asset, idx) in assets_at_current_timestamp
        df = original_dfs[asset]
        next_idx = idx + 1
        if next_idx <= nrow(df) && df[next_idx, :timestamp] >= min_acceptable_timestamp
            push!(min_heap, (df[next_idx, :timestamp], asset, next_idx))
        end
    end
    return nothing # This function modifies the heap in place
end

# New helper function for parameter validation and initialization
function _validate_and_init_params(method::Symbol)::Tuple{Vector{Symbol}, String}
    local result_cols::Vector{Symbol}
    if method == :covariance
        result_cols = [:Asset, :Beta_Covariance]
    elseif method == :regression
        result_cols = [:Asset, :Beta_Regression]
    elseif method == :both
        result_cols = [:Asset, :Beta_Covariance, :Beta_Regression]
    else
        error("Invalid method: $(method). Must be :covariance, :regression, or :both.")
    end
    return result_cols, "" # Benchmark name string is determined later
end

# New helper function for preparing asset and benchmark dataframes
function _prepare_asset_data(
    s::st.Strategy,
    tf,
    benchmark::Union{Symbol, String, DataFrame},
    min_vol::DFT,
    benchmark_name_str_ref::Ref{String} # Pass benchmark_name_str by reference to modify it
)::Tuple{Dict{String, DataFrame}, Option{DataFrame}, Vector{String}, String}

    local asset_dfs::Dict{String, DataFrame} = Dict()
    local benchmark_df::Option{DataFrame} = nothing
    local all_relevant_assets::Vector{String} = []
    local benchmark_asset_name::String = ""

    # 1. Get the universe data for the specified timeframe and flatten it
    universe_asset_dfs_flattened = st.coll.flatten(st.universe(s); noempty=true)
    universe_dfs_for_tf = get(universe_asset_dfs_flattened, tf, DataFrame[])

    # Initial populate asset_dfs from universe data for the timeframe
    local initial_universe_asset_dfs = Dict{String, DataFrame}()
    for df in universe_dfs_for_tf
        if haskey(metadata(df), "asset_instance")
            asset_name = raw(metadata(df, "asset_instance"))
            initial_universe_asset_dfs[asset_name] = df
        else
            @warn "DataFrame in flattened universe data for timeframe $(tf) is missing 'asset_instance' metadata." color=:yellow
        end
    end

    local candidate_assets = collect(keys(initial_universe_asset_dfs))

    # 2. Apply minimum volume filter to initial candidate assets
    local all_assets_after_volume_filter::Vector{String} = tickers(st.getexchange!(s.exchange), s.qc; min_vol=min_vol, as_vec=true)

    # Filter down the initial_universe_asset_dfs to only include assets passing volume filter
    asset_dfs = Dict{String, DataFrame}()
    for asset_name in all_assets_after_volume_filter
        if haskey(initial_universe_asset_dfs, asset_name)
            # Ensure the DataFrame is not empty and has a timestamp column
            df = initial_universe_asset_dfs[asset_name]
            if !isempty(df) && "timestamp" in names(df)
                asset_dfs[asset_name] = df
            else
                @debug "Skipping asset $(asset_name) due to empty DataFrame or missing timestamp column."
            end
        else
            @debug "Asset $(asset_name) from volume filter not found in initial universe data for timeframe $(tf)."
        end
    end

    # Update candidate_assets to reflect those that passed volume and data checks
    candidate_assets = collect(keys(asset_dfs))

    # 3. Determine the benchmark asset/DataFrame from the volume-filtered set
    if typeof(benchmark) <: DataFrame
        benchmark_df = benchmark
        if !("timestamp" in names(benchmark_df)) || !(size(benchmark_df, 2) >= 2)
            @error "External benchmark DataFrame must contain a 'timestamp' column and at least one value column."
            return Dict(), nothing, [], "" # Return empty on error
        end
        # Attempt to get asset name from metadata, fallback to a default name
        if haskey(metadata(benchmark), "asset_instance")
            benchmark_asset_name = raw(metadata(benchmark, "asset_instance"))
        else
            benchmark_asset_name = "external_benchmark"
            @warn "External benchmark DataFrame is missing 'asset_instance' metadata. Using 'external_benchmark' as name." color=:yellow
        end

        # If the benchmark DataFrame's asset is not in the volume-filtered set, add it
        if !(benchmark_asset_name in candidate_assets)
            @warn "External benchmark asset \"$(benchmark_asset_name)\" is not in the volume-filtered universe. Adding it for calculation." color=:yellow
            push!(candidate_assets, benchmark_asset_name)
            asset_dfs[benchmark_asset_name] = benchmark_df
        end

    elseif typeof(benchmark) <: Symbol
        if benchmark == :top_asset
            # Determine top asset based on quote volume from the *already volume-filtered* assets
            candidate_assets_with_volume = [(asset, _calculate_quote_volume(asset_dfs[asset])) for asset in candidate_assets]
            sort!(candidate_assets_with_volume, by=x->x[2], rev=true)
            if isempty(candidate_assets_with_volume) || candidate_assets_with_volume[1][2] == -Inf
                @warn "No assets meet the minimum volume requirement or have valid close/volume data to determine top asset benchmark from the filtered set."
                return Dict(), nothing, [], ""
            end
            benchmark_asset_name = candidate_assets_with_volume[1][1] # Set benchmark_asset_name directly
            # Get benchmark df from the filtered set
            benchmark_df = asset_dfs[benchmark_asset_name]

        elseif benchmark == :top_5_percent
            @warn "Top 5% benchmark aggregation in online mode is not fully implemented. Aggregating by averaging close prices." # Info about aggregation method

            # Determine top assets based on cumulative quote volume from the *already volume-filtered* assets
            candidate_assets_with_volume = [(asset, _calculate_quote_volume(asset_dfs[asset])) for asset in candidate_assets]
            sort!(candidate_assets_with_volume, by=x->x[2], rev=true)

            if isempty(candidate_assets_with_volume) || candidate_assets_with_volume[1][2] == -Inf
                @warn "No assets meet the minimum volume requirement or have valid close/volume data to determine top 5% benchmark from the filtered set."
                return Dict(), nothing, [], ""
            end

            local total_volume = sum(v for (a, v) in candidate_assets_with_volume if v > 0)
            local cumulative_volume = 0.0
            local top_5_percent_assets = String[]

            for (asset, volume) in candidate_assets_with_volume
                if volume > 0
                    cumulative_volume += volume
                    push!(top_5_percent_assets, asset)
                    if cumulative_volume / total_volume >= 0.05
                        break # Stop once 5% cumulative volume is reached
                    end
                end
            end

            if isempty(top_5_percent_assets)
                @warn "Could not find enough assets with positive quote volume to reach 5% of total volume."
                return Dict(), nothing, [], "" # Return empty if no assets selected
            end

            # Aggregate data for the top 5% assets
            local aggregated_df::Option{DataFrame} = nothing
            local first_asset = true

            for asset_name in top_5_percent_assets
                if haskey(asset_dfs, asset_name)
                    df = asset_dfs[asset_name][!, [:timestamp, :close]] # Select only timestamp and close
                    if first_asset
                        aggregated_df = df
                        first_asset = false
                    else
                        # Merge with existing aggregated_df on timestamp and add close prices
                        # Need to rename columns to avoid conflicts before merging
                        rename!(df, :close => Symbol("close_", asset_name))
                        if !isnothing(aggregated_df)
                            aggregated_df = outerjoin(aggregated_df, df, on=:timestamp)
                        end
                    end
                end
            end

            if isnothing(aggregated_df) || isempty(aggregated_df)
                @warn "Failed to aggregate data for top 5% assets."
                return Dict(), nothing, [], "" # Return empty if aggregation fails
            end

            # Calculate the average close price for each timestamp in the aggregated DataFrame
            local benchmark_close_prices = Vector{DFT}()
            local timestamps = aggregated_df.timestamp

            for row in eachrow(aggregated_df)
                local sum_closes = DFT(0.0)
                local count_closes = 0
                for asset_name in top_5_percent_assets
                    col_name = Symbol("close_", asset_name)
                    if hasproperty(row, col_name) && !ismissing(row[col_name]) && !isnan(row[col_name])
                        sum_closes += row[col_name]
                        count_closes += 1
                    end
                end
                if count_closes > 0
                    push!(benchmark_close_prices, sum_closes / count_closes)
                else
                    push!(benchmark_close_prices, NaN)
                end
            end

            # Create the final benchmark DataFrame with timestamp and the aggregated close price
            benchmark_df = DataFrame(:timestamp => timestamps, :close => benchmark_close_prices)
            benchmark_asset_name = "Top5PercentBenchmark" # Set a descriptive name directly

            # Add the aggregated benchmark DataFrame to asset_dfs
            asset_dfs[benchmark_asset_name] = benchmark_df

            # Ensure all_relevant_assets includes the new benchmark asset name
            if !(benchmark_asset_name in candidate_assets) # Check against initial candidate_assets before aggregation
                 # This case should ideally not happen if we add it to asset_dfs, but as a safeguard
                 push!(candidate_assets, benchmark_asset_name) # Add to candidate_assets temporarily for all_relevant_assets construction
             end

        else
            @error "Invalid benchmark symbol: $(benchmark). Must be :top_asset or :top_5_percent."
            return Dict(), nothing, [], ""
        end

    elseif typeof(benchmark) <: String
        benchmark_asset_name = benchmark # Set benchmark_asset_name directly
        # Check if the chosen benchmark asset exists in the *volume-filtered* data
        if !haskey(asset_dfs, benchmark_asset_name)
            @error "Specified benchmark asset \"$(benchmark_asset_name)\" is not available in the volume-filtered universe data for timeframe $(tf)."
            return Dict(), nothing, [], "" # Return empty if benchmark data is missing after filtering
        end
        benchmark_df = asset_dfs[benchmark_asset_name] # Get benchmark df from the filtered set

    else
         @error "Invalid benchmark type: $(typeof(benchmark)). Must be Symbol, String, or DataFrame."
         return Dict(), nothing, [], ""
     end

    # 4. Final list of all relevant assets for calculations
    # This includes all assets in asset_dfs, which now consistently includes the benchmark
    all_relevant_assets = collect(keys(asset_dfs))

    # Set benchmark_name_str_ref for the cache initialization
    benchmark_name_str_ref[] = benchmark_asset_name

    return asset_dfs, benchmark_df, all_relevant_assets, benchmark_asset_name
end

# New helper function for getting or initializing the beta cache
function _get_or_initialize_beta_cache(
    s::st.Strategy,
    benchmark_name_str::String,
    method::Symbol,
    window::Int,
    roc_period::Int,
    demean::Bool,
    assets_for_beta_calc::Vector{String},
    all_relevant_assets::Vector{String}
)::Tuple{BetaOnlineCache, Bool}

    local beta_cache = nothing
    local reinitialize_required = false

    if haskey(s.attrs, :_beta_state)
        local current_beta_state = s.attrs[:_beta_state]
        if typeof(current_beta_state) <: BetaOnlineCache &&
           current_beta_state.benchmark_name == benchmark_name_str &&
           current_beta_state.method == method &&
           current_beta_state.window == window &&
           current_beta_state.roc_period == roc_period &&
           current_beta_state.demean == demean
             beta_cache = current_beta_state
             @debug "Reusing compatible online beta state from strategy attributes."
         else
             @warn "Cached online beta state is incompatible (parameters or type changed). Reinitializing." required_params=(benchmark_name=benchmark_name_str, method=method, window=window, roc_period=roc_period, demean=demean) typeof_cached=typeof(current_beta_state)
             reinitialize_required = true
          end
    else
        @debug "No existing online beta state found in strategy attributes. Initializing new state."
        reinitialize_required = true
    end

    if reinitialize_required
        @debug "Initializing ROC indicators and online stats for reinitialization."
        current_roc_indicators = Dict{String, ROC{DFT}}()
        for asset in all_relevant_assets
             current_roc_indicators[asset] = ROC{DFT}(period=roc_period)
        end

        # Initialize online stats
        initialized_stats = _initialize_online_beta_stats(assets_for_beta_calc, benchmark_name_str, window, method)

        beta_cache = BetaOnlineCache(
            initialized_stats[1], # cov_stats
            initialized_stats[2], # benchmark_var_stat
            initialized_stats[3], # reg_stats
            benchmark_name_str,
            method,
            window,
            roc_period,
            demean,
            nothing, # last_timestamp
            current_roc_indicators,
            Dict{String, Any}(), # Initialize empty last_calculated_beta
            nothing # Initialize empty last_calculation_timestamp
        )
        s.attrs[:_beta_state] = beta_cache
    end

    return beta_cache, reinitialize_required
end

# New helper function for processing new data and updating the cache
function _process_and_update_cache!(
    s::st.Strategy,
    tf,
    beta_cache::BetaOnlineCache,
    reinitialize_required::Bool,
    asset_dfs::Dict{String, DataFrame}, # Keep original asset_dfs for filtering
    all_relevant_assets::Vector{String},
    assets_for_beta_calc::Vector{String},
    benchmark_asset_name::String
)::Tuple{Set{String}, Bool} # Returns set of asset names needing beta calculation and a flag indicating if new data was processed

    # Determine the overall maximum timestamp across all relevant assets' data
    local max_shared_timestamp::Option{DateTime} = nothing
    for asset_name in all_relevant_assets
        if haskey(asset_dfs, asset_name) && !isempty(asset_dfs[asset_name])
            df = asset_dfs[asset_name]
            if "timestamp" in names(df)
                if isnothing(max_shared_timestamp) || df[end, :timestamp] > max_shared_timestamp
                    max_shared_timestamp = df[end, :timestamp]
                end
            end
        end
    end

    if isnothing(max_shared_timestamp)
         @debug "No data available to determine max timestamp. Returning empty set of assets to recalculate."
         return Set{String}(), false
     end

    # Calculate the minimum acceptable timestamp based on the window and timeframe relative to the overall max timestamp
    local min_acceptable_timestamp::DateTime
    local timeframe = s.timeframe # Assuming s.timeframe is the correct timeframe period
    try
         min_acceptable_timestamp = max_shared_timestamp - beta_cache.window * timeframe
         @info "Processing data from $(min_acceptable_timestamp) to $(max_shared_timestamp) (Window: $(beta_cache.window), Timeframe: $(timeframe))"
    catch e
         @warn "Could not calculate minimum acceptable timestamp based on timeframe and window. Processing all available data." exception=e
         min_acceptable_timestamp = DateTime(0) # Process all data if calculation fails
    end

    # Filter input dataframes to include only data within the calculated window
    local data_to_process_dfs::Dict{String, DataFrame} = Dict()
    local new_data_found = false # Track if any new data (relative to last_timestamp) is found in the window

    for asset_name in all_relevant_assets
        if haskey(asset_dfs, asset_name) && !isempty(asset_dfs[asset_name]) && "timestamp" in names(asset_dfs[asset_name])
            df = asset_dfs[asset_name]
            # Filter rows within the acceptable timestamp range
            filtered_df = filter(row -> row.timestamp >= min_acceptable_timestamp, df)
            if !isempty(filtered_df)
                data_to_process_dfs[asset_name] = filtered_df
                # Check if any of this filtered data is newer than the last processed timestamp
                if isnothing(beta_cache.last_timestamp) || filtered_df[end, :timestamp] > beta_cache.last_timestamp
                     new_data_found = true
                 end
            else
                 @debug "No data within acceptable window for asset $(asset_name)."
             end
        end
    end

    if isempty(data_to_process_dfs)
         @debug "No relevant data within window to process. Returning empty set of assets to recalculate."
         return Set{String}(), false
     end

    # Determine if new data was processed overall. This is true if new data was found in the window
    # OR if reinitialization is required (as reinit implies processing all available data in the window)
    local new_data_processed = new_data_found || reinitialize_required

    local current_roc_indicators = beta_cache.roc_indicators

    aligned_new_returns = _align_and_calculate_returns!(
        data_to_process_dfs,
        current_roc_indicators,
        beta_cache.roc_period,
        beta_cache.window,
        s.timeframe
    )

    sorted_new_timestamps = sort(collect(keys(aligned_new_returns)))

    local assets_to_recalculate = Set{String}()

    @info "Processing $(length(sorted_new_timestamps)) aligned timestamps."
    # Process the aligned returns to fit the custom rolling statistics
    for timestamp in sorted_new_timestamps
        data_point_dict = aligned_new_returns[timestamp]
        benchmark_return = get(data_point_dict, benchmark_asset_name, missing)

        if ismissing(benchmark_return)
            @debug "Benchmark return missing at timestamp $(timestamp). Skipping this data point for stat fitting."
            continue
        end

        # Fit benchmark variance stat
        benchmark_return_demeaned = beta_cache.demean ? benchmark_return - value(beta_cache.roc_indicators[benchmark_asset_name]) : benchmark_return
        fit!(beta_cache.benchmark_var_stat, benchmark_return_demeaned)

        for asset_name in assets_for_beta_calc
            asset_return = get(data_point_dict, asset_name, missing)
            if ismissing(asset_return)
                @debug "Asset return missing for $(asset_name) at timestamp $(timestamp). Skipping stat fitting for this asset."
                continue
            end

            # Calculate demeaned returns once for covariance and regression
            asset_return_demeaned = beta_cache.demean ? asset_return - value(beta_cache.roc_indicators[asset_name]) : asset_return

            # Fit covariance stat (using demeaned returns)
            if haskey(beta_cache.cov_stats, asset_name) # Use asset_name as key
                fit!(beta_cache.cov_stats[asset_name], (asset_return_demeaned, benchmark_return_demeaned))
            end

            # Fit regression stat (using non-demeaned returns, y=asset, x=benchmark)
            if haskey(beta_cache.reg_stats, asset_name) # Use asset_name as key
                fit!(beta_cache.reg_stats[asset_name], (asset_return, benchmark_return))
            end
        end
    end

    # After processing all relevant timestamps, determine which assets need recalculation
    # This is typically when their rolling stats have accumulated the required window size
    for asset_name in assets_for_beta_calc
        # Check if the window is full for either covariance or regression stat for this asset
        if (haskey(beta_cache.cov_stats, asset_name) && nobs(beta_cache.cov_stats[asset_name]) >= beta_cache.window) ||
           (haskey(beta_cache.reg_stats, asset_name) && nobs(beta_cache.reg_stats[asset_name]) >= beta_cache.window)
            push!(assets_to_recalculate, asset_name)
        end
    end

    # Update last_timestamp if any data was processed and aligned
    if !isempty(sorted_new_timestamps)
         beta_cache.last_timestamp = last(sorted_new_timestamps)
     end

    # If reinitializing, recalculate for all assets_for_beta_calc
    if reinitialize_required
        union!(assets_to_recalculate, Set(assets_for_beta_calc))
    end

    return assets_to_recalculate, new_data_processed
end

# New helper function to calculate beta results and cache them for specific assets
function _calculate_and_cache_beta(
    beta_cache::BetaOnlineCache,
    assets_to_recalculate::Set{String}, # Calculate only for these assets
    benchmark_asset_name::String
)
    # Do not clear the entire cache, only update entries for assets being recalculated.
    # The main function will reconstruct the DataFrame from the full cache.

    for asset_name in assets_to_recalculate # Iterate only over assets that need recalculation
        local beta_cov::Union{DFT, Missing} = missing
        local beta_reg::Union{DFT, Missing} = missing

        stat_pair_key = asset_name # The key for cov_stats and reg_stats is just the asset name
        
        # Check if the RollingVariance stat has enough observations
        if nobs(beta_cache.benchmark_var_stat) >= beta_cache.window
            # Get the rolling variance value
            benchmark_var_val = value(beta_cache.benchmark_var_stat)

            # Check for non-zero benchmark variance before calculating covariance-based beta
            if !isnan(benchmark_var_val) && abs(benchmark_var_val) > eps(DFT)
                # Calculate Beta by Covariance
                if beta_cache.method == :covariance || beta_cache.method == :both
                    # Check if the RollingCovMatrix stat has enough observations
                    if haskey(beta_cache.cov_stats, stat_pair_key) && nobs(beta_cache.cov_stats[stat_pair_key]) >= beta_cache.window
                        # Get the rolling covariance matrix and extract the covariance value
                        cov_matrix = value(beta_cache.cov_stats[stat_pair_key])
                        cov_val = cov_matrix[1, 2] # Cov(Asset, Benchmark)
                        
                        # Ensure the covariance value is not NaN
                        if !isnan(cov_val)
                            beta_cov = cov_val / benchmark_var_val
                        else
                            beta_cov = missing
                        end
                    end
                end
            else
                @debug "Cannot calculate Beta by Covariance for $(asset_name): Benchmark variance is NaN, zero or near zero." timestamp=beta_cache.last_timestamp var=benchmark_var_val
                beta_cov = missing
            end
        else
            @debug "Benchmark variance rolling window not full for calculation." nobs=nobs(beta_cache.benchmark_var_stat) window=beta_cache.window
            beta_cov = missing
        end

        # Calculate Beta by Regression
        if beta_cache.method == :regression || beta_cache.method == :both
            # Check if the RollingLinReg stat has enough observations
            if haskey(beta_cache.reg_stats, stat_pair_key) && nobs(beta_cache.reg_stats[stat_pair_key]) >= beta_cache.window
                # Get the rolling regression coefficients
                reg_coeffs = coef(beta_cache.reg_stats[stat_pair_key]) # Returns [β₀, β₁]
                
                # Ensure the regression has enough observations and beta coefficient is not NaN/Inf
                # The value function for RollingLinReg already returns [NaN, NaN] if not enough data or denominator is zero
                if length(reg_coeffs) == 2 && !isnan(reg_coeffs[2]) && !isinf(reg_coeffs[2])
                     beta_reg = reg_coeffs[2] # The beta coefficient is β₁ (the slope)
                 else
                    beta_reg = missing
                 end
            end
        end

        local asset_result
        if beta_cache.method == :both
            asset_result = (Asset=asset_name, Beta_Covariance=beta_cov, Beta_Regression=beta_reg)
        elseif beta_cache.method == :covariance
            asset_result = (Asset=asset_name, Beta_Covariance=beta_cov)
        elseif beta_cache.method == :regression
            asset_result = (Asset=asset_name, Beta_Regression=beta_reg)
        end
        # Update the cached result for this specific asset
        beta_cache.last_calculated_beta[asset_name] = asset_result
    end

    # Update last calculation timestamp only if any calculations occurred
    if !isempty(assets_to_recalculate) && !isnothing(beta_cache.last_timestamp)
         beta_cache.last_calculation_timestamp = beta_cache.last_timestamp
     end

    # This function now just updates the cache, the main function builds the DataFrame
    return nothing
end

# Refactored main function
function beta_indicator_online(
    s::st.Strategy,
    tf=s.timeframe;
    benchmark::Union{Symbol, String, DataFrame} = :top_asset,
    min_vol::DFT = 1e6,
    method::Symbol = :covariance,
    window::Int = 100,
    roc_period::Int = 1,
    demean::Bool = false
)::DataFrame

    # 1. Parameter validation and initialization
    local benchmark_name_str_ref = Ref{String}("")
    result_cols, _ = _validate_and_init_params(method)

    # 2. Prepare asset and benchmark data
    asset_dfs, benchmark_df, all_relevant_assets, benchmark_asset_name = _prepare_asset_data(s, tf, benchmark, min_vol, benchmark_name_str_ref)

    if isempty(asset_dfs) || isnothing(benchmark_df) || isempty(benchmark_df)
         @warn "Insufficient data or benchmark missing after preparation."
         return DataFrame(result_cols, [])
    end

    local benchmark_name_str = benchmark_name_str_ref[]

    local assets_for_beta_calc = collect(keys(asset_dfs))
    filter!(asset -> asset != benchmark_asset_name, assets_for_beta_calc)

    if isempty(assets_for_beta_calc)
         @warn "No assets remaining to calculate beta for after excluding benchmark."
         return DataFrame(result_cols, [])
    end

    # 3. Get or initialize the beta cache
    beta_cache, reinitialize_required = _get_or_initialize_beta_cache(
        s,
        benchmark_name_str,
        method,
        window,
        roc_period,
        demean,
        assets_for_beta_calc,
        all_relevant_assets
    )

    # 4. Process new data and update cache state, get list of assets needing recalculation
    local assets_to_recalculate, new_data_processed = _process_and_update_cache!(
        s,
        tf,
        beta_cache,
        reinitialize_required,
        asset_dfs, # Pass original asset_dfs for reinitialization data
        all_relevant_assets,
        assets_for_beta_calc,
        benchmark_asset_name
    )

    # 5. Calculate and cache beta results only for needed assets
    if !isempty(assets_to_recalculate) || reinitialize_required
        @debug "Calculating beta values for $(length(assets_to_recalculate)) assets."
        _calculate_and_cache_beta(
            beta_cache,
            assets_to_recalculate,
            benchmark_asset_name
        )
        # Update last calculation timestamp is done inside _calculate_and_cache_beta now
    elseif !new_data_processed # If no new data was processed, return cached results
        @debug "No new data processed, returning cached beta values."
        # Fall through to the section that reconstructs the DataFrame from cache
    else # If new data was processed but no assets needed recalculation (e.g., window not full)
        @debug "New data processed, but no assets met recalculation criteria (e.g. window not full). Returning current cached values."
        # Fall through to the section that reconstructs the DataFrame from cache
    end

    # Always reconstruct the result DataFrame from the latest cached values for all assets that were processed
    local final_results_data = []
    for asset in assets_for_beta_calc
        if haskey(beta_cache.last_calculated_beta, asset)
            push!(final_results_data, beta_cache.last_calculated_beta[asset])
        end
    end

    if isempty(final_results_data)
         @debug "No cached beta results available for any asset."
         return DataFrame([col => Vector{DFT}() for col in result_cols])
     else
         return DataFrame(final_results_data)
     end
end
