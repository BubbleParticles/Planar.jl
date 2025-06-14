# gpu_indicators.jl

import OnlineTechnicalIndicators as oti
# Assuming oneAPI might be available in Main, consistent with previous steps.
# For robust package development, oneAPI should be a proper dependency.

# Helper function to check oneAPI availability and functionality
function is_oneapi_functional()
    if !isdefined(Main, :oneAPI)
        return false
    end
    oneAPI_module = getfield(Main, :oneAPI)
    if !isdefined(oneAPI_module, :functional) || !isdefined(oneAPI_module, :oneArray) || !isdefined(oneAPI_module, :Array)
        return false # Added Main.oneAPI.Array check for completeness
    end
    return oneAPI_module.functional()
end

# Helper function to ensure a value is a CPU scalar
function ensure_cpu_scalar(val)
    if is_oneapi_functional() # Check if oneAPI is available before trying to access its types
        oneAPI_module = getfield(Main, :oneAPI)
        if isa(val, oneAPI_module.oneArray)
            # Assuming val is a 1-element oneArray if it's a scalar from GPU
            return oneAPI_module.Array(val)[]
        end
    end
    return val # Assume it's already a CPU scalar or not a oneArray type
end

"""
    fit_gpu!(indicator::oti.OnlineIndicator, new_value)

Fits a `new_value` into an OnlineTechnicalIndicators.jl `indicator`.
If `oneAPI` is functional and the indicator's internal data buffer (`input_values.buffer`)
is a `oneAPI.oneArray`, data transfers are handled to perform the `fit!` operation
on the CPU and then the updated buffer is moved back to the GPU.
Otherwise, performs a standard CPU `oti.fit!`.

Assumes `indicator.input_values.buffer` is the path to the internal data array.
This might need adjustment for different OTI indicator types.
"""
function fit_gpu!(indicator::T, new_value) where {T <: oti.OnlineIndicator}
    # This function is generic for oti.OnlineIndicator.
    # Specific handling might be needed if buffer access differs significantly between indicators.
    # For oti.SMA, input_values.buffer seems appropriate.

    cpu_new_value = ensure_cpu_scalar(new_value)

    # Attempt to access the buffer; this path is common for WindowedIndicator types in OTI
    if !hasproperty(indicator, :input_values) || !hasproperty(indicator.input_values, :buffer)
        # Fallback for indicators that don't match the expected structure
        # Or, could throw an error if strict GPU path is expected for certain types.
        oti.fit!(indicator, cpu_new_value)
        return indicator
    end

    buffer_accessor = indicator.input_values # This is a CircularBuffer

    if is_oneapi_functional() && isa(buffer_accessor.buffer, getfield(Main, :oneAPI).oneArray)
        oneAPI_module = getfield(Main, :oneAPI) # Safe due to is_oneapi_functional

        # GPU Buffer Path
        original_gpu_buffer = buffer_accessor.buffer
        cpu_buffer_for_fit = oneAPI_module.Array(original_gpu_buffer) # Convert GPU buffer to CPU Array

        # Temporarily assign the CPU buffer to the indicator for oti.fit!
        # This assumes that oti.fit! primarily works on this buffer and
        # the rest of the indicator's state is compatible with this temporary change.
        buffer_accessor.buffer = cpu_buffer_for_fit

        try
            oti.fit!(indicator, cpu_new_value) # fit! now operates on the CPU buffer
        finally
            # Always ensure the buffer is converted back and reassigned, even if fit! errors.
            # The buffer inside 'indicator' (which is buffer_accessor.buffer) was modified by fit!
            # and is currently a CPU array. Convert it back to oneArray.
            buffer_accessor.buffer = oneAPI_module.oneArray(buffer_accessor.buffer)
        end
    else
        # CPU Buffer Path (or oneAPI not functional)
        oti.fit!(indicator, cpu_new_value)
    end

    return indicator # Return the modified indicator
end

export fit_gpu!, is_oneapi_functional # Export the new function and the helper

# The old sma_gpu (functional version) is removed as per plan.
# If a functional, one-shot GPU SMA is still needed, it could be reintroduced
# separately, but fit_gpu! now handles the stateful, online update aspect.
