@doc """
    ratio_consecutive_along_dim!(output::AbstractArray, A::AbstractArray, dims::Integer)

Calculates the ratio of consecutive elements along a specified dimension `dims`
of an N-dimensional array `A`, writing the result into `output` in-place.
Specifically, it computes A[..., i+1, ...] / A[..., i, ...]
for each index `i` along `dims`.

The `output` array must have the correct dimensions: its size along `dims`
must be one less than `A`'s size along `dims`, and all other dimensions must match.

Arguments:
- `output`: The pre-allocated output array to write results into.
- `A`: The input array.
- `dims`: The dimension along which to compute the ratios.
"""
function ratio!(output::AbstractArray, A::AbstractArray; dims::Integer=1)
    s_in = size(A)
    s_out = size(output)

    # Check for correct output array size
    expected_s_out_tuple = ntuple(i -> i == dims ? s_in[i] - 1 : s_in[i], ndims(A))
    if s_out != expected_s_out_tuple
        throw(ArgumentError("Output array dimensions $(s_out) do not match expected dimensions $(expected_s_out_tuple) for dimension $(dims)."))
    end

    # Create index tuples for the "shifted" and "current" slices
    idx_shifted = ntuple(d -> d == dims ? (firstindex(A, d) + 1 : lastindex(A, d)) : :, ndims(A))
    idx_current = ntuple(d -> d == dims ? (firstindex(A, d) : lastindex(A, d) - 1) : :, ndims(A))

    # Perform the element-wise division using broadcasting into the pre-allocated output
    @. output = (@views A[idx_shifted...] / @views A[idx_current...]) - one(eltype(output))

    return output
end

"""
    ratio(A::AbstractArray, dims::Integer)

Returns a new array with the ratio of consecutive elements along a specified dimension `dims`
of an N-dimensional array `A`.

The returned array has the same size as `A` except for the dimension specified by `dims`, which is one less than `A`'s size along `dims`.

Arguments:
- `A`: The input array.
- `dims`: The dimension along which to compute the ratios.
"""
function ratio(A::Union{Vector{<:Real}, Matrix{<:Real}}; dims::Integer=1)
    s_in = size(A)
    s_out = ntuple(i -> i == dims ? s_in[i] - 1 : s_in[i], ndims(A))
    output = similar(A, s_out)
    ratio!(output, A; dims)
    return output
end

function ratio(A::Vector{<:Vector{<:Real}}; kwargs...)
    return ratio(reduce(hcat, A); kwargs...)
end

"""
    roc_ratio(A::AbstractArray; dims::Integer=1, period::Int=10)

Calculate the Rate of Change (ROC) ratio for an array along the specified dimension.

# Arguments
- `A`: The input array.
- `dims`: The dimension along which to compute the ROC ratios.
- `period`: The lookback period for the ROC calculation.

# Returns
An array of ROC values with the same dimensions as the input, except along the specified dimension
which will be shorter by `period` elements.
"""
function roc_ratio(A::Union{Vector{<:Real}, Matrix{<:Real}}; dims::Integer=1, period::Int=2)
    nd = ndims(A)
    if !(eltype(A) <: Real)
        throw(ArgumentError("Element type must be a subtype of Real, got $(eltype(A))"))
    end
    if !(1 <= dims <= nd)
        throw(ArgumentError("dims=$dims is out of bounds for an array with $nd dimensions."))
    end
    if period <= 0
        throw(ArgumentError("period=$period must be positive. Received $period."))
    end

    s_in = size(A)
    s_out_dim_val = max(0, s_in[dims] - period)
    s_out = ntuple(i -> i == dims ? s_out_dim_val : s_in[i], nd)

    Tout = promote_type(eltype(A), DFT) # Output type will be Float64 or higher if A is already a higher-precision float
    output = similar(A, Tout, s_out)
    
    # roc_ratio_corrected! will now first check if eltype(A) is scalar.
    roc_ratio!(output, A; dims=dims, period=period)
    return output ./ 100.0
end

function roc_ratio(A::Vector{<:Vector}; kwargs...)
    return roc_ratio(reduce(hcat, A); kwargs...)
end

function roc_to_ratio(v)
    return v ./ 100.0
end


"""
    roc_ratio!(output, A; dims::Integer=1, period::Int=10)

In-place version of `roc_ratio` that stores the result in `output`.
"""
function roc_ratio!(output::AbstractArray, A::AbstractArray; dims::Integer=1, period::Int=1)
    # --- Element Type Validation for oti.ROC ---
    # oti.ROC typically works with scalar element types like Float64, Int, etc.
    # We check if eltype(A) is a subtype of Real. Adjust if oti.ROC supports other scalar types (e.g., Complex).
    if !(eltype(A) <: Real) # Or <: Number if Complex numbers are supported by oti.ROC for this indicator
        throw(ArgumentError("Element type of input array A ($(eltype(A))) must be a scalar type (e.g., a subtype of Real) for oti.ROC."))
    end

    # Validate dimensions
    size_A = size(A)
    nd = ndims(A)
    expected_output_size = ntuple(i -> i == dims ? size_A[i] - period : size_A[i], nd)

    if size(output) != expected_output_size
        throw(DimensionMismatch("Output array has incorrect dimensions. Expected $expected_output_size, got $(size(output)) for input size $size_A, dims=$dims, period=$period"))
    end
    
    # Validate period
    period > 0 || throw(ArgumentError("period must be positive. Received $period."))
    # If not enough data along target dimension for any calculation, return (potentially empty) output
    size(A, dims) > period || return roc_to_ratio(output) 

    # Special case for 1D arrays
    if ndims(A) == 1
        roc_calculator = oti.ROC{eltype(A)}(period=period)
        for i in (period+1):size(A, 1)
            oti.fit!(roc_calculator, A[i-period]) 
            oti.fit!(roc_calculator, A[i])        
            output[i-period] = @coalesce roc_calculator.value DFT(0.0) # Ensure fallback is of appropriate type
        end
        return roc_to_ratio(output)
    end
    
    # For N-D arrays (N >= 2)
    roc_calculator = oti.ROC{eltype(A)}(period=period)

    for idx_along_dim_output in 1:(size(A, dims) - period)
        prev_slice_actual_idx_in_A = idx_along_dim_output
        curr_slice_actual_idx_in_A = idx_along_dim_output + period
        
        prev_slab = selectdim(A, dims, prev_slice_actual_idx_in_A)
        curr_slab = selectdim(A, dims, curr_slice_actual_idx_in_A)
        out_slab  = selectdim(output, dims, idx_along_dim_output)

        for I_element_in_slab in CartesianIndices(out_slab)
            prev_val = prev_slab[I_element_in_slab]
            curr_val = curr_slab[I_element_in_slab]
            
            oti.fit!(roc_calculator, prev_val)
            oti.fit!(roc_calculator, curr_val)
            
            out_slab[I_element_in_slab] = @coalesce roc_calculator.value DFT(0.0) # Ensure fallback is of appropriate type
        end
    end
    return roc_to_ratio(output)
end