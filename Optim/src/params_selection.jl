using Metrics.Data: DataFrame
using SimMode.Misc: attr

@doc """ Selects the most different parameter combinations from optimization results.

$(TYPEDSIGNATURES)

- `sess`: The optimization session containing results
- `n`: Number of parameter combinations to select (default: 10)
- `metric`: Distance metric to use (:euclidean, :manhattan, :cosine, default: :euclidean)

Returns a DataFrame with the most diverse parameter combinations that have at least 1 trade.
"""
function select_diverse_params(sess::OptSession; n::Int=10, metric::Symbol=:euclidean)
    # Filter results to only include those with at least 1 trade
    filtered_results = filter([:trades] => trades -> trades > 0, sess.results)
    
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
                    distances[i, j] = sqrt(sum((param_data[i, :] .- param_data[j, :]).^2))
                elseif metric == :manhattan
                    distances[i, j] = sum(abs.(param_data[i, :] .- param_data[j, :]))
                elseif metric == :cosine
                    dot_prod = sum(param_data[i, :] .* param_data[j, :])
                    norm_i = sqrt(sum(param_data[i, :].^2))
                    norm_j = sqrt(sum(param_data[j, :].^2))
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
    avg_distances = vec(mean(distances, dims=2))
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
function select_best_params(sess::OptSession; n::Int=10, sort_by::Symbol=:pnl, ascending::Bool=false)
    # Filter results to only include those with at least 1 trade
    filtered_results = filter([:trades] => trades -> trades > 0, sess.results)
    
    if nrow(filtered_results) == 0
        @warn "No results with trades found. Returning empty DataFrame."
        return DataFrame()
    end
    
    if nrow(filtered_results) <= n
        return sort(filtered_results, [sort_by], rev=!ascending)
    end
    
    sorted_results = sort(filtered_results, [sort_by], rev=!ascending)
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
    filtered_results = filter([:trades] => trades -> trades > 0, sess.results)
    
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
            additional = filtered_results[remaining[1:min(additional_needed, length(remaining))], :]
            result = vcat(result, additional)
        end
    end
    
    return result[1:min(n, nrow(result)), :]
end

export select_diverse_params, select_best_params, select_balanced_params 