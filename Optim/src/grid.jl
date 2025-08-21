using Pbar.Term.Progress: @track, ProgressJob, Progress
using Pbar: pbar!, @withpbar!, @pbupdate!, pbar, dorender
using SimMode.Instruments: compactnum as cnum, Instruments
using SimMode.Lang.Logging: SimpleLogger, with_logger, current_logger
using SimMode.Lang: splitkws
using Metrics.Data: Cache as ca, nrow, groupby, combine, DataFrame, DATA_PATH
using SimMode.Misc: attr
using Random: shuffle!
using SimMode: Context, Sim

using Printf: @sprintf
using Base.Sys: free_memory
import .Progress: AbstractColumn, get_columns
import Pbar.Term.Segments: Segment
import Pbar.Term.Measures: Measure

function _tostring(_, s::String)
    s[begin:min(displaysize()[2], length(s))]
end

@doc """ Converts the provided parameters into a string representation.

$(TYPEDSIGNATURES)

The function takes a prefix and a set of parameters as input.
It joins the prefix and the parameters into a single string, with each parameter converted to a compact number representation.
The resulting string is then truncated to fit the display size.
"""
function _tostring(prefix, params)
    s = join(("[", prefix, (cnum(p) for p in params)..., "]"), " ")
    s[begin:min(displaysize()[2], length(s))]
end

@doc """ A column in the progress bar representing parameters.

$(FIELDS)

This struct represents a column in the progress bar that displays the parameters of the optimization job.
It contains a `ProgressJob`, a vector of `Segment` objects, a `Measure` object, and a reference to the parameters.
The constructor creates a `Segment` with a string representation of the parameters and sets the width of the measure to 15.
"""
struct ParamsColumn <: AbstractColumn
    job::ProgressJob
    segments::Vector{Segment}
    measure::Measure
    params::Ref

    function ParamsColumn(job::ProgressJob; params)
        txt = Segment(_tostring("params: ", params[]), "cyan")
        txt.measure.w = 15
        return new(job, [txt], txt.measure, params)
    end
end

function Progress.update!(col::ParamsColumn, args...)::String
    seg = Segment(_tostring("params: ", col.params[]), "cyan")
    return seg.text
end

@doc """ A column in the progress bar representing the best optimization result.

$(FIELDS)

This struct represents a column in the progress bar that displays the best result of the optimization job.
It contains a `ProgressJob`, a vector of `Segment` objects, a `Measure` object, and a reference to the best result.
The constructor creates a `Segment` with a string representation of the best result and sets the width of the measure to 15.
"""
struct BestColumn <: AbstractColumn
    job::ProgressJob
    segments::Vector{Segment}
    measure::Measure
    best::Ref

    function BestColumn(job::ProgressJob; best)
        s = _tostring("best: ", best[])
        txt = Segment(s, "green")
        txt.measure.w = 15
        return new(job, [txt], txt.measure, best)
    end
end

function Progress.update!(col::BestColumn, args...)::String
    seg = Segment(_tostring("best: ", col.best[]), "green")
    return seg.text
end

@doc """ A column in the progress bar representing the estimated time remaining.

$(FIELDS)

This struct represents a column in the progress bar that displays the estimated time remaining for the optimization job.
It contains a `ProgressJob`, a vector of `Segment` objects, a `Measure` object, and references to track progress timing.
The constructor creates a `Segment` with a string representation of the ETA and sets the width of the measure to 15.
"""
struct ETAColumn <: AbstractColumn
    job::ProgressJob
    segments::Vector{Segment}
    measure::Measure
    start_time::Ref{DateTime}
    last_update::Ref{DateTime}
    completed::Ref{Int}
    total::Ref{Int}

    function ETAColumn(
        job::ProgressJob;
        start_time=Ref(now()),
        last_update=Ref(now()),
        completed=Ref(0),
        total=Ref(0),
    )
        txt = Segment("ETA: --", "yellow")
        txt.measure.w = 15
        return new(job, [txt], txt.measure, start_time, last_update, completed, total)
    end
end

function Progress.update!(col::ETAColumn, args...)::String
    if col.completed[] > 0 && col.total[] > 0
        elapsed = now() - col.start_time[]
        if col.completed[] < col.total[]
            # Calculate average time per item
            avg_time_per_item = elapsed ÷ col.completed[]
            # Calculate remaining items
            remaining_items = col.total[] - col.completed[]
            # Calculate estimated time remaining
            eta_seconds = avg_time_per_item.value * remaining_items / 1000.0  # Convert from milliseconds to seconds

            if eta_seconds > 0
                if eta_seconds >= 86400  # 24 hours
                    days = trunc(Int, eta_seconds ÷ 86400)
                    eta_str = @sprintf("ETA: %dd", days)
                elseif eta_seconds >= 3600  # 1 hour
                    hours = trunc(Int, eta_seconds ÷ 3600)
                    eta_str = @sprintf("ETA: %dh", hours)
                elseif eta_seconds >= 60  # 1 minute
                    minutes = trunc(Int, eta_seconds ÷ 60)
                    eta_str = @sprintf("ETA: %dm", minutes)
                else
                    eta_str = @sprintf("ETA: %ds", trunc(Int, eta_seconds))
                end
            else
                eta_str = "ETA: --"
            end
        else
            eta_str = "ETA: 0s"
        end
    else
        eta_str = "ETA: --"
    end

    seg = Segment(eta_str, "yellow")
    return seg.text
end

@doc """ Initializes a progress bar for grid optimization.

$(TYPEDSIGNATURES)

This function sets up a progress bar for the grid optimization process.
It creates a `ParamsColumn`, a `BestColumn`, and an `ETAColumn` and adds them to the default columns.
The function returns a tuple of (current_params, eta_refs) where eta_refs contains the ETA column references.
"""
function gridpbar!(sess, first_params)
    columns = get_columns(:default)
    push!(columns, ParamsColumn)
    push!(columns, BestColumn)
    push!(columns, ETAColumn)
    current_params = Ref(first_params)

    # Create ETA references that will be shared
    eta_start_time = Ref(now())
    eta_completed = Ref(0)
    eta_total = Ref(0)

    pbar!(;
        columns,
        columns_kwargs=Dict(
            :ParamsColumn => Dict(:params => current_params),
            :BestColumn => Dict(:best => sess.best),
            :ETAColumn => Dict(
                :start_time => eta_start_time,
                :last_update => Ref(now()),
                :completed => eta_completed,
                :total => eta_total,
            ),
        ),
    )
    (current_params, (eta_start_time, eta_completed, eta_total))
end

@doc """ Generates a grid from the provided parameters.

$(TYPEDSIGNATURES)

The function takes a set of parameters as input.
It generates a grid by taking the product of the parameters and reshaping it to the length of the parameters.
"""
function gridfromparams(params)
    mat = Iterators.product(params...) |> collect
    reshape(mat, length(mat))
end

@doc """ Generates a grid from the optimization results.

$(TYPEDSIGNATURES)

The function takes an optimization session and results as input.
It generates a grid by extracting the parameters from each row of the results.
"""
function gridfromresults(sess::OptSession, results; kwargs...)
    params = keys(sess.params)
    [((getproperty(row, p) for p in params)...,) for row in eachrow(results)]
end

@doc """ Resumes the optimization session from saved state.

$(TYPEDSIGNATURES)

The function attempts to load a saved session and resumes it.
If the saved session does not match the current session in terms of strategy, context, parameters, or attributes, an error is thrown.
If the session is successfully resumed, the results from the saved session are appended to the current session's results.
"""
function resume!(sess; zi=get_zinstance(sess))
    saved_sess = try
        load_session(sess; zi)
    catch e
        e isa KeyError && return false
        rethrow(e)
    end
    what = if nameof(saved_sess.s) != nameof(sess.s)
        "strategy"
    elseif let r1 = saved_sess.ctx.range, r2 = sess.ctx.range
        !(r1.start == r2.start && r1.stop == r2.stop)
    end
        "context"
    elseif saved_sess.params != sess.params
        "params"
    elseif saved_sess.attrs != sess.attrs
        "attrs"
    else
        ""
    end
    if what != ""
        error("Can't resume session, mismatching $what")
    end
    append!(sess.results, saved_sess.results)
    return true
end

@doc "Remove results that don't have all the `repeat`ed evalutaion."
function remove_incomplete!(sess::OptSession)
    gd = groupby(sess.results, [keys(sess.params)...])
    splits = attr(sess, :splits)
    completed = DataFrame(filter(g -> nrow(g) == splits, gd))
    empty!(sess.results)
    append!(sess.results, completed)
end

@doc """ Removes results that don't have all the `repeat`ed evaluation.

$(TYPEDSIGNATURES)

The function groups the results by session parameters and removes those groups that don't have a complete set of evaluations, as defined by the `splits` attribute of the session.
"""
function optsession(s::Strategy; seed=1, splits=1, offset=0)
    ctx, params, grid = call!(s, OptSetup())
    OptSession(s; ctx, params, offset, attrs=Dict(pairs((; seed, splits))))
end

@doc """Backtests the strategy across combination of parameters.

$(TYPEDSIGNATURES)

- `seed`: random seed set before each backtest run.
- `splits`: the number segments into which the context is split.
- `save_freq`: how frequently (`Period`) to save results, when `nothing` (default) saving is skipped.
- `logging`: enabled logging
- `random_search`: shuffle parameters combinations before iterations

One parameter combination runs `splits` times, where each run uses a period
that is a segment of the full period of the given `Context` given.
(The `Context` comes from the strategy `call!(s, params, OptRun())`
"""
function gridsearch(
    s::Strategy{Sim};
    seed=1,
    splits=1,
    save_freq=nothing,
    resume=true,
    logging=true,
    random_search=false,
    zi=get_zinstance(s),
    grid_itr=nothing,
    offset=0,
    ctx=nothing,
)
    running!()
    sess = optsession(s; seed, splits, offset)
    if !isnothing(ctx)
        sess.ctx = ctx
    end
    ctx = sess.ctx
    sess.attrs[:splits] = splits
    grid = gridfromparams(sess.params)
    resume && resume!(sess)
    from = Ref(0)
    should_save = if !isnothing(save_freq)
        resume || save_session(sess; zi)
        true
    else
        false
    end
    logger = if logging
        io = open(log_path(s)[1], "w+")
        # SimpleLogger(io)
        current_logger()
    else
        io = NullLogger()
        IOBuffer()
    end
    try
        backtest_func = define_backtest_func(
            sess, ctxsteps(ctx, splits, call!(s, WarmupPeriod()))...
        )
        obj_type, n_obj = objectives(s)
        sess.best[] = if isone(n_obj)
            zero(eltype(obj_type))
        else
            ((zero(eltype(obj_type)) for _ in 1:n_obj)...,)
        end
        ismulti = n_obj > 1
        opt_func = define_opt_func(
            s; backtest_func, ismulti, splits, obj_type, isthreaded=false
        )
        current_params, (eta_start_time, eta_completed, eta_total) = gridpbar!(
            sess, first(grid)
        )
        best = sess.best

        if isnothing(grid_itr)
            grid_itr = if isempty(sess.results)
                collect(grid)
            else
                remove_incomplete!(sess)
                done_params = Set(
                    values(result_params(sess, idx)) for idx in 1:nrow(sess.results)
                )
                filter(params -> params ∉ done_params, grid)
            end
        else
            grid_itr = collect(grid_itr)
            grid = grid_itr
        end
        if random_search
            shuffle!(grid_itr)
        end

        # Set total for ETA calculation (each parameter combination runs 'splits' times)
        eta_total[] = length(grid_itr) * splits
        eta_completed[] = 0

        from[] = nrow(sess.results) + 1
        saved_last = Ref(now())
        grid_lock = ReentrantLock()
        with_logger(logger) do
            @withpbar! grid begin
                if !isempty(sess.results)
                    completed_combinations = sum(divrem(nrow(sess.results), splits))
                    @pbupdate! completed_combinations
                    eta_completed[] = completed_combinations * splits
                    # Force ETA column update by triggering a render
                    if !isnothing(pbar[]) && pbar[].running
                        dorender(pbar[])
                    end
                end
                function runner(cell)
                    @lock grid_lock Random.seed!(seed)
                    obj = opt_func(cell)
                    @lock grid_lock begin
                        current_params[] = cell
                        eta_completed[] += splits
                        @pbupdate!
                        if obj > best[]
                            best[] = obj
                        end
                    end
                    should_save && @lock sess.lock begin
                        if now() - saved_last[] > save_freq
                            save_session(sess; from=from[], zi)
                            from[] = nrow(sess.results) + 1
                            saved_last[] = now()
                        end
                    end
                end
                Threads.@threads for cell in grid_itr
                    if isrunning()
                        try
                            runner(cell)
                        catch
                            @error "" exception = (first(Base.catch_stack())...,)
                            stopcall!()
                            logging && @lock grid_lock @debug_backtrace
                        end
                    end
                end
                save_session(sess; from=from[], zi)
            end
        end
    catch e
        logging && @error e
        save_session(sess; from=from[], zi)
        if !(e isa InterruptException)
            rethrow(e)
        end
    finally
        stopcall!()
        if logging
            flush(io)
            close(io)
        end
    end
    sess
end

@doc """ Filters the optimization results based on certain criteria.

$(TYPEDSIGNATURES)

The function takes a strategy and a session as input, along with optional parameters for cut and minimum results.
It filters the results based on the cut value and the minimum number of results.
"""
function filter_results(::Strategy, sess; cut=0.8, min_results=100)
    df = agg(sess)
    if nrow(df) > 1
        initial_cash = sess.s.initial_cash
        filter!([:cash] => (x) -> x > initial_cash, df)
        if nrow(df) > min_results
            sort!(df, [:cash, :obj, :trades])
            from_idx = trunc(Int, nrow(df) * (cut / 3))
            best_cash = @view df[(end - from_idx):end, :]
            sort!(df, [:trades, :obj, :cash])
            best_trades = @view df[(end - from_idx):end, :]
            sort!(df, [:obj, :cash, :trades])
            best_obj = @view df[(end - from_idx):end, :]
            vcat(best_cash, best_trades, best_obj)
        else
            df
        end
    else
        return df
    end
end

@doc "A progressive search performs multiple grid searches with only 1 repetition per parameters combination.

$(TYPEDSIGNATURES)

After each search is completed, the results are filtered according to custom rules. The parameters from the results
that match the filtering will be backtested again with a different `offset` which modifies the backtesting period.
`rounds`: how many iterations (of grid searches) to perform
`sess`: If a `Ref{<:OptSession>` is provided, search will resume from the session previous results

Additional kwargs are forwarded to the grid search.
"
function progsearch(
    s; sess::Option{Ref{<:OptSession}}=nothing, rounds=:auto, cut=1.0, kwargs...
)
    rcount = rounds == :auto ? round(Int, period(s.timeframe) / Minute(1)) : rounds
    @assert rcount isa Integer
    _, fw_kwargs = splitkws(:offset, :splits, :grid_itr; kwargs)
    init_offset = isnothing(sess) ? 0 : sess[].attrs[:offset] + 1
    let offset = init_offset,
        grid_itr = if isnothing(sess)
            nothing
        else
            gridfromresults(sess[], filter_results(s, sess[]; cut))
        end

        this_sess = gridsearch(s; offset, grid_itr, splits=1, fw_kwargs...)
        if isnothing(sess)
            sess = Ref(this_sess)
        else
            sess[] = this_sess
        end
    end
    for offset in (init_offset + 1):rcount
        results = filter_results(s, sess[]; cut)
        grid_itr = gridfromresults(sess[], results)
        if length(grid_itr) < 3
            @info "Search stopped because no results were left to filter."
            break
        end
        sess[] = gridsearch(s; offset, splits=1, grid_itr, fw_kwargs...)
    end
    sess[]
end

@doc """Performs a broad search optimization that progressively moves through the context range.

$(TYPEDSIGNATURES)

- `slice_size`: Size of each slice in terms of strategy timeframe periods. If a float between 0 and 1, it is interpreted as a fraction of the total steps (default: 0.2, i.e., 1/5 of the total steps)
- `sort_by`: Column to sort results by (:pnl or :obj, default: :pnl)

The search starts with the first slice of the context and at each iteration:
1. Moves to the next contiguous slice
2. Filters parameters based on filter_func
3. Continues until reaching the end of the context
"""
function broadsearch(
    s::Strategy;
    slice_size=0.2,  # Default to 1/5 of total_steps
    sort_by=:pnl,
    kwargs...,
)
    # Initial setup
    _, fw_kwargs = splitkws(:offset, :splits, :grid_itr; kwargs)

    # Get context and calculate total steps
    ctx, params, _ = call!(s, OptSetup())
    ctx_step = ctx.range.step
    total_steps = trunc(Int, (ctx.range.stop - ctx.range.start) / ctx_step)
    current_step = 0

    # Always interpret the default (0.2) as a fraction, but if the user passes >=1, use as absolute
    actual_slice_size = if ((isa(slice_size, Number) && 0 < slice_size < 1))
        max(1, trunc(Int, total_steps * slice_size))
    else
        slice_size
    end

    local sess = Ref{OptSession}()
    local results::DataFrame = DataFrame()

    # Create initial slice context
    slice_start = ctx.range.start
    slice_stop = min(slice_start + actual_slice_size * ctx_step, ctx.range.stop)
    slice_ctx = Context(Sim(), DateRange(slice_start, slice_stop, ctx_step))

    # Initialize session with first slice

    # Run initial grid search with all parameters
    sess[] = gridsearch(s; ctx=slice_ctx, splits=1, fw_kwargs...)
    # Get current results and apply filtering
    results = filter_results(s, sess[])

    # Move to next slice
    current_step += actual_slice_size

    try
        while current_step < total_steps
            # Calculate slice range
            slice_start = ctx.range.start + current_step * ctx_step
            slice_stop = min(slice_start + actual_slice_size * ctx_step, ctx.range.stop)

            # Create a new strategy with the slice context
            slice_s = similar(s; mode=Sim())
            slice_ctx = Context(Sim(), DateRange(slice_start, slice_stop, ctx_step))

            if isempty(results)
                @info "No valid parameter combinations found for current slice, stopping search"
                break
            end

            # Sort results by specified column
            sort!(results, [sort_by]; rev=true)

            # Create new grid from filtered results
            grid_itr = gridfromresults(sess[], results)

            # Perform next grid search with current slice
            try
                # Create new session with current slice
                new_sess = optsession(slice_s; splits=1)
                # Run grid search with filtered parameters on current slice
                sess[] = gridsearch(
                    slice_s; ctx=slice_ctx, splits=1, grid_itr, fw_kwargs...
                )

                # Get current results and apply filtering
                results = filter_results(s, sess[])
            catch e
                @error "Error during grid search" exception = (e, catch_backtrace())
                break
            end

            # Move to next slice
            current_step += actual_slice_size
        end
    catch e
        @error "Error during broad search" exception = (e, catch_backtrace())
        rethrow(e)
    end

    sess[]
end

@doc "Backtests by sliding over the backtesting period, by the smallest timeframe (the strategy timeframe).

$(TYPEDSIGNATURES)

Until a full range of timeframes is reached between the strategy timeframe and backtesting context timeframe.

- `multiplier`: the steps count (total stepps will be `multiplier * context_timeframe / s.timeframe` )
"
function slidetest(
    s::Strategy; n_jobs=Threads.nthreads(), step_ratio=1 / n_jobs, params=nothing
)
    ctx, _, _ = call!(s, OptSetup())
    inc = ctx.range.step
    @assert 0 < step_ratio < 1 "step_ratio must be between 0 and 1"
    split_len = round(Int, length(ctx.range) * step_ratio)
    n_iters = length(ctx.range) ÷ split_len
    wp = call!(s, WarmupPeriod())
    results = DataFrame()
    initial_cash = s.initial_cash
    rlock = ReentrantLock()
    s_clones = tuple(((ReentrantLock(), similar(s)) for _ in 1:n_jobs)...)
    ctx_mode = typeof(ctx).parameters[1]()
    if !isnothing(params)
        for (l, s_c) in s_clones
            attrs = s_c.attrs
            for (k, p) in pairs(params)
                attrs[k] = p
            end
            call!(s_c, params, OptRun())
        end
    end

    @withpbar! 1:n_iters begin
        Threads.@threads for n in 1:n_iters
            let id = Threads.threadid(), (l, s) = s_clones[id]
                lock(l) do
                    st.reset!(s, true)
                    range_start = ctx.range.start + wp + (n - 1) * split_len * inc
                    range_stop = range_start + split_len * inc
                    this_range = DateRange(range_start, range_stop, inc)
                    this_ctx = Context(ctx_mode, this_range)
                    start!(s, this_ctx; doreset=false)
                end
                lock(rlock) do
                    push!(results, (; step=n, metrics_func(s; initial_cash)...))
                    @pbupdate!
                end
            end
        end
    end
    results
end

function slidetest(s::Strategy, params_df::DataFrame; kwargs...)
    remove_keys = (:repeat, :obj, :cash, :pnl, :trades)
    results = DataFrame()
    try
        @withpbar! 1:nrow(params_df) begin
            for n in 1:nrow(params_df) - 1
                params = NamedTuple(k => v for (k, v) in pairs(params_df[n, :]) if !(k in remove_keys))
                ans = slidetest(s; params, kwargs...)
                append!(results, ans)
                @pbupdate!
            end
        end
    catch e
        @error "Error during slide test" exception = (e, catch_backtrace())
    end
    results
end

export gridsearch, progsearch, slidetest
