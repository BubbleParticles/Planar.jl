using ..Executors: orderscount
using ..Executors: isoutof_orders
using ..Instances.Data.DFUtils: lastdate
using ..Misc.LoggingExtras
using Base: with_logger
using .st: universe, current_total, trades_count
using ..Pbar: @withpbar!, @pbupdate!, ProgressBar, addjob!, ProgressJob, pbar!, Progress, pbar
using .Progress: DescriptionColumn, CompletedColumn, SeparatorColumn, ProgressColumn, AbstractColumn
using ..Pbar.Term.Segments: Segment
using ..Pbar.Term.Measures: Measure
using ..Pbar.Term.Progress: Progress

import ..Misc: start!, stop!

# Custom column to display trades and balance
struct StatsColumn <: AbstractColumn
end

function Progress.update!(col::StatsColumn, color::String, args...)
end

@doc """Backtest a strategy `strat` using context `ctx` iterating according to the specified timeframe.

$(TYPEDSIGNATURES)

This function runs a backtest of the strategy `strat` using the provided context `ctx`.
The backtest iterates through time according to the specified timeframe, updating orders,
positions, and executing the strategy's `call!` function at each step.

# Arguments
- `strat::Strategy{Sim}`: The strategy to backtest.
- `ctx::Context`: The context containing the universe and time range.
- `trim_universe::Bool`: If true, trim the universe to ensure data alignment.
- `doreset::Bool`: If true, reset the strategy before starting.
- `resetctx::Bool`: If true, reset the context to start after warmup period.
- `show_progress::Symbol`: Progress bar mode - `:off`, `:minimal`, or `:full`.
- `fail_fast::Bool`: If true, stop on first error; if false, continue and collect errors.

"""
function start!(
    s::Strategy{Sim}, ctx::Context; trim_universe=false, doreset=true, resetctx=true, show_progress=:off, fail_fast=true
)
    # Check for empty universe early
    if isempty(s.universe)
        @warn "SimMode: empty universe, nothing to backtest"
        return s
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
        # Track errors when fail_fast=false
        error_count = Ref{Int}(0)
        error_dates = DateTime[]
        
        if show_progress !== :off
            # Create custom columns for the progress bar
            mycols = [DescriptionColumn, CompletedColumn, SeparatorColumn, ProgressColumn]
            trades = Ref{Int}()
            balance = Ref{DFT}()
            cols_kwargs = Dict()
            
            # Add stats columns if show_progress is :full
            if show_progress === :full
                push!(mycols, StatsColumn)
                cols_kwargs[:StatsColumn] = Dict(:style=>"blue bold", :trades=>trades, :balance=>balance)
            end
            
            wp = call!(s, WarmupPeriod())
            wp_steps = trunc(Int, wp / ctx.range.step)
            trimmed_start = min(ctx.range.stop, ctx.range.start + wp_steps * ctx.range.step)
            trimmed_range = trimmed_start:ctx.range.step:ctx.range.stop
            pbar!(; columns=mycols, columns_kwargs=cols_kwargs, width=140)
            balance[] = current_total(s)

            # Define update function based on show_progress mode
            update_stats = if show_progress === :full
                () -> begin
                    trades[] = trades_count(s)
                    balance[] = current_total(s)
                end
            else
                () -> nothing
            end

            @withpbar! trimmed_range desc="Backtesting" begin
                # Iterate over the trimmed_range to respect warmup trimming when showing progress
                consecutive_errors = 0
                for date in trimmed_range
                    try
                        isoutof_orders(s) && begin
                            @deassert all(iszero(ai) for ai in universe(s))
                            break
                        end
                        # Check OHLCV data exists for this date before calling strategy
                        has_data = true
                        for ai in universe(s)
                            o = ohlcv(ai)
                            # Check if date falls within the OHLCV data range
                            if date < o.timestamp[begin] || date > o.timestamp[end]
                                has_data = false
                                break
                            end
                        end
                        if !has_data
                            @debug "sim: skipping $date - no OHLCV data available"
                            consecutive_errors = 0
                            @pbupdate!
                            continue
                        end
                        update!(s, date, update_mode)
                        call!(s, date, ctx)
                        update_stats()
                        @debug "sim: iter" s.cash ltxzero(s.cash) isempty(s.holdings) orderscount(s)
                        consecutive_errors = 0
                    catch e
                        e isa InterruptException && rethrow(e)
                        @error "sim: error at $date" exception=(e, catch_backtrace())
                        error_count[] += 1
                        push!(error_dates, date)
                        consecutive_errors += 1
                        # fail_fast after 10 consecutive errors to prevent infinite error loops
                        if fail_fast || consecutive_errors >= 10
                            rethrow(e)
                        end
                    end
                    @pbupdate!
                end
            end
        else
            consecutive_errors = 0
            for date in ctx.range
                try
                    isoutof_orders(s) && begin
                            @deassert all(iszero(ai) for ai in universe(s))
                        break
                    end
                    # Check OHLCV data exists for this date before calling strategy
                    has_data = true
                    for ai in universe(s)
                        o = ohlcv(ai)
                        if date < o.timestamp[begin] || date > o.timestamp[end]
                            has_data = false
                            break
                        end
                    end
                    if !has_data
                        @debug "sim: skipping $date - no OHLCV data available"
                        consecutive_errors = 0
                        continue
                    end
                    update!(s, date, update_mode)
                    call!(s, date, ctx)
                    @debug "sim: iter" s.cash ltxzero(s.cash) isempty(s.holdings) orderscount(s)
                    consecutive_errors = 0
                catch e
                    e isa InterruptException && rethrow(e)
                    @error "sim: error at $date" exception=(e, catch_backtrace())
                    error_count[] += 1
                    push!(error_dates, date)
                    consecutive_errors += 1
                    # fail_fast after 10 consecutive errors to prevent infinite error loops
                    if fail_fast || consecutive_errors >= 10
                        rethrow(e)
                    end
                end
            end
        end
        
        # Log error summary if any errors occurred and fail_fast=false
        if !fail_fast && error_count[] > 0
            @warn "sim: backtest completed with $error_count errors on $(length(error_dates)) dates" error_dates
        end
    end
    s
end

@doc """
Backtest a strategy `strat` using context `ctx` iterating according to the specified timeframe.

$(TYPEDSIGNATURES)

This is a convenience method that creates a context from the strategy and calls the main `start!` function.

"""
start!(s::Strategy{Sim}; kwargs...) = start!(s, Context(s); kwargs...)

@doc """
Backtest a strategy for a specific number of time steps.

$(TYPEDSIGNATURES)

This function runs a backtest for `count` time steps from the start of the universe data.
If `count` is positive, it starts from the beginning. If negative, it counts backwards from the end.

"""
function start!(s::Strategy{Sim}, count::Integer; tf=s.timeframe, kwargs...)
    if isempty(s.universe)
        @warn "SimMode: empty universe, nothing to backtest"
        return s
    end
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

@doc """Backtest a strategy `strat` on a tick-by-tick basis using context `ctx`.

$(TYPEDSIGNATURES)

This function runs a backtest of the strategy `strat` iterating over every market
trade in `ctx.trades` in global chronological order. At each tick it first fills any
crossed limit orders (`UpdateOrdersTick`), then calls the strategy's `ping!`
entrypoint with the tick context and the current tick. Market orders placed inside
`ping!` fill immediately at the current tick price with no slippage; limit orders
placed inside `ping!` fill on subsequent ticks when crossed. Ticks before
`first_ts + WarmupPeriod()` are skipped.

There is no `trim_universe`/`resetctx` — tick data has no OHLCV alignment to trim and
`TradeTickRange` is immutable.

# Arguments
- `strat::Strategy{Sim}`: The strategy to backtest.
- `ctx::TickContext`: The context containing the tick range.
- `doreset::Bool`: If true, reset the strategy before starting.
- `show_progress::Symbol`: Progress bar mode - `:off`, `:minimal`, or `:full`.
- `fail_fast::Bool`: If true, stop on first error; if false, continue and collect errors.
"""
function start!(
    s::Strategy{Sim}, ctx::TickContext; doreset=true, show_progress=:off, fail_fast=true
)
    # Check for empty universe early
    if isempty(s.universe)
        @warn "SimMode: empty universe, nothing to backtest"
        return s
    end
    if doreset
        st.reset!(s)
    end
    ts = [t.timestamp for t in ctx.trades]
    if isempty(ts)
        @warn "SimMode: no ticks to backtest"
        return s
    end
    n_warmup = searchsortedfirst(ts, ts[begin] + call!(s, WarmupPeriod())) - 1
    trades = ctx.trades[n_warmup + 1:end]
    s.attrs[:sim_tick_mode] = true
    logger = if s[:sim_debug]
        current_logger()
    else
        MinLevelLogger(current_logger(), s[:log_level])
    end

    try
        with_logger(logger) do
            # Track errors when fail_fast=false
            error_count = Ref{Int}(0)
            error_dates = DateTime[]

            if show_progress !== :off
                # Create custom columns for the progress bar
                mycols = [DescriptionColumn, CompletedColumn, SeparatorColumn, ProgressColumn]
                trades_n = Ref{Int}()
                balance = Ref{DFT}()
                cols_kwargs = Dict()

                # Add stats columns if show_progress is :full
                if show_progress === :full
                    push!(mycols, StatsColumn)
                    cols_kwargs[:StatsColumn] = Dict(:style=>"blue bold", :trades=>trades_n, :balance=>balance)
                end

                pbar!(; columns=mycols, columns_kwargs=cols_kwargs, width=140)
                balance[] = current_total(s)

                # Define update function based on show_progress mode
                update_stats = if show_progress === :full
                    () -> begin
                        trades_n[] = trades_count(s)
                        balance[] = current_total(s)
                    end
                else
                    () -> nothing
                end

                @withpbar! trades desc="Backtesting" begin
                    for tick in trades
                        try
                            isoutof_orders(s) && break
                            update!(s, tick, UpdateOrdersTick())
                            s.attrs[:sim_current_tick] = tick
                            ping!(s, ctx, tick)
                            update_stats()
                            @debug "sim: tick" tick.timestamp raw(tick.asset) tick.price
                        catch e
                            e isa InterruptException && rethrow(e)
                            @error "sim: error at $(tick.timestamp)" exception=(e, catch_backtrace())
                            error_count[] += 1
                            push!(error_dates, tick.timestamp)
                            fail_fast && rethrow(e)
                        end
                        @pbupdate!
                    end
                end
            else
                for tick in trades
                    try
                        isoutof_orders(s) && break
                        update!(s, tick, UpdateOrdersTick())
                        s.attrs[:sim_current_tick] = tick
                        ping!(s, ctx, tick)
                        @debug "sim: tick" tick.timestamp raw(tick.asset) tick.price
                    catch e
                        e isa InterruptException && rethrow(e)
                        @error "sim: error at $(tick.timestamp)" exception=(e, catch_backtrace())
                        error_count[] += 1
                        push!(error_dates, tick.timestamp)
                        fail_fast && rethrow(e)
                    end
                end
            end

            # Log error summary if any errors occurred and fail_fast=false
            if !fail_fast && error_count[] > 0
                @warn "sim: backtest completed with $(error_count[]) errors on $(length(error_dates)) dates" error_dates
            end
        end
    finally
        # Never leak tick-mode flags, even on exception
        delete!(s.attrs, :sim_tick_mode)
        delete!(s.attrs, :sim_current_tick)
    end
    s
end

@doc """
Backtest a strategy on a tick-by-tick basis from a `TradeTickRange`.

$(TYPEDSIGNATURES)

Convenience method that wraps `trades` in a `TickContext` and calls the main `start!`.
"""
start!(s::Strategy{Sim}, trades::TradeTickRange; kwargs...) =
    start!(s, TickContext(Sim(), trades); kwargs...)

@doc """Returns the latest date in the given strategy's universe.

$(TYPEDSIGNATURES)

Iterates over the strategy's universe to find the date of the last data point. Returns the latest date as a `DateTime` object.

"""
_todate(s) = begin
    isempty(s.universe) && return DateTime(0)
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

This function starts the strategy simulation from a specific `from` date to a `to` date.
If `to` is not provided, it defaults to the latest date in the strategy's universe.

"""
function start!(s::Strategy{Sim}, from::DateTime, to::DateTime=_todate(s); kwargs...)
    if isempty(s.universe)
        @warn "SimMode: empty universe, nothing to backtest"
        return s
    end
    tf = s.timeframe
    ctx = Context(Sim(), tf, from, to)
    start!(s, ctx; kwargs...)
end

backtest!(s::Strategy{Sim}, args...; kwargs...) = begin
    @warn "DEPRECATED: use `start!`"
    start!(s, args...; kwargs...)
end