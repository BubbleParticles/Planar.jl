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
@doc """
    _fit_gpu_generic!(indicator::oti.OnlineIndicator, cpu_new_value)

Generic fallback for GPU-aware fitting of an OnlineTechnicalIndicators.jl `indicator`.
This function is used by `fit_gpu!` when a specialized GPU path for the given
indicator type (e.g., `oti.SMA`) is not available, or if GPU resources are not functional.

It handles indicators with an internal buffer (commonly `indicator.input_values.buffer`)
that might be a `oneAPI.oneArray`.
- If the buffer is a `oneAPI.oneArray`, it's copied to the CPU.
- `oti.fit!` is then called with the CPU buffer.
- Finally, the (potentially modified) CPU buffer is copied back to a `oneAPI.oneArray`
  and reassigned to the indicator.
- If the buffer is already CPU-based, `oti.fit!` is called directly.

This ensures correct calculation by relying on OTI's standard `fit!` method but may
incur performance costs due to full buffer transfers if used frequently with GPU buffers.
"""
function _fit_gpu_generic!(indicator::T, cpu_new_value) where {T <: oti.OnlineIndicator}
    # Attempt to access the buffer; this path is common for WindowedIndicator types in OTI like SMA, EMA.
    if !hasproperty(indicator, :input_values) || !hasproperty(indicator.input_values, :buffer)
        # If the indicator doesn't have the expected buffer structure,
        # call standard oti.fit! directly.
        oti.fit!(indicator, cpu_new_value)
        return indicator
    end

    buffer_accessor = indicator.input_values # This is a CircularBuffer

    if is_oneapi_functional() && isa(buffer_accessor.buffer, getfield(Main, :oneAPI).oneArray)
        oneAPI_module = getfield(Main, :oneAPI)

        original_gpu_buffer = buffer_accessor.buffer
        cpu_buffer_for_fit = oneAPI_module.Array(original_gpu_buffer)
        buffer_accessor.buffer = cpu_buffer_for_fit

        try
            oti.fit!(indicator, cpu_new_value)
        finally
            buffer_accessor.buffer = oneAPI_module.oneArray(buffer_accessor.buffer)
        end
    else
        oti.fit!(indicator, cpu_new_value)
    end
    return indicator
end

@doc """
    sma_update_kernel!(buffer, new_val, old_val_out, idx, is_full)

A `oneAPI.jl` kernel to update a circular buffer for SMA calculation directly on the GPU.
It writes `new_val` to `buffer` at `idx`. If `is_full` is true, the value being
overwritten in `buffer[idx]` is first stored in `old_val_out[1]`.

Parameters:
- `buffer::oneAPI.oneDeviceArray`: The circular buffer data (e.g., prices) residing on the GPU.
- `new_val::T_val`: The new value to be added to the buffer.
- `old_val_out::oneAPI.oneDeviceArray`: A 1-element `oneAPI.oneDeviceArray` to store the value that rolls off the buffer if it's full.
- `idx::Int`: The current 1-based index in the circular buffer where `new_val` should be placed.
- `is_full::Bool`: A boolean indicating if the buffer was full before adding `new_val`.
"""
function sma_update_kernel!(
    buffer::oneAPI.oneDeviceArray, # More specific type for device data
    new_val::T_val,                # Generic type for new_val
    old_val_out::oneAPI.oneDeviceArray, # More specific type for device data
    idx::Int,
    is_full::Bool
) where {T_val <: Real} # Constrain new_val to Real
    if is_full
        old_val_out[1] = buffer[idx] # Store the value that will be overwritten
    else
        # If buffer not full, no value is "rolling off" in the traditional sense for sum adjustment.
        # Storing zero ensures correct arithmetic if old_val_cpu is always subtracted.
        old_val_out[1] = zero(eltype(buffer))
    end
    buffer[idx] = new_val # Place the new value into the buffer
    return nothing
end

@doc """
    fit_gpu!(indicator::oti.SMA, new_value)

Specialized `fit_gpu!` for `OnlineTechnicalIndicators.SMA` (Simple Moving Average).
This function implements a hybrid GPU update mechanism when `oneAPI.jl` is functional
and the SMA's internal buffer (`indicator.input_values.buffer`) is a `oneAPI.oneArray`.

The hybrid approach is as follows:
1.  The new value (`new_value`) is ensured to be a CPU scalar.
2.  The `sma_update_kernel!` is launched on the GPU. This kernel:
    a.  Writes the `new_value` into the correct slot in the GPU buffer.
    b.  If the buffer is full, it captures the "rolled-off" value (the one being overwritten)
        and stores it in a temporary 1-element GPU array. If not full, zero is stored.
3.  The rolled-off value (or zero) is copied back from the GPU to the CPU.
4.  The SMA's sum (`indicator.sum`) and final value (`indicator.value`) are updated on the CPU
    using the new value and the rolled-off value.
5.  The metadata of the `CircularBuffer` (index, length, is_full status) is also updated on the CPU.

This method significantly reduces GPU-CPU data transfer compared to copying the entire buffer,
as only the new value (effectively as a kernel argument) and the single rolled-off value cross
the GPU-CPU boundary per update. The main buffer remains on the GPU.

If the GPU path is not applicable (e.g., `oneAPI.jl` not functional, buffer is not a `oneAPI.oneArray`,
or the indicator does not have an accessible `sum` field), it falls back to `_fit_gpu_generic!`.

Assumptions:
- The `oti.SMA` struct has an accessible `sum` field that stores the current sum of elements in its window.
- The `indicator.input_values` is a `CircularBuffer` with accessible fields like `idx`, `length`, `isfull`, `buffer`.
- `indicator.period` gives the window size of the SMA.
"""
function fit_gpu!(indicator::oti.SMA, new_value)
    cpu_new_value = ensure_cpu_scalar(new_value) # Ensure new_value is a CPU scalar
    oneAPI_module = is_oneapi_functional() ? getfield(Main, :oneAPI) : nothing

    buffer_accessor = indicator.input_values # This is typically a CircularBuffer for SMA
    # Check if GPU path is viable: oneAPI functional, buffer is a oneAPI array, and indicator has a 'sum' field.
    can_use_gpu_path = oneAPI_module !== nothing &&
                       isa(buffer_accessor.buffer, oneAPI_module.oneArray) &&
                       hasproperty(indicator, :sum) # Crucial for current hybrid approach

    if can_use_gpu_path
        # GPU Path for SMA
        gpu_buffer = buffer_accessor.buffer # This is a oneAPI.oneArray
        T_buffer = eltype(gpu_buffer)

        # State from CircularBuffer (CPU)
        cb_idx = buffer_accessor.idx
        cb_len = buffer_accessor.length
        cb_isfull = buffer_accessor.isfull
        cb_period = indicator.period # Assuming this is how to get SMA period

        # 1. Insert new value into GPU buffer and get the rolled-off value
        #    Need a 1-element GPU array to store the old value if any
        old_val_gpu = oneAPI_module.oneArray{T_buffer}(undef, 1)

        # oneAPI kernel launch
        # Ensure cb_idx is 1-based if OTI uses 0-based internally and adjust if necessary.
        # For now, assume oti.CircularBuffer.idx is 1-based for direct use in sma_update_kernel!.
        oneAPI_module.@oneapi items=1 groups=1 sma_update_kernel!(
            gpu_buffer,                 # Pass the device array directly
            T_buffer(cpu_new_value),    # Ensure new value is of buffer's eltype
            old_val_gpu,
            cb_idx,
            cb_isfull
        )

        old_val_cpu = oneAPI_module.Array(old_val_gpu)[1] # Copy the single rolled-off value back to CPU

        # 2. Update sum and value on CPU.
        # This part relies on `indicator.sum` being an accessible field of the SMA struct
        # and that it's a CPU scalar. OTI's internal sum management might be different.
        # This hybrid approach is a compromise to avoid full buffer copies while still
        # leveraging OTI's structure for state management as much as possible.

        # Update the sum:
        # Note: T_buffer(cpu_new_value) ensures type consistency for the sum.
        if cb_isfull
            indicator.sum = indicator.sum - old_val_cpu + T_buffer(cpu_new_value)
        else
            # If buffer wasn't full, old_val_cpu is zero, so sum is just incremented.
            # Or, if length increases, sum is just new_value + previous sum.
            # OTI's logic for non-full buffer sum update is typically just adding the new value.
            indicator.sum = indicator.sum + T_buffer(cpu_new_value)
        end

        # Update CircularBuffer state on CPU side (mimicking OTI's CircularBuffer behavior).
        # This state management remains on the CPU.
        buffer_accessor.idx = (cb_idx == cb_period) ? 1 : cb_idx + 1
        if !cb_isfull && cb_len < cb_period
            buffer_accessor.length += 1
            if buffer_accessor.length == cb_period
                buffer_accessor.isfull = true
            end
        end

        indicator.value = indicator.sum / buffer_accessor.length
        # This direct manipulation assumes `indicator.sum` and `indicator.value` are accessible and of CPU type.
        # If `indicator.sum` or `indicator.value` are intended to be `oneArray`s, this needs adjustment.
        # For now, assume they are CPU properties.

    else
        # Fallback to generic (CPU or copy-based) for SMA if not on GPU path
        _fit_gpu_generic!(indicator, cpu_new_value)
    end
    return indicator
end

# Generic fit_gpu! that dispatches
function fit_gpu!(indicator::T, new_value) where {T <: oti.OnlineIndicator}
    # This is the main entry point, it will call specialized versions if they exist.
    # For now, it directly calls the generic or SMA-specific one.
    # A more extensible way would be to use a trait or multiple dispatch more deeply.
    if indicator isa oti.SMA
        return fit_gpu!(indicator, new_value) # Calls the ::oti.SMA version
    # elseif indicator isa oti.EMA
        # return fit_gpu!(indicator, new_value) # Call EMA version when implemented
    else
        cpu_new_value = ensure_cpu_scalar(new_value)
        return _fit_gpu_generic!(indicator, cpu_new_value)
    end
end


export fit_gpu!, is_oneapi_functional

# --- Conceptual EMA GPU Update ---
# The following is a commented-out conceptual outline for a GPU-accelerated EMA.
# It's provided as a guideline for potential future development.
# EMA calculation is `new_ema = (price * alpha) + (prev_ema * (1-alpha))`.
#
# Challenges for a full GPU EMA:
# - `indicator.value` (previous EMA) needs to be a GPU scalar or efficiently accessed.
# - `indicator.alpha` (smoothing factor) is typically a CPU scalar.
# - OTI's EMA often has a startup period (e.g., using SMA initially based on `indicator.n`
#   and `indicator.period`) which complicates a pure GPU kernel for all stages.
# - State like `indicator.n` (count of observations) is managed on the CPU.
#
# A truly optimized version might involve a custom EMA indicator struct designed for GPU,
# or more intricate state management synchronization.

# """
#     fit_gpu!(indicator::oti.EMA, new_value)
#
# (Conceptual) Specialized `fit_gpu!` for `OnlineTechnicalIndicators.EMA`.
# Aims to perform EMA calculation on GPU if `indicator.value` is a `oneAPI.oneArray` scalar
# and the indicator is past its initial warm-up phase.
#
# This is a placeholder for future implementation. Current EMA updates via `fit_gpu!`
# will use the `_fit_gpu_generic!` fallback.
# """
# function fit_gpu!(indicator::oti.EMA, new_value)
#     cpu_new_value = ensure_cpu_scalar(new_value)
#     oneAPI_module = is_oneapi_functional() ? getfield(Main, :oneAPI) : nothing
#
#     # Example condition: GPU path if indicator value is a oneArray and past initial period
#     # can_use_gpu_path = oneAPI_module !== nothing &&
#     #                    isa(indicator.value, oneAPI_module.oneArray) &&
#     #                    (hasproperty(indicator, :n) && indicator.n > indicator.period)
#     #
#     # if can_use_gpu_path
#     #     # Placeholder for GPU EMA update logic:
#     #     # 1. Define an ema_update_kernel!
#     #     #    function ema_update_kernel!(new_ema_out, prev_ema_val, price, alpha)
#     #     #        new_ema_out[1] = (price * alpha) + (prev_ema_val * (1.0 - alpha))
#     #     #        return
#     #     #    end
#     #     # 2. Prepare GPU arrays for prev_ema (if not already), new_ema_out.
#     #     # 3. Launch kernel.
#     #     # 4. Update indicator.value with new_ema_out.
#     #     # 5. Update indicator.n on CPU.
#     #     #
#     #     # For now, this path is conceptual and falls back.
#     #     return _fit_gpu_generic!(indicator, cpu_new_value) # Fallback until fully implemented
#     # else
#     #     # Fallback for initial period (where EMA might use SMA) or if not on GPU.
+        return _fit_gpu_generic!(indicator, cpu_new_value) # Default to generic for EMA
#     # end
# end
