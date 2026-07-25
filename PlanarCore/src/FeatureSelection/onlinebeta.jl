using OnlineTechnicalIndicators: ROC, OnlineStatsBase
using OnlineStats:
    fit!,
    value,
    Variance,
    Mean,
    LinReg,
    nobs,
    coef,
    CovMatrix,
    MovingWindow,
    StatLag,
    OnlineStats
using .OnlineStatsBase: OnlineStat, value, nobs, merge!, CircBuff, EqualWeight # Added CircBuff
using .da.DataFrames:
    DataFrame, metadata, names, findfirst, size, DataFrameRow, filter, nrow, rename!
using .st.Dates: DateTime
using .st.Misc: DFT, Option # Assuming DFT is in Misc
using .st: Strategy, AssetInstance, universe, raw # Added imports for strategy and asset access
using .da.DataStructures: BinaryHeap, isempty, push!, peek, pop! # Added for min-heap

# Helper function to calculate quote volume safely
function _calculate_quote_volume(df::DataFrame)::DFT
    if isempty(df) ||
        !hasproperty(df, :close) ||
        !hasproperty(df, :volume) ||
        ismissing(df[end, :close]) ||
        ismissing(df[end, :volume]) ||
        isnan(df[end, :close]) ||
        isnan(df[end, :volume])
        return DFT(-Inf) # Use -Inf to handle cases with missing/invalid data during sorting
    else
        return DFT(df[end, :close] * df[end, :volume])
    end
end

# Define a new OnlineStat for rolling variance
mutable struct RollingVariance{T<:Number,W<:EqualWeight} <: OnlineStat{T}
    buffer::CircBuff{T}
    sum_x::T
    sum_x2::T
    nobs::Int
    window::Int
    weight::W

    function RollingVariance{T}(
        window::Int, weight::W=EqualWeight()
    ) where {T,W<:EqualWeight}
        window > 0 || error("Window size must be positive.")
        new{T,W}(CircBuff(T, window), zero(T), zero(T), 0, window, weight)
    end
end

# Constructor for convenience
RollingVariance(window::Int, T::Type=Float64) = RollingVariance{T}(window)

# Implement fit! for RollingVariance
function OnlineStats.fit!(o::RollingVariance{T}, x::T) where {T}
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
mutable struct RollingCovMatrix{T<:Number} <: OnlineStat{Tuple{T,T}} # CovMatrix takes pairs (x, y)
    buffer::CircBuff{Tuple{T,T}}
    sum_x::T
    sum_y::T
    sum_x2::T # Needed for individual variances in CovMatrix calculation
    sum_y2::T # Needed for individual variances
    sum_xy::T # Needed for covariance
    nobs::Int
    window::Int
    weight::EqualWeight # Assuming EqualWeight for rolling window

    function RollingCovMatrix{T}(window::Int) where {T}
        window > 0 || error("Window size must be positive.")
        new{T}(
            CircBuff(Tuple{T,T}, window),
            zero(T),
            zero(T),
            zero(T),
            zero(T),
            zero(T),
            0,
            window,
            EqualWeight(),
        )
    end
end

# Constructor for convenience
RollingCovMatrix(window::Int, T::Type=Float64) = RollingCovMatrix{T}(window)

# Implement fit! for RollingCovMatrix
function OnlineStats.fit!(o::RollingCovMatrix{T}, xy::Tuple{T,T}) where {T}
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
function OnlineStats.value(o::RollingCovMatrix{T}) where {T}
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
mutable struct RollingLinReg{T<:Number} <: OnlineStat{Tuple{T,T}} # Takes (y, x)
    buffer::CircBuff{Tuple{T,T}}
    sum_x::T # Sum of predictor (benchmark return)
    sum_y::T # Sum of response (asset return)
    sum_x2::T # Sum of squares of predictor
    sum_y2::T # Sum of squares of response (needed for R^2, but not strictly for coeffs)
    sum_xy::T # Sum of products of predictor and response
    nobs::Int
    window::Int
    weight::EqualWeight # Assuming EqualWeight for rolling window

    function RollingLinReg{T}(window::Int) where {T}
        window > 0 || error("Window size must be positive.")
        # Initialize sums and sum of squares to zero
        new{T}(
            CircBuff(Tuple{T,T}, window),
            zero(T),
            zero(T),
            zero(T),
            zero(T),
            zero(T),
            0,
            window,
            EqualWeight(),
        )
    end
end

# Constructor for convenience
RollingLinReg(window::Int, T::Type=Float64) = RollingLinReg{T}(window)

# Implement fit! for RollingLinReg
function OnlineStats.fit!(o::RollingLinReg{T}, yx::Tuple{T,T}) where {T}
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
function OnlineStats.value(o::RollingLinReg{T}) where {T}
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
    cov_stats::Dict{String,RollingCovMatrix{DFT}} # Rolling covariance stat for each asset pair with benchmark
    benchmark_var_stat::RollingVariance{DFT} # Rolling variance stat for benchmark
    reg_stats::Dict{String,RollingLinReg{DFT}} # Rolling regression stat for each asset on benchmark
    benchmark_specifier::Union{String, Vector{String}} # Name of the single benchmark asset or list of asset names for aggregated benchmark
    method::Symbol # :covariance, :regression, or :both
    window::Int # Rolling window size
    roc_period::Int # ROC period for percentage change (used for calculating returns)
    demean::Bool # Whether to demean returns
    last_timestamp::Option{DateTime} # Store the timestamp of the last processed data point
    # Cache for ROC indicators for all assets and the benchmark
    roc_indicators::Dict{String,ROC{DFT}}
    # New fields for caching the last calculated result
    last_calculated_beta::Dict{String,Any} # Store the last calculated beta values per asset. Using Any for flexibility with NamedTuples.
    last_calculation_timestamp::Option{DateTime} # Timestamp of the last beta calculation
end

# Helper function to initialize custom rolling stats objects
function _initialize_online_beta_stats(
    asset_names::Vector{String},
    benchmark_specifier::Union{String, Vector{String}},
    window::Int,
    method::Symbol, # Need method here to initialize relevant stats
)::Tuple{
    Dict{String,RollingCovMatrix{DFT}},RollingVariance{DFT},Dict{String,RollingLinReg{DFT}}
}
    cov_stats = Dict{String,RollingCovMatrix{DFT}}()
    reg_stats = Dict{String,RollingLinReg{DFT}}()

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
function _get_new_ohlcv_data(
    s::st.Strategy, tf, assets::Vector{String}, since_timestamp::Option{DateTime}
)::Dict{String,DataFrame}
    new_data_dfs = Dict{String,DataFrame}()
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
            @warn "Asset instance not found in strategy universe for $(asset_name)." color =
                :yellow
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
    dfs::Dict{String,DataFrame},
    roc_indicators::Dict{String,ROC{DFT}},
    roc_period::Int,
    window::Int, # Add window as parameter
    timeframe, # Add timeframe as parameter
    benchmark_specifier::Union{String, Vector{String}} # Add benchmark specifier
)::Dict{DateTime,Dict{String,DFT}}
    aligned_returns = Dict{DateTime,Dict{String,DFT}}()

    # Item for the heap: (timestamp, asset_name, dataframe_row_index)
    # Collect initial heap items and find the maximum timestamp
    local heap_items = Vector{Tuple{DateTime,String,Int}}()
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
        @warn "Could not calculate minimum acceptable timestamp based on timeframe and window." exception =
            e
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
    local aligned_data_points = Vector{Dict{String,DFT}}()
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
        min_timestamp, assets_at_current_timestamp = _collect_and_align_timestamp_data!(
            min_heap, original_asset_names, min_ts_item, min_acceptable_timestamp
        ) # Pass the already popped item

        if isnothing(min_timestamp)
            @debug "_collect_and_align_timestamp_data! returned nothing timestamp but heap is not empty."
            continue
        end

        # Calculate returns and add to a temporary dictionary for this timestamp
        local current_returns = Dict{String,DFT}()
        # local all_assets_roc_ready = true # No longer strictly needed with relaxed alignment condition

        for (asset, idx) in assets_at_current_timestamp
            df = original_dfs[asset]
            if idx <= nrow(df) &&
                df[idx, :timestamp] == min_timestamp &&
                "close" in names(df)
                close_price = df[idx, :close]

                if haskey(roc_indicators, asset)
                    fit!(roc_indicators[asset], close_price)
                    latest_return = value(roc_indicators[asset])

                    if nobs(roc_indicators[asset]) >= roc_period &&
                        !ismissing(latest_return) &&
                        !isnan(latest_return)
                        current_returns[asset] = latest_return
                    end
                else
                    @warn "ROC indicator not found for asset \"$(asset)\". Cannot calculate return."
                end
            else
                @debug "Data missing or invalid for asset $(asset) at timestamp $(min_timestamp)."
            end
        end

        # If all assets needed for this timestamp had their ROC ready, add the aligned data point
        # Condition for including a timestamp in aligned_returns:
        # If it's a single asset benchmark, that asset must have a ready ROC.
        # If it's a Top 5% benchmark, at least one of the benchmark component assets must have a ready ROC.
        # In all cases, we should ensure the current_returns is not empty (at least one asset had a ready ROC at this timestamp).
        local should_include_timestamp = false
        if typeof(benchmark_specifier) <: String # Single asset benchmark
             benchmark_asset = benchmark_specifier
             # Check if the benchmark asset's return is available and valid in current_returns
             if haskey(current_returns, benchmark_asset) && !ismissing(current_returns[benchmark_asset]) && !isnan(current_returns[benchmark_asset])
                 should_include_timestamp = true
             else
                  @debug "Skipping timestamp $(min_timestamp): Single benchmark asset $(benchmark_asset) return is missing or invalid."
             end
        else # Vector{String} benchmark (Top 5%)
             benchmark_assets = benchmark_specifier
             # Check if at least one benchmark component asset has a ready and valid return
             if any(asset -> haskey(current_returns, asset) && !ismissing(current_returns[asset]) && !isnan(current_returns[asset]), benchmark_assets)
                 should_include_timestamp = true
             else
                  @debug "Skipping timestamp $(min_timestamp): None of the Top 5% benchmark assets had ready and valid returns."
             end
        end

        # Debug: Log the state before the final inclusion check
        @debug "Alignment check at timestamp $(min_timestamp):" current_returns = current_returns should_include_timestamp = should_include_timestamp isempty_current_returns = isempty(current_returns) benchmark_specifier = benchmark_specifier

        # Debug: Log ROC readiness for benchmark components and sample assets if not including timestamp
        if !should_include_timestamp || isempty(current_returns)
             @debug "Skipping timestamp $(min_timestamp) details:"
             local assets_to_check = collect(keys(roc_indicators)) # Check all relevant assets
             # Limit output for too many assets
             if length(assets_to_check) > 10
                 assets_to_check = vcat(assets_to_check[1:5], ["..."], assets_to_check[end-4:end])
             end
             for asset in assets_to_check
                  if asset == "..." continue end
                  if haskey(roc_indicators, asset)
                      roc = roc_indicators[asset]
                      roc_ready = nobs(roc) >= roc_period
                      roc_val = value(roc)
                      roc_valid = !ismissing(roc_val) && !isnan(roc_val)
                      @debug "  Asset $(asset): ROC ready = $(roc_ready), ROC value valid = $(roc_valid), nobs = $(nobs(roc))"
                  else
                      @debug "  Asset $(asset): ROC indicator not found."
                  end
             end
        end

        if should_include_timestamp && !isempty(current_returns)
            push!(aligned_timestamps, min_timestamp)
            push!(aligned_data_points, current_returns)
        else
             # The debug message inside the if/else if blocks above provide more specific reasons.
             if isempty(current_returns)
                  @debug "Skipping timestamp $(min_timestamp): No assets had ready and valid returns at this timestamp."
              end
        end

        # Add the next data point from the processed dataframes to the heap
        _add_next_data_to_heap!(
            min_heap, assets_at_current_timestamp, original_dfs, min_acceptable_timestamp
        )
    end

    # Convert the list of aligned data points and timestamps back to the required dictionary format
    # This step might still be slow for large datasets, but the processing loop is improved.
    # Further optimization might require changing the return type or how this is consumed.
    aligned_returns = Dict{DateTime,Dict{String,DFT}}()
    for i in 1:length(aligned_timestamps)
        aligned_returns[aligned_timestamps[i]] = aligned_data_points[i]
    end

    return aligned_returns
end

# Helper function to collect and align data points at the minimum timestamp
function _collect_and_align_timestamp_data!(
    min_heap::BinaryHeap{Tuple{DateTime,String,Int}}, # Specify heap type
    original_asset_names::Set{String},
    initial_item::Tuple{DateTime,String,Int}, # Accept the item already popped
    min_acceptable_timestamp::DateTime, # Add min_acceptable_timestamp
)::Tuple{Option{DateTime},Dict{String,Int}}
    if isempty(min_heap) && isnothing(initial_item)
        return nothing, Dict{String,Int}() # No data to process
    end

    # The minimum timestamp item is already provided
    min_timestamp, current_asset, current_idx = initial_item

    # Only process if the minimum timestamp is within the acceptable window
    if min_timestamp < min_acceptable_timestamp
        @debug "Skipping timestamp $(min_timestamp) in _collect_and_align_timestamp_data! as it is older than acceptable window start $(min_acceptable_timestamp). Stopping processing."
        # Do not collect other items at this timestamp, as we are discarding this timestamp
        return nothing, Dict{String,Int}()
    end

    # Collect all data points that share the same minimum timestamp
    assets_at_current_timestamp = Dict{String,Int}() # Store asset_name => index for this timestamp
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
    min_heap::BinaryHeap{Tuple{DateTime,String,Int}}, # Specify heap type
    assets_at_current_timestamp::Dict{String,Int},
    original_dfs::Dict{String,DataFrame},
    min_acceptable_timestamp::DateTime, # Add min_acceptable_timestamp
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
function _validate_and_init_params(method::Symbol)::Tuple{Vector{Symbol},String}
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
    benchmark::Union{Symbol,String,DataFrame},
    min_vol::DFT,
    benchmark_name_str_ref::Ref{String}, # Pass benchmark_name_str by reference to modify it
)::Tuple{Dict{String,DataFrame}, Vector{String}, Union{String, Vector{String}}, Vector{String}}
    local asset_dfs::Dict{String,DataFrame} = Dict()
    local benchmark_df::Option{DataFrame} = nothing # Keep for DataFrame benchmark case
    local all_relevant_assets::Vector{String} = []
    local benchmark_specifier::Union{String, Vector{String}} = "" # Use benchmark_specifier

    # 1. Get the universe data for the specified timeframe and flatten it
    universe_asset_dfs_flattened = st.coll.flatten(st.universe(s); noempty=true)
    universe_dfs_for_tf = get(universe_asset_dfs_flattened, tf, DataFrame[])

    # Initial populate asset_dfs from universe data for the timeframe
    local initial_universe_asset_dfs = Dict{String,DataFrame}()
    for df in universe_dfs_for_tf
        if haskey(metadata(df), "asset_instance")
            asset_name = raw(metadata(df, "asset_instance"))
            initial_universe_asset_dfs[asset_name] = df
        else
            @warn "DataFrame in flattened universe data for timeframe $(tf) is missing 'asset_instance' metadata." color =
                :yellow
        end
    end

    local candidate_assets = collect(keys(initial_universe_asset_dfs))

    # 2. Apply minimum volume filter to initial candidate assets
    local all_assets_after_volume_filter::Vector{String} = tickers(
        st.getexchange!(s.exchange), s.qc; min_vol=min_vol, as_vec=true
    )

    # Filter down the initial_universe_asset_dfs to only include assets passing volume filter
    asset_dfs = Dict{String,DataFrame}() # This will contain data for all assets that pass volume filter
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

    # 3. Determine the benchmark asset/DataFrame or list of assets from the volume-filtered set
    if typeof(benchmark) <: DataFrame
        benchmark_df = benchmark
        if !("timestamp" in names(benchmark_df)) || !(size(benchmark_df, 2) >= 2)
            @error "External benchmark DataFrame must contain a 'timestamp' column and at least one value column."
            return Dict(), [], "", [] # Return empty on error
        end
        # Attempt to get asset name from metadata, fallback to a default name
        if haskey(metadata(benchmark), "asset_instance")
            local benchmark_name_str = String(raw(metadata(benchmark, "asset_instance")))
            benchmark_specifier = benchmark_name_str # Explicitly convert SubString to String via a temporary variable
        else
            benchmark_specifier = "external_benchmark"
            @warn "External benchmark DataFrame is missing 'asset_instance' metadata. Using 'external_benchmark' as name." color =
                :yellow
        end

        # If the benchmark DataFrame's asset is not in the volume-filtered set, add it to asset_dfs
        if !(benchmark_specifier in candidate_assets)
            @warn "External benchmark asset \"$(benchmark_specifier)\" is not in the volume-filtered universe. Adding it for calculation." color =
                :yellow
            push!(candidate_assets, benchmark_specifier) # Add to candidate_assets
            asset_dfs[benchmark_specifier] = benchmark_df # Add the benchmark DataFrame to asset_dfs
        end

    elseif typeof(benchmark) <: Symbol
        if benchmark == :top_asset
            # Determine top asset based on quote volume from the *already volume-filtered* assets
            candidate_assets_with_volume = [
                (asset, _calculate_quote_volume(asset_dfs[asset])) for
                asset in candidate_assets
            ]
            sort!(candidate_assets_with_volume, by = x -> x[2], rev = true) # Sort by quote volume descending

            if isempty(candidate_assets_with_volume) ||
                candidate_assets_with_volume[1][2] == -Inf
                @warn "No assets meet the minimum volume requirement or have valid close/volume data to determine top asset benchmark from the filtered set."
                return Dict(), [], "", [] # Return empty on error
            end
            benchmark_specifier = candidate_assets_with_volume[1][1] # benchmark_specifier is a String

        elseif benchmark == :top_5_percent
            @warn "Top 5% benchmark in online mode will aggregate individual asset returns." # Info about aggregation method

            # Determine top assets based on quote volume from the *already volume-filtered* assets
            candidate_assets_with_volume = [
                (asset, _calculate_quote_volume(asset_dfs[asset])) for
                asset in candidate_assets
            ]
            sort!(candidate_assets_with_volume, by = x -> x[2], rev = true) # Sort by quote volume descending

            if isempty(candidate_assets_with_volume) ||
                candidate_assets_with_volume[1][2] == -Inf
                @warn "No assets meet the minimum volume requirement or have valid close/volume data to determine top 5% benchmark from the filtered set."
                return Dict(), [], "", [] # Return empty on error
            end

            # Select the top 5% of assets based on count (at least one)
            local num_top_5_percent = max(1, ceil(Int, length(candidate_assets_with_volume) * 0.05))
            # Ensure we don't ask for more assets than available
            local num_to_select = min(num_top_5_percent, length(candidate_assets_with_volume))
            # Select the top N assets from the sorted list
            benchmark_specifier = [asset for (asset, volume) in candidate_assets_with_volume[1:num_to_select]] # benchmark_specifier is a Vector{String}

            if isempty(benchmark_specifier) # Check the selected list of assets
                @warn "Could not select top 5% assets for benchmark."
                return Dict(), [], "", [] # Return empty if no assets selected
            end

            # For :top_5_percent benchmark, the relevant assets are the benchmark components themselves.
            # We don't need to add a synthetic benchmark_df to asset_dfs here.

        else
            @error "Invalid benchmark symbol: $(benchmark). Must be :top_asset or :top_5_percent."
            return Dict(), [], "", []
        end

    elseif typeof(benchmark) <: String
        benchmark_specifier = benchmark # benchmark_specifier is a String
        # Check if the chosen benchmark asset exists in the *volume-filtered* data (which is in asset_dfs)
        if !haskey(asset_dfs, benchmark_specifier)
            @error "Specified benchmark asset \"$(benchmark_specifier)\" is not available in the volume-filtered universe data for timeframe $(tf)."
            return Dict(), [], "", [] # Return empty if benchmark data is missing after filtering
        end

    else
        @error "Invalid benchmark type: $(typeof(benchmark)). Must be Symbol, String, or DataFrame."
        return Dict(), [], "", []
    end

    # 4. Determine all relevant assets for calculations
    # This includes all assets that passed the volume filter (contained in asset_dfs keys)
    # and, in the case of a DataFrame benchmark, the benchmark asset itself if it wasn't already in asset_dfs.
    # For :top_5_percent, all relevant assets are the assets in asset_dfs, and the benchmark specifier is the list of assets.

    all_relevant_assets = collect(keys(asset_dfs)) # asset_dfs already contains the DataFrame benchmark if applicable

    # Set benchmark_name_str_ref for the cache initialization
    # This needs to be a consistent string identifier for the cache key.
    local benchmark_cache_name::String
    if typeof(benchmark_specifier) <: String
        benchmark_cache_name = benchmark_specifier
    else # benchmark_specifier is Vector{String}
        # Create a stable string representation for the cache key from the sorted list of assets
        benchmark_cache_name = "Top5PercentBenchmark_" * join(sort(benchmark_specifier), "_")
    end
    benchmark_name_str_ref[] = benchmark_cache_name

    # Return asset_dfs, the list of assets for beta calculation, the benchmark specifier, and all relevant assets
    local assets_for_beta_calc = collect(keys(asset_dfs))
    # Ensure assets_for_beta_calc does NOT include the single asset benchmark if applicable
    if typeof(benchmark_specifier) <: String
        filter!(asset -> asset != benchmark_specifier, assets_for_beta_calc)
    end
    # Note: For :top_5_percent, the assets to calculate beta FOR are still all assets *not* in the benchmark list.
    # This requires careful handling in subsequent steps.

    return asset_dfs, assets_for_beta_calc, benchmark_specifier, all_relevant_assets
end

# New helper function for getting or initializing the beta cache
function _get_or_initialize_beta_cache(
    s::st.Strategy,
    benchmark_name_str::String, # This is now the cache key string
    method::Symbol,
    window::Int,
    roc_period::Int,
    demean::Bool,
    assets_for_beta_calc::Vector{String}, # Assets for which beta is calculated AGAINST the benchmark
    all_relevant_assets::Vector{String}, # ALL assets for which we have data and need ROCs
    benchmark_specifier::Union{String, Vector{String}} # Add benchmark specifier
)::Tuple{BetaOnlineCache, Bool}
    local beta_cache::BetaOnlineCache
    local reinitialize_required = false

    if haskey(s.attrs, :_beta_state)
        local current_beta_state = s.attrs[:_beta_state]
        # Also check if the benchmark specifier and assets are consistent with the cache
        # Compare benchmark_name_str for string benchmarks/cache key
        if typeof(current_beta_state) <: BetaOnlineCache &&
            # Compare the cache key string
            (typeof(current_beta_state.benchmark_specifier) <: String ? current_beta_state.benchmark_specifier : "Top5PercentBenchmark_" * join(sort(current_beta_state.benchmark_specifier), "_")) == benchmark_name_str &&
            current_beta_state.method == method &&
            current_beta_state.window == window &&
            current_beta_state.roc_period == roc_period &&
            current_beta_state.demean == demean &&
            # Additionally, check if the set of assets matches the cached stats and ROCs
            issetequal(keys(current_beta_state.cov_stats), assets_for_beta_calc) && # Check assets in cov_stats (assets for beta calc)
            issetequal(keys(current_beta_state.reg_stats), assets_for_beta_calc) && # Check assets in reg_stats (assets for beta calc)
            issetequal(keys(current_beta_state.roc_indicators), all_relevant_assets) # Check assets in roc_indicators (all relevant assets)
            beta_cache = current_beta_state
            @debug "Reusing compatible online beta state from strategy attributes."
        else
            @warn "Cached online beta state is incompatible (parameters, type, or asset set changed). Reinitializing." required_params = (
                benchmark_name=benchmark_name_str, # Log the cache key string
                method=method,
                window=window,
                roc_period=roc_period,
                demean=demean,
                assets_for_beta_calc=sort(assets_for_beta_calc),
                all_relevant_assets=sort(all_relevant_assets),
            ) typeof_cached = typeof(current_beta_state)
            reinitialize_required = true
        end
    else
        @debug "No existing online beta state found in strategy attributes. Initializing new state."
        reinitialize_required = true
    end

    if reinitialize_required
        @debug "Initializing ROC indicators and online stats for reinitialization."
        current_roc_indicators = Dict{String,ROC{DFT}}()
        # Initialize ROCs for ALL relevant assets, including benchmark components if applicable
        for asset in all_relevant_assets
            current_roc_indicators[asset] = ROC{DFT}(; period=roc_period)
        end

        # Initialize online stats only for assets we are calculating beta FOR (assets_for_beta_calc)
        initialized_stats = _initialize_online_beta_stats(
            assets_for_beta_calc, benchmark_name_str, window, method # Pass cache key string for stats initialization too (not strictly used there, but for consistency)
        )

        beta_cache = BetaOnlineCache(
            initialized_stats[1], # cov_stats
            initialized_stats[2], # benchmark_var_stat
            initialized_stats[3], # reg_stats
            benchmark_specifier, # Store the actual benchmark specifier (String or Vector{String})
            method,
            window,
            roc_period,
            demean,
            nothing, # last_timestamp
            current_roc_indicators,
            Dict{String,Any}(), # Initialize empty last_calculated_beta
            nothing, # Initialize empty last_calculation_timestamp
        )
        s.attrs[:_beta_state] = beta_cache
    else
        # If reusing cache, ensure ROC indicators exist for any new assets in all_relevant_assets
        # This could happen if the universe expands but the benchmark parameters are otherwise compatible
        for asset in all_relevant_assets
            if !haskey(beta_cache.roc_indicators, asset)
                @debug "Initializing ROC indicator for new relevant asset: $(asset)"
                beta_cache.roc_indicators[asset] = ROC{DFT}(; period=beta_cache.roc_period)
            end
        end
         # Ensure stats exist for any new assets in assets_for_beta_calc
         for asset in assets_for_beta_calc
              if !haskey(beta_cache.cov_stats, asset) && (beta_cache.method == :covariance || beta_cache.method == :both)
                   @debug "Initializing CovMatrix stat for new asset for beta calculation: $(asset)"
                   beta_cache.cov_stats[asset] = RollingCovMatrix(beta_cache.window, DFT)
              end
              if !haskey(beta_cache.reg_stats, asset) && (beta_cache.method == :regression || beta_cache.method == :both)
                   @debug "Initializing LinReg stat for new asset for beta calculation: $(asset)"
                   beta_cache.reg_stats[asset] = RollingLinReg(beta_cache.window, DFT)
              end
         end
    end

    return beta_cache, reinitialize_required
end

# New helper function for processing new data and updating the cache
function _process_and_update_cache!(
    s::st.Strategy,
    tf,
    beta_cache::BetaOnlineCache,
    reinitialize_required::Bool,
    asset_dfs::Dict{String,DataFrame}, # DataFrames for ALL relevant assets (including benchmark components)
    all_relevant_assets::Vector{String},
    assets_for_beta_calc::Vector{String}, # Assets for which beta is calculated AGAINST the benchmark
    benchmark_specifier::Union{String, Vector{String}}, # The benchmark specifier
)::Tuple{Set{String}, Bool} # Returns set of asset names needing beta calculation and a flag indicating if new data was processed

    # Determine the overall maximum timestamp across all relevant assets' data
    local max_shared_timestamp::Option{DateTime} = nothing
    for asset_name in all_relevant_assets
        if haskey(asset_dfs, asset_name) && !isempty(asset_dfs[asset_name])
            df = asset_dfs[asset_name]
            if "timestamp" in names(df)
                if isnothing(max_shared_timestamp) ||
                    df[end, :timestamp] > max_shared_timestamp
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
        @warn "Could not calculate minimum acceptable timestamp based on timeframe and window. Processing all available data." exception =
            e
        min_acceptable_timestamp = DateTime(0) # Process all data if calculation fails
    end

    # Filter input dataframes to include only data within the calculated window for ALL relevant assets
    local data_to_process_dfs::Dict{String,DataFrame} = Dict() # This will contain data for ALL relevant assets within the window
    local new_data_found = false # Track if any new data (relative to last_timestamp) is found in the window

    for asset_name in all_relevant_assets
        if haskey(asset_dfs, asset_name) &&
            !isempty(asset_dfs[asset_name]) &&
            "timestamp" in names(asset_dfs[asset_name])
            df = asset_dfs[asset_name]
            # Filter rows within the acceptable timestamp range
            filtered_df = filter(row -> row.timestamp >= min_acceptable_timestamp, df)
            if !isempty(filtered_df)
                data_to_process_dfs[asset_name] = filtered_df
                # Check if any of this filtered data is newer than the last processed timestamp
                if isnothing(beta_cache.last_timestamp) ||
                    filtered_df[end, :timestamp] > beta_cache.last_timestamp
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

    # Fit ROCs for all data points within the processing window for ALL relevant assets.
    # _align_and_calculate_returns! will then use these fitted ROCs.
    local all_relevant_assets_in_window = collect(keys(data_to_process_dfs))
    # Debug: Inspect the input to the timestamp collection
    @debug "Input to timestamp collection (values of data_to_process_dfs):" typeof(values(data_to_process_dfs))
    local timestamp_sets = []
    for df in values(data_to_process_dfs)
        # Debug: Inspect the type of the timestamp column
        @debug "Timestamp column type:" typeof(df.timestamp)
        push!(timestamp_sets, Set(df.timestamp))
    end
    local unique_timestamps = union(timestamp_sets...)
    # Debug: Inspect the result of the union operation
    @debug "Result of union operation:" typeof(unique_timestamps) first(collect(unique_timestamps), 10)
    local all_relevant_timestamps_in_window = convert(Vector{DateTime}, sort(collect(unique_timestamps)))

     if !isempty(all_relevant_timestamps_in_window)
          @debug "Fitting ROCs for $(length(all_relevant_assets_in_window)) relevant assets over $(length(all_relevant_timestamps_in_window)) unique timestamps."

          # Debug: Inspect the type and content of all_relevant_timestamps_in_window
          @debug "all_relevant_timestamps_in_window type and first 10 elements:" typeof(all_relevant_timestamps_in_window) first(all_relevant_timestamps_in_window, 10)

          # Create iterators for each relevant asset DataFrame for efficient chronological processing
          local asset_iterators = Dict(asset => eachrow(df) for (asset, df) in data_to_process_dfs)
          local current_rows = Dict(asset => iterate(iter) for (asset, iter) in asset_iterators)

          for current_processing_timestamp in all_relevant_timestamps_in_window
               for asset in keys(current_rows)
                    @debug "Comparing timestamp types: current_rows[asset][1].timestamp type = $(typeof(current_rows[asset][1].timestamp)), current_processing_timestamp type = $(typeof(current_processing_timestamp))"
                    while !isnothing(current_rows[asset]) && current_rows[asset][1].timestamp <= current_processing_timestamp
                         row, state = current_rows[asset]
                         close_price = row.close
                         # Fit the ROC indicator for this asset
                         fit!(current_roc_indicators[asset], close_price)
                         # Move to the next row for this asset
                         next_row_state = iterate(asset_iterators[asset], state)
                         if isnothing(next_row_state)
                             # Iterator exhausted for this asset, remove from current_rows or mark as done
                             delete!(current_rows, asset)
                             break # Exit the while loop for this asset
                         else
                             current_rows[asset] = next_row_state
                         end
                    end
               end
          end
     else
          @debug "No relevant data to fit ROCs in the processing window."
     end

    # Now perform alignment and get aligned returns for ALL relevant assets within the window
    aligned_returns_all_relevant = _align_and_calculate_returns!(
        data_to_process_dfs, # Pass data for all relevant assets
        current_roc_indicators,
        beta_cache.roc_period,
        beta_cache.window,
        s.timeframe,
        beta_cache.benchmark_specifier # Pass the benchmark specifier
    )

    # Ensure timestamps are sorted and explicitly a Vector{DateTime} for safe iteration
    sorted_aligned_timestamps = convert(Vector{DateTime}, sort(collect(keys(aligned_returns_all_relevant))))

    local assets_to_recalculate = Set{String}()

    @info "Processing $(length(sorted_aligned_timestamps)) aligned timestamps for stat fitting."
    # Process the aligned returns to fit the custom rolling statistics
    for timestamp in sorted_aligned_timestamps
        data_point_dict = aligned_returns_all_relevant[timestamp]

        # Determine the benchmark return for this timestamp
        local benchmark_return::Union{DFT, Missing} = missing

        if typeof(beta_cache.benchmark_specifier) <: String
            # Single asset benchmark
            benchmark_asset_name = beta_cache.benchmark_specifier
            benchmark_return = get(data_point_dict, benchmark_asset_name, missing)
            if ismissing(benchmark_return)
                 @debug "Single benchmark asset return missing at timestamp $(timestamp). Skipping this data point for stat fitting."
                 continue
            end
        else # benchmark_specifier is Vector{String} (Top 5% benchmark)
            benchmark_assets = beta_cache.benchmark_specifier
            local sum_benchmark_returns = DFT(0.0)
            local count_benchmark_assets_ready = 0

            for asset in benchmark_assets
                if haskey(data_point_dict, asset) && !ismissing(data_point_dict[asset]) && !isnan(data_point_dict[asset])
                     # Check if individual asset ROC is ready (should be if it's in data_point_dict and not missing/NaN)
                     # Double check nobs just in case, though alignment should ensure this based on roc_period
                     if haskey(beta_cache.roc_indicators, asset) && nobs(beta_cache.roc_indicators[asset]) >= beta_cache.roc_period
                         sum_benchmark_returns += data_point_dict[asset]
                         count_benchmark_assets_ready += 1
                     else
                          # This case indicates an issue in alignment if data is present but ROC is not ready
                           @debug "Top 5% benchmark component asset $(asset) data present at $(timestamp), but ROC not ready. Skipping for benchmark average."
                     end
                else
                    # Asset data or return is missing/invalid at this timestamp
                     @debug "Top 5% benchmark component asset $(asset) data/return missing at timestamp $(timestamp)."
                end
            end

            if count_benchmark_assets_ready > 0
                benchmark_return = sum_benchmark_returns / count_benchmark_assets_ready
            else
                 # If none of the benchmark assets had ready and valid returns at this timestamp
                 @debug "None of the Top 5% benchmark assets had ready and valid returns at timestamp $(timestamp). Skipping this data point for stat fitting."
                 continue # Skip the data point if benchmark return cannot be calculated
            end
        end

        # At this point, benchmark_return is either a valid DFT or missing (only for single asset benchmark that is missing)
        # If it's missing, we already continued.

        # Fit benchmark variance stat
        benchmark_return_demeaned = if beta_cache.demean
            # Demeaning benchmark return only makes sense for single asset benchmark
            if typeof(beta_cache.benchmark_specifier) <: String
                 benchmark_asset_name = beta_cache.benchmark_specifier
                 # Ensure the ROC for the benchmark asset is ready before demeaning
                 if haskey(beta_cache.roc_indicators, benchmark_asset_name) && nobs(beta_cache.roc_indicators[benchmark_asset_name]) >= beta_cache.roc_period
                      benchmark_return - value(beta_cache.roc_indicators[benchmark_asset_name])
                 else
                       # Cannot demean if benchmark ROC is not ready, use non-demeaned return but log a warning
                        @warn "Benchmark ROC not ready for demeaning at timestamp $(timestamp). Using non-demeaned benchmark return for variance calculation."
                        benchmark_return
                 end
            else
                 # For Top 5% aggregate benchmark, demeaning is not applied at this stage
                 benchmark_return
            end
        else
            benchmark_return # Not demeaning
        end
        fit!(beta_cache.benchmark_var_stat, benchmark_return_demeaned) # Always fit benchmark variance if benchmark return is available

        for asset_name in assets_for_beta_calc # Iterate only over assets we are calculating beta FOR
            asset_return = get(data_point_dict, asset_name, missing)

            # Ensure the asset is one for which we calculate beta and its return is available and valid
            if ismissing(asset_return) || isnan(asset_return) || !(asset_name in assets_for_beta_calc) # Double check asset_name is in assets_for_beta_calc
                 if !(asset_name in assets_for_beta_calc)
                      @debug "Asset $(asset_name) is not in the list of assets for beta calculation. Skipping stat fitting."
                 else
                      @debug "Asset return missing or invalid for $(asset_name) at timestamp $(timestamp). Skipping stat fitting for this asset."
                 end
                continue
            end

            # Calculate demeaned returns for the asset return
            asset_return_demeaned = if beta_cache.demean
                 # Ensure the ROC for the asset is ready before demeaning
                 if haskey(beta_cache.roc_indicators, asset_name) && nobs(beta_cache.roc_indicators[asset_name]) >= beta_cache.roc_period
                    asset_return - value(beta_cache.roc_indicators[asset_name])
                 else
                      # Cannot demean if asset ROC is not ready, use non-demeaned return but log a warning
                       @warn "Asset ROC not ready for demeaning for $(asset_name) at timestamp $(timestamp). Using non-demeaned asset return for covariance calculation."
                       asset_return
                 end
            else
                asset_return # Not demeaning
            end

            # Prepare benchmark return for covariance and regression fitting.
            # Use the demeaned benchmark return for covariance if demeaning is enabled and applicable.
            # Use the raw benchmark return for regression (y=asset, x=benchmark).
            local benchmark_return_for_cov_fit::DFT
            local benchmark_return_for_reg_fit::DFT # Regression uses the raw benchmark return

            if beta_cache.demean && typeof(beta_cache.benchmark_specifier) <: String
                 # If demeaning and single asset benchmark, use the demeaned benchmark return calculated earlier
                 benchmark_return_for_cov_fit = benchmark_return_demeaned # This is the demeaned single asset benchmark return
            else
                 # Otherwise (no demeaning, or Top 5% benchmark), use the raw benchmark return
                 benchmark_return_for_cov_fit = benchmark_return
            end

             benchmark_return_for_reg_fit = benchmark_return # Regression always uses the raw benchmark return

            # Fit covariance stat (using demeaned asset return and appropriate benchmark return)
            if haskey(beta_cache.cov_stats, asset_name) # Use asset_name as key
                fit!(
                    beta_cache.cov_stats[asset_name],
                    (asset_return_demeaned, benchmark_return_for_cov_fit),
                )
            end

            # Fit regression stat (using raw asset return and raw benchmark return)
            if haskey(beta_cache.reg_stats, asset_name) # Use asset_name as key
                fit!(beta_cache.reg_stats[asset_name], (asset_return, benchmark_return_for_reg_fit))
            end
        end
    end

    # After processing all relevant timestamps, determine which assets need recalculation
    # This is typically when their rolling stats have accumulated the required window size
    for asset_name in assets_for_beta_calc # Check only assets for which we calculate beta
        # Check if the window is full for either covariance or regression stat for this asset
        if (
            haskey(beta_cache.cov_stats, asset_name) &&
            nobs(beta_cache.cov_stats[asset_name]) >= beta_cache.window
        ) || (
            haskey(beta_cache.reg_stats, asset_name) &&
            nobs(beta_cache.reg_stats[asset_name]) >= beta_cache.window
        )
            push!(assets_to_recalculate, asset_name)
        end
    end

    # Update last_timestamp if any data was processed and aligned
    if !isempty(sorted_aligned_timestamps)
        beta_cache.last_timestamp = last(sorted_aligned_timestamps)
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
    benchmark_specifier::Union{String, Vector{String}},
)
    # Do not clear the entire cache, only update entries for assets being recalculated.
    # The main function will reconstruct the DataFrame from the full cache.

    # Determine the benchmark variance value (same calculation regardless of benchmark type, uses benchmark_var_stat)
    local benchmark_var_val::Union{DFT, Missing} = missing
    if nobs(beta_cache.benchmark_var_stat) >= beta_cache.window
        benchmark_var_val = value(beta_cache.benchmark_var_stat)
        if isnan(benchmark_var_val)
             benchmark_var_val = missing
        end
    else
        @debug "Benchmark variance rolling window not full for Beta calculation."
    end

    for asset_name in assets_to_recalculate # Iterate only over assets that need recalculation
        local beta_cov::Union{DFT,Missing} = missing
        local beta_reg::Union{DFT,Missing} = missing

        stat_pair_key = asset_name # The key for cov_stats and reg_stats is just the asset name

        # Calculate Beta by Covariance
        # Requires valid benchmark_var_val and enough observations in the covariance stat
        if !ismissing(benchmark_var_val) && abs(benchmark_var_val) > eps(DFT)
            if beta_cache.method == :covariance || beta_cache.method == :both
                # Check if the RollingCovMatrix stat has enough observations for this asset
                if haskey(beta_cache.cov_stats, stat_pair_key) &&
                    nobs(beta_cache.cov_stats[stat_pair_key]) >= beta_cache.window
                    # Get the rolling covariance matrix and extract the covariance value (Cov(Asset, Benchmark))
                    cov_matrix = value(beta_cache.cov_stats[stat_pair_key])

                    # The covariance matrix from RollingCovMatrix is [[Var(Asset), Cov(Asset, Benchmark)], [Cov(Benchmark, Asset), Var(Benchmark)]]
                    # We need Cov(Asset, Benchmark), which is at [1, 2] or [2, 1]. It should be symmetric.
                    cov_val = cov_matrix[1, 2]

                    # Ensure the covariance value is not NaN
                    if !isnan(cov_val)
                        beta_cov = cov_val / benchmark_var_val
                    else
                        beta_cov = missing
                    end
                end
            end
        else
            @debug "Cannot calculate Beta by Covariance for $(asset_name): Benchmark variance is missing, NaN, zero or near zero." timestamp =
                beta_cache.last_timestamp var = benchmark_var_val
            beta_cov = missing # Cannot calculate covariance beta if benchmark variance is invalid
        end

        # Calculate Beta by Regression
        if beta_cache.method == :regression || beta_cache.method == :both
            # Check if the RollingLinReg stat has enough observations for this asset
            if haskey(beta_cache.reg_stats, stat_pair_key) &&
                nobs(beta_cache.reg_stats[stat_pair_key]) >= beta_cache.window
                # Get the rolling regression coefficients [β₀, β₁]
                reg_coeffs = coef(beta_cache.reg_stats[stat_pair_key])

                # Ensure the regression has enough observations and beta coefficient is not NaN/Inf
                # The value function for RollingLinReg already returns [NaN, NaN] if not enough data or denominator is zero
                if length(reg_coeffs) == 2 && !isnan(reg_coeffs[2]) && !isinf(reg_coeffs[2])
                    beta_reg = reg_coeffs[2] # The beta coefficient is β₁ (the slope) from y = β₀ + β₁x (asset return = β₀ + β₁ * benchmark return)
                else
                    beta_reg = missing # Regression failed or result is invalid
                end
            end
        end

        local asset_result
        if beta_cache.method == :both
            asset_result = (
                Asset=asset_name, Beta_Covariance=beta_cov, Beta_Regression=beta_reg
            )
        elseif beta_cache.method == :covariance
            asset_result = (Asset=asset_name, Beta_Covariance=beta_cov)
        elseif beta_cache.method == :regression
            asset_result = (Asset=asset_name, Beta_Regression=beta_reg)
        end
        # Update the cached result for this specific asset
        beta_cache.last_calculated_beta[asset_name] = asset_result
    end

    # Update last calculation timestamp only if any calculations occurred and there was a valid last_timestamp
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
    benchmark::Union{Symbol,String,DataFrame}=:top_asset,
    min_vol::DFT=1e6,
    method::Symbol=:covariance,
    window::Int=100,
    roc_period::Int=1,
    demean::Bool=false,
)::DataFrame

    # 1. Parameter validation and initialization
    local benchmark_name_str_ref = Ref{String}("") # This will hold the cache key string
    result_cols, _ = _validate_and_init_params(method)

    # 2. Prepare asset and benchmark data
    # _prepare_asset_data now returns asset_dfs, assets_for_beta_calc, benchmark_specifier, and all_relevant_assets
    asset_dfs, assets_for_beta_calc, benchmark_specifier, all_relevant_assets = _prepare_asset_data(
        s, tf, benchmark, min_vol, benchmark_name_str_ref
    )

    # benchmark_name_str_ref is populated inside _prepare_asset_data now
    local benchmark_cache_key = benchmark_name_str_ref[]

    # Check for errors/insufficient data after preparation
    if isempty(asset_dfs) || isempty(all_relevant_assets) || benchmark_specifier == ""
        @warn "Insufficient data, no relevant assets, or benchmark not determined after preparation."
        return DataFrame(result_cols, []) # Return empty DataFrame with correct columns
    end

    # For DataFrame benchmark, ensure it is in asset_dfs
    if typeof(benchmark_specifier) <: String && benchmark_specifier == "external_benchmark"
         # If external_benchmark was specified and added to asset_dfs, ensure it exists
         if !haskey(asset_dfs, "external_benchmark") || isempty(asset_dfs["external_benchmark"])
              @warn "External benchmark DataFrame was not found or is empty in asset_dfs after preparation."
              return DataFrame(result_cols, [])
         end
          # If benchmark_specifier is a single string name (not external_benchmark) ensure it's in asset_dfs
    elseif typeof(benchmark_specifier) <: String
         if !haskey(asset_dfs, benchmark_specifier) || isempty(asset_dfs[benchmark_specifier])
              @warn "Specified single asset benchmark \"$(benchmark_specifier)\" not found or is empty in asset_dfs after preparation."
               return DataFrame(result_cols, [])
         end
    end # No specific check needed for Vector{String} benchmark_specifier, as component assets are checked later via all_relevant_assets

    # assets_for_beta_calc is already determined in _prepare_asset_data (assets in asset_dfs excluding single benchmark asset)
    if isempty(assets_for_beta_calc)
        @warn "No assets remaining to calculate beta for after excluding benchmark (if applicable)."
        return DataFrame(result_cols, [])
    end

    # 3. Get or initialize the beta cache
    beta_cache, reinitialize_required = _get_or_initialize_beta_cache(
        s,
        benchmark_cache_key, # Pass the cache key string
        method,
        window,
        roc_period,
        demean,
        assets_for_beta_calc, # Assets for which beta is calculated
        all_relevant_assets, # ALL relevant assets for ROCs
        benchmark_specifier # Pass the benchmark specifier
    )

    # 4. Process new data and update cache state, get list of assets needing recalculation
    # _process_and_update_cache! now uses the benchmark_specifier directly from the cache.
    local assets_to_recalculate, new_data_processed = _process_and_update_cache!(
        s,
        tf,
        beta_cache,
        reinitialize_required,
        asset_dfs, # Pass data for ALL relevant assets (including benchmark components)
        all_relevant_assets,
        assets_for_beta_calc,
        beta_cache.benchmark_specifier # Pass the benchmark specifier from the cache
    )

    # 5. Calculate and cache beta results only for needed assets
    if !isempty(assets_to_recalculate) || reinitialize_required
        @debug "Calculating beta values for $(length(assets_to_recalculate)) assets."
        _calculate_and_cache_beta(
            beta_cache,
            assets_to_recalculate,
            beta_cache.benchmark_specifier # Pass the benchmark specifier from the cache
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
        return DataFrame([col => Vector{DFT}() for col in result_cols]) # Ensure empty DataFrame has correct column types
    else
        return DataFrame(final_results_data)
    end
end
