using ..Executors: orderscount
using ..Executors: isoutof_orders
using ..Instances.Data.DFUtils: lastdate
using ..Instances.Instruments: AbstractInstrument, parse as parse_instrument
using ..Instances: InstrumentInstance
using ..Instances.DataStructures: SortedDict
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

# ── shared machinery for OHLCV and tick backtests ─────────────────────────
# Pre-flight for both OHLCV and tick backtests: refuse empty universes and
# optionally reset the strategy. Returns `true` when the backtest may proceed.
function _sim_start!(s::Strategy{Sim}, doreset::Bool)
    if isempty(s.universe)
        @warn "SimMode: empty universe, nothing to backtest"
        return false
    end
    doreset && st.reset!(s)
    true
end

# Full log verbosity under `sim_debug`, otherwise filtered to the strategy's log level.
_sim_logger(s::Strategy{Sim}) =
    s[:sim_debug] ? current_logger() : MinLevelLogger(current_logger(), s[:log_level])

# Shared iteration machinery for both OHLCV and tick backtests: progress bar
# scaffolding, error accounting (`error_count`/`error_dates`), the out-of-orders
# early break and the `fail_fast`/consecutive-error rethrow policy.
# `step(item)` performs the per-iteration work, returning `:skip` to mark the
# item as skipped without stats/error accounting; `dateof(item)` yields the
# timestamp used in error reporting. `pbar_items` is the collection iterated
# when `show_progress !== :off` — the OHLCV loop trims the warmup range for the
# bar.
#
# Hot-loop note: `step` and `dateof` are POSITIONAL args (never kwargs) —
# Julia specializes only on positional arguments, so the concrete closure type
# lands in the method signature and `step(item)` compiles to a static call.
# The per-item body is kept INLINE in both loops (never routed through a
# capturing closure); error accounting state lives in `Ref`s, not boxed locals.
function _sim_loop!(
    s::Strategy{Sim}, items, step, dateof;
    show_progress::Symbol, fail_fast::Bool, desc::String, pbar_items=items,
)
    # Track errors when fail_fast=false
    error_count = Ref{Int}(0)
    error_dates = DateTime[]
    consecutive_errors = Ref{Int}(0)

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

        pbar!(; columns=mycols, columns_kwargs=cols_kwargs, width=140)
        balance[] = current_total(s)

        @withpbar! pbar_items desc=desc begin
            for item in pbar_items
                isoutof_orders(s) && begin
                    @deassert all(iszero(ii) for ii in universe(s))
                    break
                end
                try
                    if step(item) !== :skip
                        # Refresh the pbar stats columns after each real step
                        if show_progress === :full
                            trades[] = trades_count(s)
                            balance[] = current_total(s)
                        end
                    end
                    consecutive_errors[] = 0
                catch e
                    e isa InterruptException && rethrow(e)
                    @error "sim: error at $(dateof(item))" exception=(e, catch_backtrace())
                    error_count[] += 1
                    push!(error_dates, dateof(item))
                    consecutive_errors[] += 1
                    # fail_fast after 10 consecutive errors to prevent infinite error loops
                    if fail_fast || consecutive_errors[] >= 10
                        rethrow(e)
                    end
                end
                @pbupdate!
            end
        end
    else
        for item in items
            isoutof_orders(s) && begin
                @deassert all(iszero(ii) for ii in universe(s))
                break
            end
            try
                step(item)
                consecutive_errors[] = 0
            catch e
                e isa InterruptException && rethrow(e)
                @error "sim: error at $(dateof(item))" exception=(e, catch_backtrace())
                error_count[] += 1
                push!(error_dates, dateof(item))
                consecutive_errors[] += 1
                # fail_fast after 10 consecutive errors to prevent infinite error loops
                if fail_fast || consecutive_errors[] >= 10
                    rethrow(e)
                end
            end
        end
    end

    # Log error summary if any errors occurred and fail_fast=false
    if !fail_fast && error_count[] > 0
        @warn "sim: backtest completed with $error_count errors on $(length(error_dates)) dates" error_dates
    end
    nothing
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
- `fail_fast::Bool`: If true, stop on first error; if false, continue and collect errors (aborting after 10 consecutive errors to prevent infinite error loops).

"""
function start!(
    s::Strategy{Sim}, ctx::Context; trim_universe=false, doreset=true, resetctx=true, show_progress=:off, fail_fast=true, universe_schedule=nothing
)
    # Check for empty universe early
    _sim_start!(s, doreset) || return s
    # resolve schedule from attrs if not passed explicitly (config-driven)
    if isnothing(universe_schedule)
        universe_schedule = get(attrs(s), :universe_schedule, nothing)
        if isnothing(universe_schedule)
            try
                toml = s.config.toml
                if !isnothing(toml) && haskey(toml, "universe") && haskey(toml["universe"], "schedule")
                    raw_sched = toml["universe"]["schedule"]
                    if raw_sched isa Vector
                        parsed = Tuple{DateTime,Vector{String}}[]
                        for entry in raw_sched
                            if entry isa AbstractDict && haskey(entry, "at") && haskey(entry, "members")
                                dt = entry["at"] isa DateTime ? entry["at"] : DateTime(string(entry["at"]))
                                ms = String.(entry["members"]::Vector)
                                push!(parsed, (dt, ms))
                            end
                        end
                        universe_schedule = isempty(parsed) ? nothing : parsed
                    end
                end
            catch e
                @debug "universe_schedule toml parse failed" exception=(e, catch_backtrace())
            end
        end
    end
    # normalize schedule to sorted Vector{Tuple{DateTime,Vector{String}}}
    _schedule = if isnothing(universe_schedule) || isempty(universe_schedule)
        nothing
    else
        sort!(collect(universe_schedule); by=first)
    end
    _sched_idx = Ref(1)
    # cache for instances created for scheduled symbols (preserve OHLCV data if reused)
    _sched_cache = Dict{String,InstrumentInstance}()
    @ifdebug _resetglobals!(s)
    if trim_universe
        let data = st.coll.flatten(st.universe(s))
            !check_alignment(data) && trim!(data)
        end
    end
    if resetctx
        tt.current!(ctx.range, ctx.range.start + call!(s, WarmupPeriod()))
    end
    update_mode = s.attrs[:sim_update_mode]::ExecAction

    with_logger(_sim_logger(s)) do
        # Warmup-trimmed range, iterated by the progress bar when show_progress is on
        wp = call!(s, WarmupPeriod())
        wp_steps = trunc(Int, wp / ctx.range.step)
        trimmed_start = min(ctx.range.stop, ctx.range.start + wp_steps * ctx.range.step)
        trimmed_range = trimmed_start:ctx.range.step:ctx.range.stop

        step = function (date)
            # apply scheduled universe mutations whose time <= date (once per entry)
            if !isnothing(_schedule)
                while _sched_idx[] <= length(_schedule) && date >= _schedule[_sched_idx[]][1]
                    _, members = _schedule[_sched_idx[]]
                    _sched_idx[] += 1
                    try
                        # resolve String members to InstrumentInstances
                        new_instances = InstrumentInstance[]
                        for sym in members
                            k = string(sym)
                            # reuse existing universe instance if present
                            ii = try
                                s.universe[k].instance[1]
                            catch
                                nothing
                            end
                            if isnothing(ii)
                                try
                                    exc = st.exchange(s)
                                    a = parse_instrument(AbstractInstrument, k)
                                    ii = InstrumentInstance(a; data=SortedDict{TimeFrame, DataFrame}(), exc, margin=s.margin, sandbox=true)
                                    if !haskey(ii.data, s.timeframe)
                                        ii.data[s.timeframe] = DataFrame(timestamp=DateTime[], open=DFT[], high=DFT[], low=DFT[], close=DFT[], volume=DFT[])
                                    end
                                catch e
                                    @warn "sim schedule: failed to resolve $k" exception=(e, catch_backtrace())
                                    continue
                                end
                                _sched_cache[k] = ii
                            end
                            push!(new_instances, ii)
                        end
                        st.replace_universe!(s, new_instances)
                    catch e
                        @warn "sim schedule: replace_universe! failed" exception=(e, catch_backtrace())
                    end
                end
            end
            # Check OHLCV data exists for this date before calling strategy
            # For dynamic universes, newly added assets may have empty/short history;
            # we tolerate empty ohlcv so that warmup-skipping is delegated to strategy `iswarmed` instead of stalling the whole backtest.
            has_data = true
            for ii in st.coll.snapshot(st.universe(s))
                o = ohlcv(ii)
                if isempty(o.timestamp)
                    continue
                end
                # Check if date falls within the OHLCV data range
                if date < o.timestamp[begin] || date > o.timestamp[end]
                    has_data = false
                    break
                end
            end
            if !has_data
                @debug "sim: skipping $date - no OHLCV data available"
                return :skip
            end
            update!(s, date, update_mode)
            call!(s, date, ctx)
            @debug "sim: iter" s.cash ltxzero(s.cash) isempty(s.holdings) orderscount(s)
            nothing
        end
        # Materialize to a typed Vector{DateTime}: `DateRange` iteration is
        # type-unstable (fields are `Union{Nothing,...}`), so iterating it in the
        # hot loop would box every item as `Any`. Exclusive-stop semantics are
        # preserved (see `DateRange.iterate`).
        items = DateTime[d for d in ctx.range]
        _sim_loop!(
            s, items, step, identity;
            pbar_items=trimmed_range, show_progress, fail_fast, desc="Backtesting",
        )
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
- `fail_fast::Bool`: If true, stop on first error; if false, continue and collect errors (aborting after 10 consecutive errors to prevent infinite error loops).
"""
function start!(
    s::Strategy{Sim}, ctx::TickContext; doreset=true, show_progress=:off, fail_fast=true, universe_schedule=nothing
)
    # Check for empty universe early
    _sim_start!(s, doreset) || return s
    if isnothing(universe_schedule)
        universe_schedule = get(attrs(s), :universe_schedule, nothing)
    end
    _schedule = if isnothing(universe_schedule) || isempty(universe_schedule)
        nothing
    else
        sort!(collect(universe_schedule); by=first)
    end
    _sched_idx = Ref(1)
    _sched_cache = Dict{String,InstrumentInstance}()
    ts = [t.timestamp for t in ctx.trades]
    if isempty(ts)
        @warn "SimMode: no ticks to backtest"
        return s
    end
    n_warmup = searchsortedfirst(ts, ts[begin] + call!(s, WarmupPeriod())) - 1
    trades = ctx.trades[n_warmup + 1:end]
    s.attrs[:sim_tick_mode] = true

    try
        with_logger(_sim_logger(s)) do
            step = function (tick)
                if !isnothing(_schedule)
                    while _sched_idx[] <= length(_schedule) && tick.timestamp >= _schedule[_sched_idx[]][1]
                        _, members = _schedule[_sched_idx[]]
                        _sched_idx[] += 1
                        try
                            new_instances = InstrumentInstance[]
                            for sym in members
                                k = string(sym)
                                ii = try s.universe[k].instance[1] catch; nothing end
                                if isnothing(ii); ii = get(_sched_cache, k, nothing) end
                                if isnothing(ii)
                                    exc = st.exchange(s)
                                    a = parse_instrument(AbstractInstrument, k)
                                    ii = InstrumentInstance(a; data=SortedDict{TimeFrame, DataFrame}(), exc, margin=s.margin)
                                    if !haskey(ii.data, s.timeframe)
                                        ii.data[s.timeframe] = DataFrames.DataFrame(timestamp=DateTime[], open=DFT[], high=DFT[], low=DFT[], close=DFT[], volume=DFT[])
                                    end
                                    _sched_cache[k] = ii
                                end
                                push!(new_instances, ii)
                            end
                            st.replace_universe!(s, new_instances)
                        catch e
                            @warn "sim tick schedule: replace_universe! failed" exception=(e, catch_backtrace())
                        end
                    end
                end
                update!(s, tick, UpdateOrdersTick())
                s.attrs[:sim_current_tick] = tick
                ping!(s, ctx, tick)
                @debug "sim: tick" tick.timestamp raw(tick.asset) tick.price
                nothing
            end
            _sim_loop!(s, trades, step, t -> t.timestamp; show_progress, fail_fast, desc="Backtesting")
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
    for ii in s.universe
        this_date = lastdate(ii)
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