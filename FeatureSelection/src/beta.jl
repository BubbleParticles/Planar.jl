using StatsBase: cov, var
using GLM
using Statistics: mean
using Strategies: Strategies as st
using .st.Misc: Option
using .st.Data: Data as da, DataFrame
using .da.DataFrames: DataFrame, metadata!, deletemetadata!, names, metadata
using .st: TimeFrame, DFT, @tf_str
using .st.coll: _flatten_noempty!, raw, flatten
using .st.Exchanges: tickers
using Processing.Alignments: trim!, empty_unaligned!
using GLM: @formula
using LinearAlgebra: diag

@doc """
    calculate_beta_covariance(stock_returns, market_returns)

Calculate the Beta of a stock/asset relative to a market benchmark using the covariance and variance method.

Beta = Covariance(stock returns, market returns) / Variance(market returns)

# Arguments
- `stock_returns::Vector{DFT}`: Vector of historical returns for the stock/asset.
- `market_returns::Vector{DFT}`: Vector of historical returns for the market benchmark.

# Returns
- `DFT`: The calculated Beta value.

# Throws
- `Error`: If the input vectors have different lengths, insufficient data, or market variance is zero.
"""
function calculate_beta_covariance(stock_returns::Vector{DFT}, market_returns::Vector{DFT})::DFT
    if length(stock_returns) != length(market_returns)
        error("Input return series must have the same length")
    end

    if length(stock_returns) < 2 # Need at least 2 data points for covariance/variance
         error("Not enough data points to calculate beta")
    end

    cov_returns = cov(stock_returns, market_returns)
    var_market = var(market_returns)

    if abs(var_market) < eps(DFT) # Check if variance is close to zero
        error("Cannot calculate beta: Market variance is zero or near zero")
    end

    beta = cov_returns / var_market

    return beta
end

@doc """
    calculate_beta_regression(stock_returns, market_returns)

Calculate the Beta of a stock/asset relative to a market benchmark using linear regression.

Beta is the slope coefficient (β) from the linear regression model:
stock_returns = α + β * market_returns + ε

# Arguments
- `stock_returns::Vector{DFT}`: Vector of historical returns for the stock/asset.
- `market_returns::Vector{DFT}`: Vector of historical returns for the market benchmark.

# Returns
- `DFT`: The calculated Beta value (the slope coefficient).

# Throws
- `Error`: If the input vectors have different lengths or insufficient data.
"""
function calculate_beta_regression(stock_returns::Vector{DFT}, market_returns::Vector{DFT})::DFT
    if length(stock_returns) != length(market_returns)
        error("Input return series must have the same length")
    end

     if length(stock_returns) < 2 # Need at least 2 data points for regression
          error("Not enough data points to calculate beta")
     end

    # Create a DataFrame for GLM
    data = DataFrame(stock_returns=stock_returns, market_returns=market_returns)

    # Perform linear regression: stock_returns ~ market_returns
    model = lm(@formula(stock_returns ~ market_returns), data)

    # Extract the coefficient for market_returns (which is Beta)
    # The coefficients are in the order of the formula: intercept, market_returns
    beta = GLM.coef(model)[2]

    return beta
end

@doc """
    beta_indicator(s::st.Strategy, tf=s.timeframe; benchmark = :top_asset, min_vol = 1e6, method = :both)

Calculate the Beta for all assets in a strategy's universe relative to a specified benchmark.

The benchmark can be:
- A Symbol: `:top_asset` (single asset with highest volume) or `:top_5_percent` (aggregate of top 5% by volume).
- A String: The name of a specific asset from the strategy's universe.
- A DataFrame: An external DataFrame with a timestamp column (first) and numerical return column (second).

# Arguments
- `s::st.Strategy`: The strategy object containing the universe of assets.
- `tf::TimeFrame`: The timeframe for the asset data (defaults to strategy's timeframe).
- `benchmark::Union{Symbol, String, DataFrame}`: Specifies the benchmark. See description above. Defaults to `:top_asset`.
- `min_vol::DFT`: The minimum volume required for an asset to be considered for `:top_asset` or `:top_5_percent` benchmarks. Defaults to 1e6.
- `method::Symbol`: The method to use for Beta calculation. Accepts `:covariance`, `:regression`, or `:both`. Defaults to `:both`. Defaults to `:covariance`.
- `tail::Option{Int}`: The number of data points to use for the Beta calculation. If `nothing`, all data points are used. If a positive integer, the last `tail` data points are used.

# Returns
- `DataFrame`: A DataFrame with columns `:Asset`, and either `:Beta_Covariance`, `:Beta_Regression`, or both, depending on the `method` argument.
             Returns an empty DataFrame if insufficient data or assets are available, or if the benchmark cannot be determined.
"""
function beta_indicator(s::st.Strategy, tf=s.timeframe; benchmark::Union{Symbol, String, DataFrame} = :top_asset, min_vol::DFT=1e6, method::Symbol = :covariance, tail::Option{Int} = nothing)::DataFrame
    # Get universe data
    universe_data = st.universe(s)

    local benchmark_returns::Vector{DFT}
    local benchmark_name = "benchmark"
    local centered_df::DataFrame
    local asset_names::Vector{String}

    # Handle external DataFrame benchmark before flattening
    if typeof(benchmark) <: DataFrame
        external_benchmark_df = copy(benchmark) # necessary to ensure metadata uniqueness
        if size(external_benchmark_df, 2) < 2
            error("External benchmark DataFrame must have at least two columns.")
        end
        # Ensure the external benchmark DataFrame has the correct timeframe metadata
        da.timeframe!(external_benchmark_df, tf)

        # Add "asset_instance" metadata if not present. Use a unique temporary key.
        metadata!(external_benchmark_df, "asset_instance", benchmark_name) # Store unique key

        # Flatten the universe data
        flattened_data = st.coll.flatten(universe_data; noempty=true)

        # Get initial list of DataFrames before adding benchmark
        local initial_dfs = get(flattened_data, tf, DataFrame[])

        push!(@lget!(flattened_data, tf, DataFrame[]), external_benchmark_df)

        # Now, apply center_data to the combined flattened data
        try
            # center_data will handle the alignment internally
            (trimmed_data, v) = center_data(flattened_data, tf; ratio_func=ratio!)

            local benchmark_df_trimmed::Option{DataFrame} = nothing
            local benchmark_v_column_idx::Option{Int} = nothing # Store the column index in v for the benchmark
            local asset_names_and_v_indices = Tuple{String, Int}[] # To store (asset_name, v_column_index) pairs for assets

            local current_v_col_idx = 1 # Counter for the current column index in the v matrix

            for df_in_trimmed in trimmed_data[tf]
                if !isempty(df_in_trimmed)
                    asset_meta_name = raw(metadata(df_in_trimmed, "asset_instance"))
                    if asset_meta_name == benchmark_name
                       benchmark_df_trimmed = df_in_trimmed
                       benchmark_v_column_idx = current_v_col_idx # Record the column index in v
                    else
                       # This is an asset DataFrame, store its name and its column index in v
                       push!(asset_names_and_v_indices, (asset_meta_name, current_v_col_idx))
                    end
                    current_v_col_idx += 1 # Increment for the next non-empty DataFrame
                end
            end

            if isnothing(benchmark_df_trimmed) || isnothing(benchmark_v_column_idx)
                 @warn "External benchmark DataFrame (with metadata key '$benchmark_name') not found in trimmed data after centering." asset_metadata=[(raw(metadata(d, "asset_instance", "<missing>")), names(d)) for d in trimmed_data[tf] if !isempty(d)]
                 return DataFrame()
            end

            # benchmark_v_column_idx now correctly points to the benchmark's column in v
            benchmark_returns = v[:, benchmark_v_column_idx]
            @debug "Using aligned external DataFrame (key: '$benchmark_name') as benchmark."

            # Separate the collected asset names and indices
            asset_names = [pair[1] for pair in asset_names_and_v_indices]
            cols_to_keep_v_indices = [pair[2] for pair in asset_names_and_v_indices]

            if isempty(asset_names) || size(v, 1) < 2 || isempty(cols_to_keep_v_indices)
                 @warn "Not enough aligned asset data after centering and excluding external benchmark, or no assets left."
                 return DataFrame()
            end

            # Ensure cols_to_keep_v_indices are valid for v's dimensions
            if any(idx -> idx < 1 || idx > size(v, 2), cols_to_keep_v_indices)
                 @error "Calculated column indices for assets are out of bounds for the centered matrix." indices=cols_to_keep_v_indices matrix_size=size(v) asset_info=asset_names_and_v_indices benchmark_name=benchmark_name
                 return DataFrame()
            end

            centered_v_assets = v[:, cols_to_keep_v_indices]
            centered_df = DataFrame(centered_v_assets, asset_names) # Create DataFrame from centered asset data

        catch e
            @warn "Centering combined data with external benchmark failed." exception = e
            return DataFrame() # Return empty DataFrame on centering failure
        end

    else
        # No external DataFrame, proceed with existing logic using flattened universe data
        # Get flattened data
        flattened_data = st.coll.flatten(universe_data; noempty=true)

        # Apply center_data to the flattened universe data
        try
            (trimmed_data, v) = center_data(flattened_data, tf; ratio_func=ratio!) # Using ratio! directly, assuming it's in scope
            asset_names = [raw(metadata(df, "asset_instance")) for df in trimmed_data[tf] if !isempty(df)]
            centered_df = DataFrame(v, asset_names)

            if isempty(asset_names) || size(centered_df, 1) < 2
                 @warn "Not enough data or assets available to calculate beta after centering."
                 return DataFrame()
            end

        catch e
            @warn "Centering universe data failed." exception = e
            return DataFrame()
        end

        # Determine benchmark returns based on symbol or string from the centered asset data

        # Get volume-sorted asset names that are also in the centered data
        all_volume_sorted_assets = tickers(st.getexchange!(s.exchange), s.qc; min_vol=min_vol, as_vec=true)
        volume_sorted_assets = [asset for asset in all_volume_sorted_assets if asset in asset_names]

        if typeof(benchmark) <: String
            # Use specific asset as benchmark
             if !(benchmark in asset_names)
                  @warn "Specified benchmark asset \"$(benchmark)\" is not in the strategy's universe or centered data."
                  return DataFrame()
             end
             benchmark_name = benchmark
             benchmark_returns = centered_df[:, benchmark_name]
             @debug "Using specific asset \"$(benchmark)\" as benchmark."

        elseif typeof(benchmark) <: Symbol
            if benchmark == :top_asset || benchmark == :top_5_percent

                if isempty(volume_sorted_assets)
                    @warn "No assets meet the minimum volume requirement or are not in the data to determine $(benchmark) benchmark."
                    return DataFrame()
                end

                if benchmark == :top_asset
                    benchmark_name = last(volume_sorted_assets)
                    if !(benchmark_name in names(centered_df))
                         @warn "Top asset \"$(benchmark_name)\" not in centered data columns."
                         return DataFrame()
                    end
                    benchmark_returns = centered_df[:, benchmark_name]
                    @debug "Using top asset \"$(benchmark_name)\" as benchmark."
                elseif benchmark == :top_5_percent
                    # Select top 5% assets (at least one)
                    num_top_5_percent = max(1, floor(Int, length(volume_sorted_assets) * 0.05))
                    benchmark_assets = volume_sorted_assets[1:min(num_top_5_percent, end)]

                    if isempty(benchmark_assets)
                        @warn "Could not select top 5% assets for benchmark."
                        return DataFrame()
                    end

                    # Calculate aggregate returns (mean of returns across selected assets)
                    # Ensure all benchmark_assets are in centered_df columns
                    valid_benchmark_assets = [asset for asset in benchmark_assets if asset in names(centered_df)]
                    if isempty(valid_benchmark_assets)
                         @warn "Selected top 5% assets not found in centered data columns."
                         return DataFrame()
                    end

                    benchmark_returns = mean(Matrix(@view centered_df[:, valid_benchmark_assets]); dims=2)[:, 1]
                    benchmark_name = "Top $(length(valid_benchmark_assets)) Assets Aggregate"
                    @debug "Using aggregate of top $(length(valid_benchmark_assets)) assets as benchmark: $(valid_benchmark_assets)"
                end
            else
                error("Invalid benchmark symbol: $(benchmark). Must be :top_asset or :top_5_percent.")
            end
        else
            # This case should not be reached due to the initial type check,
            # but included for completeness.
             error("Invalid benchmark type after initial check: $(typeof(benchmark)).")
        end
    end # end of if/else block handling benchmark types

    # Check if benchmark_returns were successfully determined and match the length of centered data
    if !(@isdefined benchmark_returns) || isempty(benchmark_returns)
         @warn "Benchmark returns could not be determined."
         return DataFrame()
    end

     if length(benchmark_returns) != size(centered_df, 1)
          @warn "Aligned benchmark data length ($(length(benchmark_returns))) does not match aligned asset data length ($(size(centered_df, 1))). This indicates an issue with alignment or data processing."
          return DataFrame()
     end

    # --- New code for handling 'tail' argument ---
    local data_length = size(centered_df, 1)
    local returns_to_use_df::DataFrame
    local benchmark_returns_to_use::Vector{DFT}

    if tail !== nothing
        if tail <= 0
            @warn "Invalid 'tail' value provided. Must be a positive integer." tail=tail
            return DataFrame()
        end
        if tail > data_length
            @warn "'tail' value ($(tail)) is greater than the available data length ($(data_length)). Using all available data." tail=tail data_length=data_length
            returns_to_use_df = centered_df
            benchmark_returns_to_use = benchmark_returns
        else
            @debug "Using last $(tail) data points for Beta calculation."
            returns_to_use_df = centered_df[end-tail+1:end, :]
            benchmark_returns_to_use = benchmark_returns[end-tail+1:end]
        end
    else
        # If tail is not provided, use all available data
        returns_to_use_df = centered_df
        benchmark_returns_to_use = benchmark_returns
    end

    # Ensure sufficient data points are available AFTER applying the tail (if any)
    if size(returns_to_use_df, 1) < 2
         @warn "Not enough data points to calculate beta after applying 'tail' or centering." data_points=size(returns_to_use_df, 1) minimum_required=2
         return DataFrame()
    end
    # --- End of new code for handling 'tail' argument ---

    # Determine the columns for the results DataFrame
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

    # Prepare to collect results
    results_data = []

    # Convert centered_df to matrix for efficient calculations - NOW using returns_to_use_df
    centered_matrix = Matrix(returns_to_use_df)

    # Initialize result variables - ensure type can handle missing
    local beta_cov_results::Union{Vector{<:Union{DFT, Missing}}, Nothing} = nothing
    local beta_reg_results::Union{Vector{<:Union{DFT, Missing}}, Nothing} = nothing

    # Calculate betas based on the specified method using vectorized operations
    if method == :covariance || method == :both
        # Calculate covariance vector: cov(asset_returns, benchmark_returns) for all assets
        # NOW using benchmark_returns_to_use
        cov_vector = cov(centered_matrix, benchmark_returns_to_use)

        # Calculate variance of benchmark returns - NOW using benchmark_returns_to_use
        var_market = var(benchmark_returns_to_use)

        if abs(var_market) < eps(DFT)
            @warn "Cannot calculate Beta by Covariance: Market variance is zero or near zero."
            # Fill with missing, ensuring the type can handle it
            beta_cov_results = Vector{Union{DFT, Missing}}(fill(missing, length(asset_names)))
        else
            # Beta_Covariance = Covariance(asset returns, benchmark returns) / Variance(market returns)
            # Ensure the result vector can hold missing in case of Inf/NaN
            cov_vector_result = vec(cov_vector ./ var_market)
            beta_cov_results = Vector{Union{DFT, Missing}}(cov_vector_result)
            replace!(beta_cov_results, NaN=>missing, Inf=>missing, -Inf=>missing)
        end
    end

    if method == :regression || method == :both
        # Perform linear regression for all assets against the benchmark
        # Model: centered_matrix (asset returns) = intercept + beta * benchmark_returns + error

        # Prepare data for regression: benchmark_returns as the predictor (X) and centered_matrix as the response (Y)
        # NOW using benchmark_returns_to_use
        # Add intercept column to benchmark_returns vector - NOW using benchmark_returns_to_use
        X = hcat(fill(one(DFT), size(returns_to_use_df, 1)), benchmark_returns_to_use)
        Y = centered_matrix

        # Perform linear regression using the backslash operator for least squares
        try
            beta_matrix = X \ Y
            # Extract Beta coefficients (second row of the coefficients matrix)
            # Ensure the result can hold missing if any calculation resulted in NaN/Inf
            beta_reg_results_temp_vec = vec(beta_matrix[2, :])
            # Convert to a vector that can hold missing and replace NaNs/Infs
            beta_reg_results = Vector{Union{DFT, Missing}}(beta_reg_results_temp_vec)
            replace!(beta_reg_results, NaN=>missing, Inf=>missing, -Inf=>missing)

        catch e
            @warn "Could not calculate Beta by Regression" exception = e
             # Fill with missing, ensuring the type can handle it
            beta_reg_results = Vector{Union{DFT, Missing}}(fill(missing, length(asset_names)))
        end
    end

    # Collect results
    for (i, asset_name) in enumerate(asset_names)
        row_data = (Asset = asset_name,)
        if method == :covariance || method == :both
            # Check if beta_cov_results was calculated (i.e., method includes covariance)
            if beta_cov_results !== nothing
                # Get the value - it can be Missing
                beta_cov_val = beta_cov_results[i]
                row_data = merge(row_data, (Beta_Covariance = beta_cov_val,))
            else
                 # This case should ideally not be reached if initialization and fill(missing) are correct,
                 # but kept for safety.
                 row_data = merge(row_data, (Beta_Covariance = missing,))
            end
        end
        if method == :regression || method == :both
            # Check if beta_reg_results was calculated (i.e., method includes regression)
            if beta_reg_results !== nothing
                # Get the value - it can be Missing
                beta_reg_val = beta_reg_results[i]
                row_data = merge(row_data, (Beta_Regression = beta_reg_val,))
            else
                 # This case should ideally not be reached if initialization and fill(missing) are correct,
                 # but kept for safety.
                 row_data = merge(row_data, (Beta_Regression = missing,))
            end
        end
        push!(results_data, row_data)
    end

    # Construct the final DataFrame with only relevant columns
    results_df = DataFrame(results_data, result_cols)

    return results_df
end

export beta_indicator



