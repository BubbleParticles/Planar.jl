using oneAPI
using Executors: orderscount
using Executors: isoutof_orders
using .Instances.Data.DFUtils: lastdate
using .Misc.LoggingExtras
using Base: with_logger
using .st: universe, current_total, trades_count
using Pbar: @withpbar!, @pbupdate!, ProgressBar, addjob!, ProgressJob, pbar!, Progress, pbar
using .Progress: DescriptionColumn, CompletedColumn, SeparatorColumn, ProgressColumn, AbstractColumn
using Pbar.Term.Segments: Segment
using Pbar.Term.Measures: Measure
using Pbar.Term.Progress: Progress

import .Misc: start!, stop!

# Custom column to display trades and balance
struct StatsColumn <: AbstractColumn
    job::ProgressJob
    segments::Vector{Segment}
    measure::Measure
    style::String
    trades::Ref{Int}
    balance::Ref{DFT}

    function StatsColumn(job::ProgressJob; style="blue", trades=Ref{Int}(), balance=Ref{DFT}())
        txt = Segment("Trades: 0 | Balance: 0.0", style)
        return new(job, [txt], txt.measure, style, trades, balance)
    end
end

function Progress.update!(col::StatsColumn, color::String, args...)
    txt = Segment("Trades: $(col.trades[]) | Balance: $(col.balance[])", col.style)
    return txt.text
end

@doc """Backtest a strategy `strat` using context `ctx` iterating according to the specified timeframe.

$(TYPEDSIGNATURES)

On every iteration, the strategy is queried for the _current_ timestamp.
The strategy should only access data up to this point.
Example:
- Timeframe iteration: `1s`
- Strategy minimum available timeframe `1m`
Iteration gives time `1999-12-31T23:59:59` to the strategy:
The strategy (that can only lookup up to `1m` precision)
looks-up data until the timestamp `1999-12-31T23:58:00` which represents the
time until `23:59:00`.
Therefore we have to shift by one period down, the timestamp returned by `apply`:
```julia
julia> t = TimeTicks.apply(tf"1m", dt"1999-12-31T23:59:59")
1999-12-31T23:59:00 # we should not access this timestamp
julia> t - tf"1m".period
1999-12-31T23:58:00 # this is the correct candle timestamp that we can access
```
To avoid this mistake, use the function `available(::TimeFrame, ::DateTime)`, instead of apply.
"""
function start!(
    s::Strategy{Sim}, ctx::Context; trim_universe=false, doreset=true, resetctx=true, show_progress=false
)
    # ensure that universe data start at the same time
    @ifdebug _resetglobals!(s)
    if trim_universe
        let data = st.coll.flatten(st.universe(s))
            !check_alignment(data) && trim!(data)
        end
    end
    if resetctx
        tt.current!(ctx.range, ctx.range.start + call!(s, WarmupPeriod()))
    end
    if doreset
        st.reset!(s)
    end
    update_mode = s.attrs[:sim_update_mode]::ExecAction
    logger = if s[:sim_debug]
        current_logger()
    else
        MinLevelLogger(current_logger(), s[:log_level])
    end
    
    with_logger(logger) do
        if show_progress
            # Create custom columns for the progress bar
            mycols = [DescriptionColumn, CompletedColumn, SeparatorColumn, ProgressColumn, StatsColumn]
            trades = Ref{Int}()
            balance = Ref{DFT}()
            cols_kwargs = Dict(
                :StatsColumn => Dict(:style=>"blue bold", :trades=>trades, :balance=>balance)
            )
            
            wp = call!(s, WarmupPeriod())
            wp_steps = trunc(Int, wp / period(s.timeframe))
            trimmed_range = (ctx.range.start + wp_steps * ctx.range.step):ctx.range.step:ctx.range.stop
            pbar!(; columns=mycols, columns_kwargs=cols_kwargs, width=140)
            balance[] = current_total(s)
            @withpbar! trimmed_range desc="Backtesting" begin
                for date in ctx.range
                    isoutof_orders(s) && begin
                        @deassert all(iszero(ai) for ai in universe(s))
                        break
                    end
                    update!(s, date, update_mode)
                    call!(s, date, ctx)
                    # Update stats
                    trades[] = trades_count(s)
                    balance[] = current_total(s)
                    @debug "sim: iter" s.cash ltxzero(s.cash) isempty(s.holdings) orderscount(s)
                    @pbupdate!
                end
            end
        else
            for date in ctx.range
                isoutof_orders(s) && begin
                    @deassert all(iszero(ai) for ai in universe(s))
                    break
                end
                update!(s, date, update_mode)
                call!(s, date, ctx)
                @debug "sim: iter" s.cash ltxzero(s.cash) isempty(s.holdings) orderscount(s)
            end
        end
    end
    s
end

@doc """
Backtest with context of all data loaded in the strategy universe.

$(TYPEDSIGNATURES)

Backtest the strategy with the context of all data loaded in the strategy universe. This function ensures that the universe data starts at the same time. If `trim_universe` is true, it trims the data to ensure alignment. If `doreset` is true, it resets the strategy before starting the backtest. The backtest is performed using the specified `ctx` context.

"""
start!(s::Strategy{Sim}; kwargs...) = start!(s, Context(s); kwargs...)

@doc """
Starts the strategy with the given count.

$(TYPEDSIGNATURES)

Starts the strategy with the given count.
If `count` is greater than 0, it sets the start and end timestamps based on the count and the strategy's timeframe.
Otherwise, it sets the start and end timestamps based on the last timestamp in the strategy's universe.

"""
function start!(s::Strategy{Sim}, count::Integer; tf=s.timeframe, kwargs...)
    if count > 0
        from = ohlcv(first(s.universe)).timestamp[begin]
        to = from + tf.period * count
    else
        to = ohlcv(last(s.universe)).timestamp[end]
        from = to + tf.period * count
    end
    ctx = Context(Sim(), tf, from, to)
    start!(s, ctx; kwargs...)
end

@doc """Returns the latest date in the given strategy's universe.

$(TYPEDSIGNATURES)

Iterates over the strategy's universe to find the date of the last data point. Returns the latest date as a `DateTime` object.

"""
_todate(s) = begin
    to = typemin(DateTime)
    for ai in s.universe
        this_date = lastdate(ai)
        if this_date > to
            to = this_date
        end
    end
    return to
end

@doc """ Starts the strategy simulation from a specific date to another.

$(TYPEDSIGNATURES)

This function initializes a simulation context with the given timeframe and date range, then starts the strategy with this context.

"""
function start!(s::Strategy{Sim}, from::DateTime, to::DateTime=_todate(s); kwargs...)
    ctx = Context(Sim(), s.timeframe, from, to)
    start!(s, ctx; kwargs...)
end

@doc """Backtest a strategy `strat` using context `ctx` iterating according to the specified timeframe. (GPU VERSION)

$(TYPEDSIGNATURES)

On every iteration, the strategy is queried for the _current_ timestamp.
The strategy should only access data up to this point.
Example:
- Timeframe iteration: `1s`
- Strategy minimum available timeframe `1m`
Iteration gives time `1999-12-31T23:59:59` to the strategy:
The strategy (that can only lookup up to `1m` precision)
looks-up data until the timestamp `1999-12-31T23:58:00` which represents the
time until `23:59:00`.
Therefore we have to shift by one period down, the timestamp returned by `apply`:
```julia
julia> t = TimeTicks.apply(tf"1m", dt"1999-12-31T23:59:59")
1999-12-31T23:59:00 # we should not access this timestamp
julia> t - tf"1m".period
1999-12-31T23:58:00 # this is the correct candle timestamp that we can access
```
To avoid this mistake, use the function `available(::TimeFrame, ::DateTime)`, instead of apply.

This GPU-accelerated version of `start!` leverages `oneAPI.jl` to potentially speed up
backtesting by utilizing a GPU. Key aspects of GPU acceleration are applied to
internal operations where possible, such as data manipulation and indicator calculations
if the underlying data structures (e.g., `DataFrame` columns, indicator buffers) are
`oneAPI.oneArray`s.

If `oneAPI.jl` is not functional or no compatible GPU is found, this function will
automatically fall back to the CPU-based `start!` implementation, issuing a warning.

The internal `update!` and `call!` functions are critical for strategy execution.
Their GPU awareness (i.e., ability to operate efficiently on `oneAPI.oneArray`s without
implicit full data transfers) is crucial for overall GPU backtesting performance. These
are marked with `// TODO:` for further investigation.
"""
function start_gpu!(
    s::Strategy{Sim}, ctx::Context; doreset=true, resetctx=true, show_progress=false
)
    # Check for oneAPI functionality. If not available, delegate to CPU execution.
    if !isdefined(Main, :oneAPI) || !Main.oneAPI.functional()
        @warn "oneAPI.jl is not available or no functional GPU found. Falling back to CPU execution."
        return Main.start!(s, ctx; doreset, resetctx, show_progress) # Ensure Main.start! is the CPU version
    end

    # Ensure that universe data start at the same time
    @ifdebug _resetglobals!(s)
    if trim_universe
        let data = st.coll.flatten(st.universe(s))
            !check_alignment(data) && trim!(data)
        end
    end
    if resetctx
        tt.current!(ctx.range, ctx.range.start + call!(s, WarmupPeriod()))
    end
    if doreset
        st.reset!(s)
    end
    update_mode = s.attrs[:sim_update_mode]::ExecAction
    logger = if s[:sim_debug]
        current_logger()
    else
        MinLevelLogger(current_logger(), s[:log_level])
    end

    with_logger(logger) do
        if show_progress
            # Create custom columns for the progress bar
            mycols = [DescriptionColumn, CompletedColumn, SeparatorColumn, ProgressColumn, StatsColumn]
            trades = Ref{Int}()
            balance = Ref{DFT}()
            cols_kwargs = Dict(
                :StatsColumn => Dict(:style=>"blue bold", :trades=>trades, :balance=>balance)
            )

            wp = call!(s, WarmupPeriod())
            wp_steps = trunc(Int, wp / period(s.timeframe))
            trimmed_range = (ctx.range.start + wp_steps * ctx.range.step):ctx.range.step:ctx.range.stop
            pbar!(; columns=mycols, columns_kwargs=cols_kwargs, width=140)
            balance[] = current_total(s) # Initial balance, assume current_total is okay or handles GPU
            @withpbar! trimmed_range desc="Backtesting (GPU)" begin
                for date_val in ctx.range # Renamed date to date_val
                    isoutof_orders(s) && begin
                        # Assuming iszero and universe(s) can handle potential oneArray data within ai
                        @deassert all(iszero(ai) for ai in universe(s))
                        break
                    end
                    # // TODO: CRITICAL: Ensure `update!` and `call!` are GPU-aware.
                    # These functions are the core of the simulation loop.
                    # If `s` (strategy object), its internal buffers (e.g., indicators),
                    # or `ctx` (context) contain fields that are `oneAPI.oneArray`,
                    # `update!` and `call!` *must* be implemented to handle them
                    # efficiently on the GPU (e.g., using custom kernels, GPU-compatible
                    # array operations via oneAPI.jl, or other GPU libraries).
                    # Failure to do so will lead to significant performance degradation due to
                    # implicit data transfers between CPU and GPU on each iteration.
                    update_gpu!(s, date_val, update_mode) # Must be GPU-aware if s or its data are on GPU
                    call_gpu!(s, date_val, ctx)          # Must be GPU-aware if s or its data are on GPU

                    # Update stats for progress bar - these need to be CPU values
                    trades_val = trades_count(s) # trades_count might return oneArray scalar
                    balance_val = current_total(s) # current_total might return oneArray scalar

                    trades[] = isa(trades_val, oneAPI.oneArray) ? Array(trades_val)[] : trades_val
                    balance[] = isa(balance_val, oneAPI.oneArray) ? Array(balance_val)[] : balance_val

                    @debug "sim: iter" s.cash ltxzero(s.cash) isempty(s.holdings) orderscount(s)
                    @pbupdate!
                end
            end
        else
            for date_val in ctx.range # Renamed date to date_val
                isoutof_orders(s) && begin
                    @deassert all(iszero(ai) for ai in universe(s))
                        break
                    end
                    # // TODO: CRITICAL: Ensure `update!` and `call!` are GPU-aware.
                    # See detailed comment in the show_progress=true block above.
                    # These functions must be GPU-aware to prevent performance bottlenecks
                    # when operating with oneAPI.oneArray data within the strategy `s`.
                update_gpu!(s, date_val, update_mode) # Must be GPU-aware
                call_gpu!(s, date_val, ctx)          # Must be GPU-aware
                @debug "sim: iter" s.cash ltxzero(s.cash) isempty(s.holdings) orderscount(s)
            end
        end
    end
    s
end

@doc """
Backtest with context of all data loaded in the strategy universe. (GPU VERSION)

$(TYPEDSIGNATURES)

Backtest the strategy with the context of all data loaded in the strategy universe. This function ensures that the universe data starts at the same time. If `trim_universe` is true, it trims the data to ensure alignment. If `doreset` is true, it resets the strategy before starting the backtest. The backtest is performed using the specified `ctx` context.

"""
start_gpu!(s::Strategy{Sim}; kwargs...) = start_gpu!(s, Context(s); kwargs...)

@doc """
Starts the strategy with the given count. (GPU VERSION)

$(TYPEDSIGNATURES)

Starts the strategy with the given count.
If `count` is greater than 0, it sets the start and end timestamps based on the count and the strategy's timeframe.
Otherwise, it sets the start and end timestamps based on the last timestamp in the strategy's universe.

"""
function start_gpu!(s::Strategy{Sim}, count::Integer; tf=s.timeframe, kwargs...)
    """
    Helper function to retrieve a single timestamp (first or last) from an asset instance's OHLCV data.
    This function is GPU-aware: if the timestamp array is a `oneAPI.oneArray`, it efficiently copies
    only the required single element to the CPU, minimizing GPU-CPU data transfer.
    Otherwise, it performs a standard array access.

    Args:
    - `asset_instance_data`: The asset instance containing OHLCV data.
    - `index_type`: Symbol, either `:first` to get the earliest timestamp or `:last` for the latest.

    Returns:
    - A `DateTime` scalar.
    """
    get_timestamp_scalar = (asset_instance_data, index_type::Symbol) -> begin
        ts_array = ohlcv(asset_instance_data).timestamp # This is expected to be AbstractVector{DateTime}

        val = if isa(ts_array, oneAPI.oneArray)
            # GPU Path: Efficiently copy only one element
            len = length(ts_array)
            if len == 0 # Should not happen in practice with valid OHLCV data
                error("Timestamp array is empty")
            end
            # Create a host array (CPU) of size 1 to copy the single element
            host_array = oneAPI.HostArray{eltype(ts_array)}(undef, 1)
            idx_to_copy = index_type == :first ? 1 : len
            # Copy single element from device (GPU) to host (CPU)
            # copyto!(dest, dest_offset, src, src_offset, count)
            oneAPI.copyto!(host_array, 1, ts_array, idx_to_copy, 1)
            host_array[1] # Access the single copied element
        else
            # Standard CPU array access
            index_type == :first ? ts_array[begin] : ts_array[end]
        end
        return val
    end

    if count > 0
        from = get_timestamp_scalar(first(s.universe), :first)
        to = from + tf.period * count # tf.period and count are CPU scalars
    else
        to = get_timestamp_scalar(last(s.universe), :last)
        from = to + tf.period * count
    end
    ctx = Context(Sim(), tf, from, to)
    start_gpu!(s, ctx; kwargs...) # Delegates to the main start_gpu! which has the GPU check
end

@doc """ Starts the strategy simulation from a specific date to another. (GPU VERSION)

$(TYPEDSIGNATURES)

This function initializes a simulation context with the given timeframe and date range, then starts the strategy with this context.

"""
function start_gpu!(s::Strategy{Sim}, from::DateTime, to::DateTime=_todate_gpu_aware(s); kwargs...)
    ctx = Context(Sim(), s.timeframe, from, to)
    start_gpu!(s, ctx; kwargs...) # Delegates to the main start_gpu! which has the GPU check
end

"""
Calculates the latest timestamp present across all asset instances in the strategy's universe.
This function is GPU-aware. If `lastdate(ai)` (where `ai` is an asset instance)
returns a `oneAPI.oneArray` containing a single `DateTime` element, this function
efficiently retrieves that element to the CPU. Otherwise, it assumes `lastdate(ai)`
returns a standard `DateTime` object.

Args:
- `s`: The strategy object, containing the universe of asset instances.

Returns:
- The latest `DateTime` found across all asset instances.
"""
function _todate_gpu_aware(s::Strategy{Sim}) # Added type for s for clarity
    to_datetime = typemin(DateTime)
    for ai in s.universe # s.universe might hold AssetInstances with oneArray fields
        this_asset_last_date = lastdate(ai) # Expected to return DateTime or oneArray{DateTime,0} or oneArray{DateTime,1} of length 1

        current_scalar_date = if isa(this_asset_last_date, oneAPI.oneArray)
            # If lastdate returns a oneArray containing a single DateTime.
            # oneAPI.Array(oneArray_scalar)[] is a common pattern to get the scalar value.
            # Ensure it's a scalar or 1-element array before indexing [].
            if length(this_asset_last_date) == 1
                oneAPI.Array(this_asset_last_date)[1] # Use [1] for 1-element array
            elseif ndims(this_asset_last_date) == 0 # 0-dimensional array (scalar)
                oneAPI.Array(this_asset_last_date)[]
            else
                error("Unsupported oneArray format from lastdate(ai): expected scalar or 1-element array.")
            end
        else
            # If lastdate returns a normal DateTime
            this_asset_last_date
        end

        if current_scalar_date > to_datetime
            to_datetime = current_scalar_date
        end
    end
    return to_datetime
end

stop!(::Strategy{Sim}) = nothing

backtest!(s::Strategy{Sim}, args...; kwargs...) = begin
    @warn "DEPRECATED: use `start!`"
    start!(s, args...; kwargs...)
end

