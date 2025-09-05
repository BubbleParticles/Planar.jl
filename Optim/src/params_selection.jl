using Metrics.Data: DataFrame
using Metrics: mean, median
using SimMode.Misc: attr

# Wrapper for median that handles vector of vectors
function safe_median(values)
    if !isempty(values) && values[1] isa AbstractVector
        # Convert vector of vectors to matrix and apply median across dim=2
        matrix = hcat(values...)
        return vec(median(matrix; dims=2))
    else
        return median(values)
    end
end

function _filter_results(os::OptSession)
    results = filter([:trades] => trades -> trades > 0, os.results)
    pnames = keys(os.params)
    unique(results, [pnames...])
end


@doc """ Selects the most different parameter combinations from optimization results.

$(TYPEDSIGNATURES)

- `sess`: The optimization session containing results
- `n`: Number of parameter combinations to select (default: 10)
- `metric`: Distance metric to use (:euclidean, :manhattan, :cosine, default: :euclidean)

Returns a DataFrame with the most diverse parameter combinations that have at least 1 trade.
"""
function select_diverse_params(sess::OptSession; n::Int=10, metric::Symbol=:euclidean)
    # Filter results to only include those with at least 1 trade
    filtered_results = _filter_results(sess)

    if nrow(filtered_results) == 0
        @warn "No results with trades found. Returning empty DataFrame."
        return DataFrame()
    end

    if nrow(filtered_results) <= n
        return filtered_results
    end

    # Extract parameter columns
    param_cols = [keys(sess.params)...]
    param_data = Matrix{Float64}(undef, nrow(filtered_results), length(param_cols))

    # Convert parameters to numeric matrix
    for (i, col) in enumerate(param_cols)
        for (j, row) in enumerate(eachrow(filtered_results))
            val = getproperty(row, col)
            # Handle different parameter types
            if val isa Period
                param_data[j, i] = val.value # Convert to numeric value
            elseif val isa AbstractFloat || val isa Integer
                param_data[j, i] = Float64(val)
            else
                param_data[j, i] = 0.0  # Default for unsupported types
            end
        end
    end

    # Normalize parameters to [0,1] range for fair comparison
    for i in 1:size(param_data, 2)
        col_min, col_max = extrema(param_data[:, i])
        if col_max > col_min
            param_data[:, i] = (param_data[:, i] .- col_min) ./ (col_max - col_min)
        end
    end

    # Calculate distance matrix
    distances = Matrix{Float64}(undef, nrow(filtered_results), nrow(filtered_results))
    for i in 1:nrow(filtered_results)
        for j in 1:nrow(filtered_results)
            if i == j
                distances[i, j] = 0.0
            else
                if metric == :euclidean
                    distances[i, j] = sqrt(sum((param_data[i, :] .- param_data[j, :]) .^ 2))
                elseif metric == :manhattan
                    distances[i, j] = sum(abs.(param_data[i, :] .- param_data[j, :]))
                elseif metric == :cosine
                    dot_prod = sum(param_data[i, :] .* param_data[j, :])
                    norm_i = sqrt(sum(param_data[i, :] .^ 2))
                    norm_j = sqrt(sum(param_data[j, :] .^ 2))
                    if norm_i > 0 && norm_j > 0
                        distances[i, j] = 1 - dot_prod / (norm_i * norm_j)
                    else
                        distances[i, j] = 1.0
                    end
                else
                    error("Unknown metric: $metric")
                end
            end
        end
    end

    # Greedy selection of most diverse points
    selected = Int[]
    remaining = collect(1:nrow(filtered_results))

    # Start with the point that has maximum average distance to all others
    avg_distances = vec(mean(distances; dims=2))
    push!(selected, argmax(avg_distances))
    deleteat!(remaining, findfirst(isequal(selected[1]), remaining))

    # Iteratively select points that maximize minimum distance to already selected points
    for _ in 2:n
        if isempty(remaining)
            break
        end

        min_distances = Float64[]
        for idx in remaining
            min_dist = minimum(distances[idx, selected])
            push!(min_distances, min_dist)
        end

        next_idx = remaining[argmax(min_distances)]
        push!(selected, next_idx)
        deleteat!(remaining, findfirst(isequal(next_idx), remaining))
    end

    return filtered_results[selected, :]
end

@doc """ Selects parameter combinations with the best performance.

$(TYPEDSIGNATURES)

- `sess`: The optimization session containing results
- `n`: Number of parameter combinations to select (default: 10)
- `sort_by`: Column to sort by (:pnl, :cash, :obj, default: :pnl)
- `ascending`: Whether to sort in ascending order (default: false for best performance)

Returns a DataFrame with the best performing parameter combinations that have at least 1 trade.
"""
function select_best_params(
    sess::OptSession; n::Int=10, sort_by::Symbol=:pnl, ascending::Bool=false
)
    # Filter results to only include those with at least 1 trade
    filtered_results = _filter_results(sess)

    if nrow(filtered_results) == 0
        @warn "No results with trades found. Returning empty DataFrame."
        return DataFrame()
    end

    if nrow(filtered_results) <= n
        return sort(filtered_results, [sort_by]; rev=!ascending)
    end

    sorted_results = sort(filtered_results, [sort_by]; rev=!ascending)
    return sorted_results[1:n, :]
end

@doc """ Selects parameter combinations that are both diverse and performant.

$(TYPEDSIGNATURES)

- `sess`: The optimization session containing results
- `n`: Number of parameter combinations to select (default: 10)
- `sort_by`: Column to sort by for performance (:pnl, :cash, :obj, default: :pnl)

Returns a DataFrame with balanced diverse and performant parameter combinations that have at least 1 trade.
"""
function select_balanced_params(sess::OptSession; n::Int=10, sort_by::Symbol=:pnl)
    # Filter results to only include those with at least 1 trade
    filtered_results = _filter_results(sess)

    if nrow(filtered_results) == 0
        @warn "No results with trades found. Returning empty DataFrame."
        return DataFrame()
    end

    if nrow(filtered_results) <= n
        return filtered_results
    end

    # Get diverse and best parameters
    diverse_params = select_diverse_params(sess; n=div(n, 2))
    best_params = select_best_params(sess; n=div(n, 2), sort_by)

    # Combine and remove duplicates
    combined = vcat(diverse_params, best_params)
    unique_indices = unique(i -> hash(combined[i, :]), 1:nrow(combined))
    result = combined[unique_indices, :]

    # If we have fewer than n unique combinations, add more from the filtered results
    if nrow(result) < n
        # Get the indices of rows that are already in our result
        used_indices = Int[]
        for (i, orig_row) in enumerate(eachrow(filtered_results))
            for result_row in eachrow(result)
                if all(collect(orig_row) .== collect(result_row))
                    push!(used_indices, i)
                    break
                end
            end
        end

        remaining = setdiff(1:nrow(filtered_results), used_indices)
        if !isempty(remaining)
            additional_needed = n - nrow(result)
            additional = filtered_results[
                remaining[1:min(additional_needed, length(remaining))], :,
            ]
            result = vcat(result, additional)
        end
    end

    return result[1:min(n, nrow(result)), :]
end

@doc """ Groups session results by repeat and aggregates metrics columns.

$(TYPEDSIGNATURES)

- `sess`: The optimization session containing results
- `sort_by`: Column to sort by (default: :pnl_avg)
- `filter_zero_trades`: Filter out rows with 0 trades (default: true)

Returns a DataFrame with one row per unique parameter combination, containing:
- Parameter columns (from first row of each group)
- Aggregated metrics: average, median, min, max for obj, cash, pnl, trades
"""
function agg(sess::OptSession; sort_by::Symbol=:pnl_avg, filter_zero_trades::Bool=true)
    if isempty(sess.results)
        @warn "No results found in session. Returning empty DataFrame."
        return DataFrame()
    end
    
    # Get parameter column names
    param_cols = [keys(sess.params)...]
    param_cols_str = [string(col) for col in param_cols]
    metric_cols = ["obj", "cash", "pnl", "trades"]
    
    # Group by parameter combinations (excluding repeat column)
    grouped = groupby(sess.results, param_cols)
    
    if length(grouped) == 0
        @warn "No groups found after grouping by parameters. Returning empty DataFrame."
        return DataFrame()
    end
    
    # Create aggregated results
    aggregated_rows = []
    
    for group in grouped
        # Get parameter values from first row
        first_row = group[1, :]
        param_values = [first_row[col] for col in param_cols]
        
        # Create row maintaining original column order
        row_data = Dict{Any, Any}()
        
        # Process each column in the original order
        for col in names(sess.results)
            if string(col) == "repeat"
                # Skip repeat column
                continue
            elseif string(col) in param_cols_str
                # Add parameter column
                col_idx = findfirst(x -> string(x) == string(col), param_cols)
                row_data[col] = param_values[col_idx]
            elseif string(col) in metric_cols
                # Replace metric column with its 4 aggregated versions
                values = group[!, col]
                row_data[Symbol("$(col)_avg")] = mean(values)
                row_data[Symbol("$(col)_med")] = safe_median(values)
                row_data[Symbol("$(col)_min")] = minimum(values)
                row_data[Symbol("$(col)_max")] = maximum(values)
            else
                # Handle any other columns by taking the first value
                row_data[col] = group[1, col]
            end
        end
        
        push!(aggregated_rows, row_data)
    end
    
    # Convert to DataFrame - ensure proper column ordering
    if isempty(aggregated_rows)
        return DataFrame()
    end
    
    # Get all column names in the correct order
    all_cols = []
    for col in names(sess.results)
        if string(col) == "repeat"
            continue
        elseif string(col) in param_cols_str
            push!(all_cols, col)
        elseif string(col) in metric_cols
            push!(all_cols, Symbol("$(col)_avg"))
            push!(all_cols, Symbol("$(col)_med"))
            push!(all_cols, Symbol("$(col)_min"))
            push!(all_cols, Symbol("$(col)_max"))
        else
            push!(all_cols, col)
        end
    end
    
    # Create DataFrame with proper structure
    result_df = DataFrame()
    for col in all_cols
        result_df[!, col] = [row[col] for row in aggregated_rows]
    end
    
    # Filter out rows with 0 trades if requested
    if filter_zero_trades && "trades_avg" in names(result_df)
        result_df = filter([:trades_avg] => trades -> trades > 0, result_df)
    end
    
    # Sort by the specified column if it exists
    if string(sort_by) in names(result_df)
        sort!(result_df, [sort_by]; rev=false)  # Sort in descending order (best first)
    end
    
    return result_df
end

@doc """ Extracts parameter values from a specific row as a named tuple.

$(TYPEDSIGNATURES)

- `df`: DataFrame containing aggregated results (from agg function)
- `row_idx`: Row index to extract parameters from (default: 1 for best result)

Returns a named tuple with parameter names as keys and their values.
"""
function get_params(df::DataFrame, row_idx::Int=1)
    if isempty(df)
        error("DataFrame is empty")
    end
    
    # Handle negative indexing (convert to positive)
    if row_idx < 0
        row_idx = nrow(df) + row_idx + 1
    end
    
    if row_idx < 1 || row_idx > nrow(df)
        error("Row index $row_idx is out of bounds for DataFrame with $(nrow(df)) rows")
    end
    
    # Get parameter columns (exclude metric columns)
    param_cols = filter(name -> !occursin(r"_(avg|med|min|max)$", string(name)), names(df))
    
    # Extract parameter values from the specified row
    param_values = [df[row_idx, col] for col in param_cols]
    
    # Create named tuple
    return NamedTuple{Tuple(Symbol.(param_cols))}(param_values)
end

export select_diverse_params, select_best_params, select_balanced_params, agg, get_params