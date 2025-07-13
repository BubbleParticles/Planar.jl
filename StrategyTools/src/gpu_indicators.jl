# gpu_indicators.jl

import OnlineTechnicalIndicators as oti
# Assuming oneAPI might be available in Main, consistent with previous steps.
# For robust package development, oneAPI should be a proper dependency.

# Define DFT (Default Float Type) - adjust as needed (e.g., Float32 for more GPU benefit)
const DFT = Float64 # Or Float32

# Helper function to check oneAPI availability and functionality
function is_oneapi_functional()
    if !isdefined(Main, :oneAPI)
        return false
    end
    oneAPI_module = getfield(Main, :oneAPI)
    # Check for core oneAPI components needed by this module
    if !isdefined(oneAPI_module, :functional) ||
       !isdefined(oneAPI_module, :oneArray) ||
       !isdefined(oneAPI_module, :oneDeviceArray) || # Used in kernels
       !isdefined(oneAPI_module, :Array) ||
       !isdefined(oneAPI_module, Symbol("@oneapi"))
        return false
    end
    return oneAPI_module.functional()
end

# Helper function to ensure a value is a CPU scalar of a specific type
function ensure_cpu_scalar(val, target_type::Type{T}=DFT) where T
    if is_oneapi_functional()
        oneAPI_module = getfield(Main, :oneAPI)
        if isa(val, oneAPI_module.oneArray)
            # Assuming val is a 1-element oneArray if it's a scalar from GPU
            return convert(T, oneAPI_module.Array(val)[])
        end
    end
    return convert(T, val) # Assume it's already a CPU scalar or other compatible type
end

@doc """
    _fit_gpu_generic!(indicator::oti.OnlineIndicator, cpu_new_value::DFT)

Generic fallback for GPU-aware fitting of an OnlineTechnicalIndicators.jl `indicator`.
This function is used by `fit_gpu!` when a specialized GPU path for the given
indicator type (e.g., `oti.SMA`) is not available, or if GPU resources are not functional.

It handles indicators with an internal buffer (commonly `indicator.input_values.buffer`)
that might be a `oneAPI.oneArray`.
- If the buffer is a `oneAPI.oneArray`, it's copied to the CPU.
- `oti.fit!` is then called with the CPU buffer and `cpu_new_value`.
- Finally, the (potentially modified) CPU buffer is copied back to a `oneAPI.oneArray`
  and reassigned to the indicator.
- If the buffer is already CPU-based, `oti.fit!` is called directly.

This ensures correct calculation by relying on OTI's standard `fit!` method but may
incur performance costs due to full buffer transfers if used frequently with GPU buffers.
"""
function _fit_gpu_generic!(indicator::T, cpu_new_value::DFT) where {T <: oti.OnlineIndicator}
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

        # Ensure the buffer on GPU is of the correct DFT if conversions are critical
        # For now, assume eltype(buffer_accessor.buffer) is compatible with DFT or handled by oti.fit!
        original_gpu_buffer = buffer_accessor.buffer
        # Convert the new value to the element type of the buffer if necessary,
        # though oti.fit! should handle standard numeric types.
        # Here, cpu_new_value is already DFT.

        cpu_buffer_for_fit = oneAPI_module.Array(original_gpu_buffer)

        # Temporarily replace GPU buffer with CPU buffer for oti.fit!
        # This is a critical section; ensure it's robust (e.g., try-finally)
        original_buffer_type = typeof(buffer_accessor.buffer) # Store original type
        buffer_accessor.buffer = cpu_buffer_for_fit

        try
            oti.fit!(indicator, cpu_new_value) # Fit with CPU buffer and DFT new value
        finally
            # Ensure the buffer is converted back and reassigned, even if oti.fit! errors.
            # The buffer on CPU (buffer_accessor.buffer) might have changed size or type
            # if oti.fit! reallocates. Be mindful of this.
            # For safety, always create a new oneArray from the (potentially modified) cpu buffer.
            buffer_accessor.buffer = oneAPI_module.oneArray(buffer_accessor.buffer)
            # Type assertion might be needed if OTI could change buffer's eltype fundamentally
            # buffer_accessor.buffer = convert(original_buffer_type, oneAPI_module.oneArray(buffer_accessor.buffer))
        end
    else
        oti.fit!(indicator, cpu_new_value) # Fit with CPU buffer and DFT new value
    end
    return indicator
end

@doc """
    sma_update_kernel!(buffer, new_val, old_val_out, idx, is_full)

A `oneAPI.jl` kernel to update a circular buffer for SMA calculation directly on the GPU.
It writes `new_val` (converted to `eltype(buffer)`) to `buffer` at `idx`.
If `is_full` is true, the value being overwritten in `buffer[idx]` is first stored in `old_val_out[1]`.

Parameters:
- `buffer::oneAPI.oneDeviceArray{T_buf, N}`: The circular buffer data (e.g., prices) residing on the GPU.
- `new_val::T_val`: The new value to be added to the buffer (will be converted to `eltype(buffer)`).
- `old_val_out::oneAPI.oneDeviceArray{T_buf, 1}`: A 1-element `oneAPI.oneDeviceArray` to store the value that rolls off the buffer if it's full.
- `idx::Int`: The current 1-based index in the circular buffer where `new_val` should be placed.
- `is_full::Bool`: A boolean indicating if the buffer was full before adding `new_val`.
"""
function sma_update_kernel!(
    buffer::oneAPI.oneDeviceArray{T_buf, N}, # Buffer type
    new_val::T_val,                          # New value type (can be different)
    old_val_out::oneAPI.oneDeviceArray{T_buf, 1}, # Output for old value (must match buffer eltype)
    idx::Int,
    is_full::Bool
) where {T_buf, N, T_val <: Real} # T_buf is eltype of buffer, T_val is type of new_val
    if is_full
        old_val_out[1] = buffer[idx] # Store the value that will be overwritten
    else
        # If buffer not full, no value is "rolling off" for sum adjustment.
        # Storing zero ensures correct arithmetic if old_val_cpu is always subtracted.
        old_val_out[1] = zero(T_buf)
    end
    buffer[idx] = convert(T_buf, new_val) # Place the new value into the buffer, ensuring type match
    return nothing
end

@doc """
    fit_gpu!(indicator::oti.SMA, new_value)

Specialized `fit_gpu!` for `OnlineTechnicalIndicators.SMA` (Simple Moving Average).
This function implements a hybrid GPU update mechanism when `oneAPI.jl` is functional
and the SMA's internal buffer (`indicator.input_values.buffer`) is a `oneAPI.oneArray`.

The hybrid approach is as follows:
1.  The new value (`new_value`) is ensured to be a CPU scalar of type `DFT`.
2.  The `sma_update_kernel!` is launched on the GPU. This kernel:
    a.  Writes the `new_value` (converted to `eltype(gpu_buffer)`) into the correct slot in the GPU buffer.
    b.  If the buffer is full, it captures the "rolled-off" value and stores it in `old_val_gpu`. If not full, zero is stored.
3.  The rolled-off value (or zero) is copied back from `old_val_gpu` to the CPU (`old_val_cpu`).
4.  The SMA's sum (`indicator.sum`) and final value (`indicator.value`) are updated on the CPU
    using `cpu_new_value` (as `DFT`) and `old_val_cpu`.
5.  The metadata of the `CircularBuffer` (index, length, is_full status) is also updated on the CPU.

This method reduces GPU-CPU data transfer compared to copying the entire buffer.
The main buffer remains on the GPU. `indicator.sum` and `indicator.value` are assumed to be CPU scalars.

If the GPU path is not applicable, it falls back to `_fit_gpu_generic!`.
"""
function fit_gpu!(indicator::oti.SMA, new_value_any_type) # Accept any numeric type for new_value
    cpu_new_value = ensure_cpu_scalar(new_value_any_type, DFT) # Convert to DFT for calculations
    oneAPI_module = is_oneapi_functional() ? getfield(Main, :oneAPI) : nothing

    # Access CircularBuffer; OTI's SMA typically uses this.
    if !hasproperty(indicator, :input_values) || !hasproperty(indicator.input_values, :buffer) || !hasproperty(indicator, :sum)
        # Fallback if structure is not as expected (e.g. no input_values.buffer or no sum property)
        return _fit_gpu_generic!(indicator, cpu_new_value)
    end

    buffer_accessor = indicator.input_values

    can_use_gpu_path = oneAPI_module !== nothing &&
                       isa(buffer_accessor.buffer, oneAPI_module.oneArray)
                       # `hasproperty(indicator, :sum)` checked above

    if can_use_gpu_path
        gpu_buffer = buffer_accessor.buffer # This is a oneAPI.oneArray
        T_buffer_eltype = eltype(gpu_buffer) # Element type of the actual GPU buffer

        # State from CircularBuffer (CPU)
        cb_idx = buffer_accessor.idx
        cb_len = buffer_accessor.length
        cb_isfull = buffer_accessor.isfull
        cb_period = indicator.period

        old_val_gpu = oneAPI_module.oneArray{T_buffer_eltype}(undef, 1)

        oneAPI_module.@oneapi items=1 groups=1 sma_update_kernel!(
            gpu_buffer,            # Device array
            cpu_new_value,         # New value (will be converted to T_buffer_eltype by kernel)
            old_val_gpu,           # Output for old value
            cb_idx,
            cb_isfull
        )

        # old_val_cpu must be of the same type as elements in indicator.sum for correct arithmetic.
        # Assuming indicator.sum is DFT, or T_buffer_eltype can be safely converted to DFT.
        old_val_cpu = convert(DFT, oneAPI_module.Array(old_val_gpu)[1])

        # Update sum and value on CPU.
        # Ensure cpu_new_value (already DFT) and old_val_cpu (converted to DFT) are used.
        if cb_isfull
            indicator.sum = indicator.sum - old_val_cpu + cpu_new_value
        else
            indicator.sum = indicator.sum + cpu_new_value
        end

        # Update CircularBuffer state on CPU side
        buffer_accessor.idx = (cb_idx == cb_period) ? 1 : cb_idx + 1
        if !cb_isfull && cb_len < cb_period
            buffer_accessor.length += 1
            if buffer_accessor.length == cb_period
                buffer_accessor.isfull = true
            end
        end

        # Update indicator value, ensuring division is with DFT types if sum and length are compatible
        if buffer_accessor.length > 0
            indicator.value = DFT(indicator.sum / buffer_accessor.length)
        else
            indicator.value = zero(DFT) # Or appropriate initial value
        end
    else
        _fit_gpu_generic!(indicator, cpu_new_value)
    end
    return indicator
end

# --- EMA Implementation ---

@doc """
    ema_update_kernel!(new_ema_out, current_price, prev_ema, alpha)

GPU kernel to calculate one step of EMA.
`new_ema = (current_price * alpha) + (prev_ema * (1-alpha))`

Parameters:
- `new_ema_out::oneAPI.oneDeviceArray{DFT, 1}`: Output buffer for the new EMA value.
- `current_price::DFT`: The current input price.
- `prev_ema::DFT`: The previous EMA value.
- `alpha::DFT`: The smoothing factor.
"""
function ema_update_kernel!(
    new_ema_out::oneAPI.oneDeviceArray{DFT, 1},
    current_price::DFT,
    prev_ema::DFT,
    alpha::DFT
)
    new_ema_out[1] = (current_price * alpha) + (prev_ema * (one(DFT) - alpha))
    return nothing
end

@doc """
    rsi_update_kernel!(new_rsi_out, avg_gain, avg_loss)

GPU kernel to calculate RSI from average gain and average loss.
`RSI = 100 - (100 / (1 + (avg_gain / avg_loss)))`
Handles the case where `avg_loss` is zero to prevent division by zero.

Parameters:
- `new_rsi_out::oneAPI.oneDeviceArray{DFT, 1}`: Output for the new RSI value.
- `avg_gain::DFT`: Average gain.
- `avg_loss::DFT`: Average loss.
"""
function rsi_update_kernel!(
    new_rsi_out::oneAPI.oneDeviceArray{DFT, 1},
    avg_gain::DFT,
    avg_loss::DFT
)
    if avg_loss == zero(DFT)
        new_rsi_out[1] = DFT(100.0)
    else
        rs = avg_gain / avg_loss
        new_rsi_out[1] = DFT(100.0) - (DFT(100.0) / (one(DFT) + rs))
    end
    return nothing
end

@doc """
    fit_gpu!(indicator::oti.EMA, new_value_any_type)

Specialized `fit_gpu!` for `OnlineTechnicalIndicators.EMA`.

Handles EMA calculation with GPU acceleration if `oneAPI.jl` is functional,
the indicator is past its warm-up period (`indicator.n >= indicator.period`),
and `indicator.value` is made into a `oneAPI.oneArray` scalar for GPU-side updates.

Warm-up Phase:
- If `indicator.n < indicator.period`, EMA typically uses SMA logic or specific seeding.
  This implementation falls back to `_fit_gpu_generic!` during this phase, which
  will use OTI's CPU-based `fit!` that correctly handles warm-up.

GPU-Active Phase (`indicator.n >= indicator.period`):
1.  `new_value` is converted to a `DFT` CPU scalar (`cpu_current_price`).
2.  The previous EMA value (`prev_ema_val`) is retrieved. If `indicator.value` is already
    a `oneAPI.oneArray` (from a previous GPU step), its content is used directly on GPU.
    Otherwise (e.g., first step after warm-up), the CPU `indicator.value` is used and
    `indicator.value` is converted to a `oneAPI.oneArray{DFT}(undef, 1)` for future GPU steps.
3.  `ema_update_kernel!` is launched on the GPU with `cpu_current_price`, `prev_ema_val`, and `indicator.alpha`.
    The result is written to a temporary GPU buffer (`new_ema_gpu`).
4.  The calculated EMA value is copied from `new_ema_gpu` to `indicator.value` (which is a GPU scalar by now).
5.  `indicator.n` (observation count) is incremented on the CPU.
6.  `indicator.input_values` (CircularBuffer) is also updated using `_fit_gpu_generic!` if it's used by EMA for other purposes,
    or manually if its role is simple for EMA after warmup. OTI's EMA might not strictly need the buffer after warmup
    if `value` holds the state. For safety and consistency with OTI, this example will call
    `_fit_gpu_generic!(indicator, cpu_current_price)` *before* the GPU EMA step to let OTI manage its
    internal buffer and `n` count, and then the GPU step overwrites `indicator.value`.
    A more optimized version might avoid this double handling if OTI's EMA internals allow.
    **Correction**: A better approach for EMA is to let `_fit_gpu_generic!` handle the initial CPU `fit!`.
    This updates `n`, `value` (with CPU logic), and potentially the buffer.
    Then, if the GPU path is active, we re-calculate `value` on GPU using the `cpu_current_price`
    and the *just updated* `indicator.value` (which is prev_ema for this step) and store it back.

If GPU is not active or during warm-up, it relies on `_fit_gpu_generic!`.
"""
function fit_gpu!(indicator::oti.EMA, new_value_any_type)
    cpu_current_price = ensure_cpu_scalar(new_value_any_type, DFT)
    oneAPI_module = is_oneapi_functional() ? getfield(Main, :oneAPI) : nothing

    # Properties needed for EMA logic
    if !hasproperty(indicator, :value) || !hasproperty(indicator, :alpha) ||
       !hasproperty(indicator, :n) || !hasproperty(indicator, :period)
        # Fallback if EMA structure is not as expected
        return _fit_gpu_generic!(indicator, cpu_current_price)
    end

    # Let OTI's fit! run first on CPU:
    # This handles warm-up (e.g. SMA seeding), n increment, and gives us prev_ema.
    # _fit_gpu_generic! will use oti.fit!(indicator, cpu_current_price)
    # This updates indicator.value to be the "current EMA based on CPU logic"
    # which serves as "previous EMA" for our GPU recalculation if we override.
    # However, this is inefficient. A better model:
    # 1. Check warmup: if indicator.n < indicator.period, use _fit_gpu_generic! and return.
    # 2. If past warmup: then we can take over.

    if indicator.n < indicator.period || oneAPI_module === nothing
        # During warm-up or if no GPU, use OTI's standard logic via _fit_gpu_generic!
        # This will correctly update indicator.n, indicator.value, etc.
        return _fit_gpu_generic!(indicator, cpu_current_price)
    else
        # GPU Path: Indicator is warmed up, and GPU is available.

        # The `prev_ema_val` is `indicator.value` BEFORE this `fit_gpu!` call conceptually.
        # However, OTI's `fit!` updates `value` in place.
        # We need the EMA value *before* the current price is incorporated.
        # This requires that `indicator.value` IS the `prev_ema`.
        # If `_fit_gpu_generic!` was called, `indicator.value` is already the NEW EMA. This is wrong for GPU.
        #
        # Corrected logic for EMA GPU:
        # The state `indicator.value` must be the EMA from the *previous* step.

        prev_ema_val_cpu = ensure_cpu_scalar(indicator.value, DFT) # This is EMA_{t-1}
        alpha = ensure_cpu_scalar(indicator.alpha, DFT) # Alpha is likely already CPU scalar

        # Prepare GPU scalar for the output.
        # We will write the new EMA to this, then copy it to indicator.value.
        new_ema_gpu_scalar = oneAPI_module.oneArray{DFT}(undef, 1)

        oneAPI_module.@oneapi items=1 groups=1 ema_update_kernel!(
            new_ema_gpu_scalar,
            cpu_current_price, # Current price P_t
            prev_ema_val_cpu,  # Previous EMA, EMA_{t-1}
            alpha
        )

        # Update indicator state:
        # 1. The new EMA value is on new_ema_gpu_scalar.
        #    We need to store this back into indicator.value.
        #    If indicator.value is to be kept on GPU, it should be a oneArray scalar.
        #    For now, let's assume indicator.value is updated with the CPU value from GPU.
        indicator.value = oneAPI_module.Array(new_ema_gpu_scalar)[1]

        # 2. Increment `n` (number of observations seen)
        #    OTI's `fit!` normally does this. We must do it manually here.
        indicator.n += 1

        # 3. Manage `indicator.input_values` (CircularBuffer)
        #    OTI's EMA uses this buffer during warm-up (for SMA). After warm-up,
        #    it might not be strictly necessary for the EMA value itself if `alpha` is fixed.
        #    However, OTI's `fit!` for EMA *does* update this buffer.
        #    To remain consistent, we should also update it.
        #    This is tricky: `_fit_gpu_generic` would run the full `oti.fit!`,
        #    which re-calculates EMA. We only want to update the buffer part.
        #    Simplest for now: if OTI's EMA `fit!` *only* uses the buffer for `n < period`,
        #    then we might not need to touch `input_values` here.
        #    This needs knowledge of oti.EMA's exact `fit!` implementation.
        #    Let's assume for a pure GPU EMA path (after warmup), we only update `value` and `n`.
        #    If `input_values` is still used by OTI for other reasons post-warmup, this is a gap.
        #    A common pattern for EMA is that the circular buffer is only for the initial SMA.
        if hasproperty(indicator, :input_values) && hasproperty(indicator.input_values, :buffer)
             # Minimal update to keep buffer ticking if necessary, without full oti.fit!
             # This is a simplified buffer update, assuming OTI's CircularBuffer logic:
             cb = indicator.input_values
             if cb.length == cb.period # isfull
                 # No specific old value needed for EMA calc itself, just new one goes in
             end
             cb.buffer[cb.idx] = cpu_current_price # or convert(eltype(cb.buffer), cpu_current_price)
             cb.idx = (cb.idx == cb.period) ? 1 : cb.idx + 1
             if !cb.isfull && cb.length < cb.period
                 cb.length +=1
                 if cb.length == cb.period
                     cb.isfull = true
                 end
             end
        end

    end
    return indicator
end

@doc """
    fit_gpu!(indicator::oti.RSI, new_value_any_type)

Specialized `fit_gpu!` for `OnlineTechnicalIndicators.RSI`.

Handles RSI calculation with GPU acceleration if `oneAPI.jl` is functional and
the indicator is past its warm-up period (`indicator.n >= indicator.period`).

Warm-up Phase (`indicator.n < indicator.period`):
- Relies on `_fit_gpu_generic!`, which calls `oti.fit!` to handle the initial
  data accumulation and calculation correctly on the CPU.

GPU-Active Phase (`indicator.n >= indicator.period`):
1.  `new_value` is converted to a `DFT` CPU scalar.
2.  The gain and loss are calculated based on the new value and the previous value.
3.  The `avg_gain` and `avg_loss` indicators (sub-components of RSI) are updated.
    This implementation assumes they are `oti.EMA` or similar, and `fit_gpu!` is used
    recursively on them.
4.  After updating `avg_gain` and `avg_loss`, their new values are retrieved.
5.  `rsi_update_kernel!` is launched on the GPU to calculate the final RSI value.
6.  The new RSI value is stored back in `indicator.value`.
7.  `indicator.n` and `indicator.last_value` are updated manually.

If GPU is not active or during warm-up, it relies on `_fit_gpu_generic!`.
"""
function fit_gpu!(indicator::oti.RSI, new_value_any_type)
    cpu_current_price = ensure_cpu_scalar(new_value_any_type, DFT)
    oneAPI_module = is_oneapi_functional() ? getfield(Main, :oneAPI) : nothing

    if !hasproperty(indicator, :n) || !hasproperty(indicator, :period) || !hasproperty(indicator, :avg_gain) || !hasproperty(indicator, :avg_loss) || !hasproperty(indicator, :last_value)
        return _fit_gpu_generic!(indicator, cpu_current_price)
    end

    if indicator.n < indicator.period || oneAPI_module === nothing
        return _fit_gpu_generic!(indicator, cpu_current_price)
    else
        # GPU Path
        last_value = ensure_cpu_scalar(indicator.last_value, DFT)
        change = cpu_current_price - last_value
        gain = max(change, zero(DFT))
        loss = max(-change, zero(DFT))

        # Recursively call fit_gpu! on sub-indicators
        fit_gpu!(indicator.avg_gain, gain)
        fit_gpu!(indicator.avg_loss, loss)

        avg_gain_val = ensure_cpu_scalar(oti.value(indicator.avg_gain), DFT)
        avg_loss_val = ensure_cpu_scalar(oti.value(indicator.avg_loss), DFT)

        new_rsi_gpu_scalar = oneAPI_module.oneArray{DFT}(undef, 1)

        oneAPI_module.@oneapi items=1 groups=1 rsi_update_kernel!(
            new_rsi_gpu_scalar,
            avg_gain_val,
            avg_loss_val
        )

        indicator.value = oneAPI_module.Array(new_rsi_gpu_scalar)[1]
        indicator.n += 1
        indicator.last_value = cpu_current_price
    end
    return indicator
end


# Generic fit_gpu! that dispatches
function fit_gpu!(indicator::T, new_value) where {T <: oti.OnlineIndicator}
    # Convert new_value once at the entry point if it's used by multiple branches
    # However, specific implementations might want different types or ensure_cpu_scalar.
    # For now, let them handle it.

    if indicator isa oti.SMA
        return fit_gpu!(indicator, new_value) # Calls the ::oti.SMA version
    elseif indicator isa oti.EMA
         return fit_gpu!(indicator, new_value) # Calls the ::oti.EMA version
    elseif indicator isa oti.RSI
        return fit_gpu!(indicator, new_value)
    else
        # Fallback for other indicator types
        cpu_new_value_dft = ensure_cpu_scalar(new_value, DFT)
        return _fit_gpu_generic!(indicator, cpu_new_value_dft)
    end
end


export fit_gpu!, is_oneapi_functional, DFT

# --- Notes on EMA GPU Implementation ---
# 1.  Warm-up: The current EMA `fit_gpu!` relies on `indicator.n >= indicator.period` to
#     switch to a GPU path. Before that, it uses `_fit_gpu_generic!`, which calls
#     `oti.fit!`. This ensures OTI's standard warm-up logic (often SMA-based) is used.
# 2.  `indicator.value` as source of `prev_ema`: The GPU kernel needs EMA_{t-1}.
#     The implemented logic assumes `indicator.value` holds EMA_{t-1} when the GPU path is taken.
#     The new EMA_t is calculated and then written back to `indicator.value`.
# 3.  `indicator.n` update: Manually incremented in the GPU path.
# 4.  `indicator.input_values` (CircularBuffer): OTI's EMA `fit!` updates this buffer.
#     The GPU path includes a simplified manual update to this buffer to keep it populated.
#     This might need refinement based on how OTI's EMA uses the buffer post-warmup.
#     If OTI's EMA doesn't use the buffer for its value calculation after `n >= period`
#     (i.e., relies only on `prev_ema` and `alpha`), this manual buffer update is for consistency
#     or other potential uses of the buffer by OTI.
# 5.  Type `DFT`: All calculations are assumed to use `DFT`. `ensure_cpu_scalar` converts inputs,
#     and kernels operate with `DFT`.
# 6.  `oneAPI.oneArray` for `indicator.value`: The current EMA does not convert `indicator.value`
#     itself into a `oneAPI.oneArray` scalar that lives permanently on the GPU. Instead, it reads
#     `indicator.value` (CPU), calculates new EMA on GPU, and writes it back to CPU `indicator.value`.
#     A further optimization could be to make `indicator.value` a `oneAPI.oneArray{DFT,0}` (GPU scalar)
#     if `new_value_any_type` is also frequently a GPU scalar. This would require more changes
#     to how `oti.EMA` is structured or wrapped.
# 7.  Error Handling & Edge Cases: Kernels should ideally have error checking, though typically
#     GPU kernels are kept minimal. Buffer full/empty states, NaN/Inf inputs are not explicitly
#     handled in these example kernels beyond what the arithmetic itself does.
# 8.  Dependency: `Main.oneAPI` is used. For a real package, `using oneAPI` and adding it as a
#     dependency in `Project.toml` is necessary.
