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
"""
function start_gpu!(
    s::Strategy{Sim}, ctx::Context; trim_universe=false, doreset=true, resetctx=true, show_progress=false
)
    if !isdefined(Main, :oneAPI) || !Main.oneAPI.functional()
        @warn "oneAPI.jl is not available or no functional GPU found. Falling back to CPU execution."
        # Delegate to the CPU version of start!
        return Main.start!(s, ctx; trim_universe, doreset, resetctx, show_progress)
    end

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
            balance[] = current_total(s) # Initial balance, assume current_total is okay or handles GPU
            @withpbar! trimmed_range desc="Backtesting (GPU)" begin
                for date_val in ctx.range # Renamed date to date_val
                    isoutof_orders(s) && begin
                        # Assuming iszero and universe(s) can handle potential oneArray data within ai
                        @deassert all(iszero(ai) for ai in universe(s))
                        break
                    end
                    update!(s, date_val, update_mode) # Must be GPU-aware if s contains oneArrays
                    call!(s, date_val, ctx)          # Must be GPU-aware if s contains oneArrays

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
                update!(s, date_val, update_mode) # Must be GPU-aware
                call!(s, date_val, ctx)          # Must be GPU-aware
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
    # Helper for getting scalar timestamp values, aware of potential oneArrays
    get_timestamp_scalar = (asset_instance_data, index_type) -> begin
        # Assume ohlcv() is defined elsewhere and handles asset_instance_data
        # and returns an object with a .timestamp field (which could be a oneArray).
        ts_array = ohlcv(asset_instance_data).timestamp
        val = if isa(ts_array, oneAPI.oneArray)
            # Copy the whole array to CPU then index.
            # This is simpler than trying to copy a single element from GPU directly
            # unless oneAPI provides a very easy way for single element access.
            cpu_ts_array = Array(ts_array)
            index_type == :first ? cpu_ts_array[begin] : cpu_ts_array[end]
        else
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

# Renamed from _todate to make it specific for GPU context if needed,
# or it can be the general version if _todate is removed/replaced.
function _todate_gpu_aware(s)
    to_datetime = typemin(DateTime)
    for ai in s.universe # s.universe might hold AssetInstances with oneArray fields
        # lastdate(ai) should return a DateTime object.
        # If lastdate itself needs to access a oneArray (e.g., timestamps of ai),
        # it must handle the copy to CPU internally to produce the DateTime.
        # Or, if lastdate returns a 1-element oneArray(DateTime), we handle it here.
        this_asset_last_date = lastdate(ai)

        current_scalar_date = if isa(this_asset_last_date, oneAPI.oneArray)
            # If lastdate returns a oneArray containing a single DateTime
            Array(this_asset_last_date)[]
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

