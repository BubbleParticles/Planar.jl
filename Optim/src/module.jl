using SimMode: SimMode
using SimMode.Executors: st, Instances, OptSetup, OptRun, OptScore, OptMinimize, Context
using SimMode.TimeTicks
using .Instances: value
using .Instances.Data: DataFrame, Not, save_data, load_data, nrow, todata, tobytes
using .Instances.Data: zinstance, Zarr as za, default_value
using .Instances.Data.Zarr: getattrs, writeattrs, writemetadata
using .Instances.Exchanges: sb_exchanges
using .st: Strategy, Sim, SimStrategy, WarmupPeriod
using SimMode.Misc: DFT, user_dir
using SimMode.Lang: Option, splitkws, @debug_backtrace
using Metrics.Statistics: median, mean
using Metrics: Metrics
using REPL.TerminalMenus
using Pkg: Pkg
using Base.Threads: threadid
using SimMode.Misc.DocStringExtensions
import .st: call!
using .Instances.Data.DataFrames: metadata, metadata!, metadatakeys

include("utils.jl")

@doc "A named tuple representing the context and space in the optimization process."
const ContextSpace = NamedTuple{(:ctx, :space),Tuple{Context,Any}}
@doc """ A mutable structure representing the running state of an optimization process.

$(FIELDS)

This structure contains a single field `value` which is an atomic boolean.
It is used to indicate whether the optimization process is currently running or not.
"""
mutable struct OptRunning
    @atomic value::Bool
end
@doc "A constant instance of `OptRunning` initialized with `false`."
const RUNNING = OptRunning(false)
@doc """ Sets the running state of the optimization process to `true`.

$(TYPEDSIGNATURES)

This function changes the `value` field of the `RUNNING` instance to `true`, indicating that the optimization process is currently running.
"""
running!() = @atomic RUNNING.value = true
@doc """ Sets the running state of the optimization process to `false`.

$(TYPEDSIGNATURES)

This function changes the `value` field of the `RUNNING` instance to `false`, indicating that the optimization process is not currently running.
"""
stopcall!() = @atomic RUNNING.value = false
@doc """ Checks if the optimization process is currently running.

$(TYPEDSIGNATURES)

This function returns the `value` field of the `RUNNING` instance, indicating whether the optimization process is currently running.
"""
isrunning() = @atomic RUNNING.value

@doc """ Returns `Optim.ContextSpace` for backtesting

$(TYPEDSIGNATURES)

The `ctx` field (`Executors.Context`) specifies the backtest time period, while `bounds` is a tuple of (lower, upper) bounds for the optimization parameters.
"""
call!(::Strategy, ::OptSetup)::ContextSpace = error("not implemented")

@doc """ Applies parameters to strategy before backtest

$(TYPEDSIGNATURES)
"""
call!(::Strategy, params, ::OptRun) = error("not implemented")

@doc """ Indicates if the optimization is a minimization problem.

$(TYPEDSIGNATURES)

"""
call!(::Strategy, ::OptMinimize) = true

isbest(s, obj, best) = if call!(s, OptMinimize())
    obj < best
else
    obj > best
end

@doc """ A structure representing an optimization session.

$(FIELDS)

This structure stores all the evaluated parameters combinations during an optimization session.
It contains fields for the strategy, context, parameters, attributes, results, best result, lock, and clones of the strategy and context for each thread.
The constructor for `OptSession` also takes an offset and number of threads as optional parameters, with default values of 0 and the number of available threads, respectively.
"""
mutable struct OptSession{S<:SimStrategy,N}
    const s::S
    ctx::Context{Sim}
    const params::T where {T<:NamedTuple}
    const attrs::Dict{Symbol,Any}
    const results::DataFrame
    const best::Ref{Any}
    const lock::ReentrantLock
    const s_clones::NTuple{N,Tuple{ReentrantLock,S}}
    const ctx_clones::NTuple{N,Context{Sim}}
    function OptSession(
        s::Strategy; ctx, params, offset=0, attrs=Dict(), n_threads=Threads.nthreads()
    )
        s_clones = tuple(
            ((ReentrantLock(), similar(s; mode=Sim())) for _ in 1:n_threads)...
        )
        ctx_clones = tuple((similar(ctx) for _ in 1:n_threads)...)
        attrs[:offset] = offset
        new{typeof(s),n_threads}(
            s,
            ctx,
            params,
            attrs,
            DataFrame(),
            Ref(nothing),
            ReentrantLock(),
            s_clones,
            ctx_clones,
        )
    end
end

function Base.show(io::IO, sess::OptSession)
    w(args...) = write(io, string(args...))
    w("Optimization Session: ", nameof(sess.s))
    range = sess.ctx.range
    w("\nTest range: ", range.start, "..", range.stop, " (", range.step, ")")
    if length(sess.params) > 0
        w("\nParams: ")
        params = keys(sess.params)
        w((string(k, ", ") for k in params[begin:(end - 1)])..., params[end])
        w(" (", length(Iterators.product(values(sess.params)...)), ")")
    end
    w("\nConfig: ")
    config = collect(pairs(sess.attrs))
    for (k, v) in config[begin:(end - 1)]
        w(k, "(", v, "), ")
    end
    k, v = config[end]
    w(k, "(", v, ")")
end

_shortdate(date) = Dates.format(date, dateformat"yymmdd")
@doc """ Generates a unique key for an optimization session.

$(TYPEDSIGNATURES)

This function generates a unique key for an optimization session by combining various parts of the session's properties.
The key is a combination of the session's strategy name, context range, parameters, and a hash of the parameters and attributes.
"""
function session_key(sess::OptSession)
    params_part = join(first.(string.(keys(sess.params))))
    ctx_part =
        ((_shortdate(getproperty(sess.ctx.range, p)) for p in (:start, :stop))...,) |>
        x -> join(x, "-")
    s_part = string(nameof(sess.s))
    config_part = first(string(hash(tobytes(sess.params)) + hash(tobytes(sess.attrs))), 4)
    join(("Opt", s_part, string(ctx_part, ":", params_part, config_part)), "/"),
    (; s_part, ctx_part, params_part, config_part)
end

@doc "Get the `Opt` group from the provided zarr instance."
function zgroup_opt(zi)
    if za.is_zgroup(zi.store, "Opt")
        za.zopen(zi.store, "w"; path="Opt")
    else
        try
            za.zgroup(zi.store, "Opt")
        catch e
            if occursin("not empty", e.msg)
                if startswith(Base.prompt("Store not empty, reset? y/[n]"), "y")
                    delete!(zi.store, "Opt")
                    za.zgroup(zi.store, "Opt")
                else
                    rethrow()
                end
            else
                rethrow()
            end
        end
    end
end
@doc """ Returns the zarr group for a given strategy.

$(TYPEDSIGNATURES)

This function checks if a zarr group exists for the given strategy name in the optimization group of the zarr instance.
If it exists, the function returns the group; otherwise, it creates a new zarr group for the strategy.
"""
function zgroup_strategy(zi, s_name::String)
    opt_group = zgroup_opt(zi)
    s_group = if za.is_zgroup(zi.store, "Opt/$s_name")
        opt_group.groups[s_name]
    else
        za.zgroup(opt_group, s_name)
    end
    (; s_group, opt_group)
end

zgroup_strategy(zi, s::Strategy) = zgroup_strategy(zi, string(nameof(s)))
_as_path(s::Strategy) = s.path
_as_path(sess::OptSession) = sess.s.path
_as_path(name::String) = joinpath(user_dir(), "strategies", name)
get_zinstance(input::Union{String,Strategy,OptSession}) =
    let p = dirname(_as_path(input))
        if isdir(p)
            zinstance(p)
        else
            zinstance(user_dir())
        end
    end

@doc """ Save the optimization session over the provided zarr instance

$(TYPEDSIGNATURES)

`sess` is the `OptSession` to be saved. The `from` parameter specifies the starting index for saving optimization results progressively, while `to` specifies the ending index. The function uses the provided zarr instance `zi` for storage.
The function first ensures that the zgroup for the strategy exists. Then, it writes various session attributes to zarr if we're starting from the beginning (`from == 0`). Finally, it saves the result data for the specified range (`from` to `to`).

"""
function save_session(
    sess::OptSession; from=0, to=nrow(sess.results), zi=get_zinstance(sess)
)
    k, parts = session_key(sess)
    # ensure zgroup
    zgroup_strategy(zi, sess.s)
    save_data(
        zi,
        k,
        [(DateTime(from), @view(sess.results[max(1, from):to, :]))];
        chunk_size=(256, 2),
        serialize=true,
    )
    # NOTE: set attributes *after* saving otherwise they do not persist
    z = load_data(zi, k; serialized=true, as_z=true)[1]
    # Save attributes if this is the initial save (from == 0) or if attributes are missing
    if from == 0 || isempty(z.attrs) || pop!(z.attrs, "new", nothing) == "1"
        attrs = z.attrs
        attrs["name"] = parts.s_part
        attrs["startstop"] = parts.ctx_part
        attrs["params_k"] = parts.params_part
        attrs["code"] = parts.config_part
        attrs["ctx"] = tobytes(sess.ctx)
        attrs["params"] = tobytes(sess.params)
        attrs["attrs"] = tobytes(sess.attrs)
        writeattrs(z.storage, z.path, z.attrs)
    end
end

@doc """ Generates a regular expression for matching optimization session keys.

$(TYPEDSIGNATURES)

The function takes three arguments: `startstop`, `params_k`, and `code`.
These represent the start and stop date of the backtesting context, the first letter of every parameter, and a hash of the parameters and attributes truncated to 4 characters, respectively.
The function returns a `Regex` object that matches the string representation of an optimization session key.
"""
function rgx_key(startstop, params_k, code)
    Regex("$startstop:$params_k$code")
end

function _anyexc()
    if nameof(exc) == Symbol()
        if isempty(sb_exchanges)
            :binance
        else
            first(keys(sb_exchanges))
        end
    else
        nameof(exc)
    end
end

_deserattrs(attrs, k) = convert(Vector{UInt8}, attrs[k]) |> todata
@doc """ Loads an optimization session from storage.

$(TYPEDSIGNATURES)

This function loads an optimization session from the provided zarr instance `zi` based on the given parameters.
The parameters include the strategy name, start and stop date of the backtesting context, the first letter of every parameter, and a hash of the parameters and attributes truncated to 4 characters.
The function returns the loaded session, either as a zarr array if `as_z` is `true`, or as an `OptSession` object otherwise.
If `results_only` is `true`, only the results DataFrame of the session is returned.
"""
function load_session(
    name,
    startstop=".*",
    params_k=".*",
    code="";
    as_z=false,
    results_only=false,
    s=nothing,
    zi=nothing,
)
    zi = @something zi get_zinstance(@something s name)
    load(k) = begin
        load_data(zi, k; serialized=true, as_z=true)[1]
    end
    function results!(df, z)
        try
            for row in eachrow(z)
                append!(df, todata(row[2]))
            end
        catch
            @debug_backtrace
        end
        df
    end
    function ensure_attrs(z, retry_f, remove_broken=nothing)
        attrs = z.attrs
        if isempty(attrs)
            @error "ZArray should contain session attributes."
            if isnothing(remove_broken) &&
                isinteractive() &&
                Base.prompt("delete entry $(z.path)? [y]/n") == "n"
                remove_broken = false
            else
                remove_broken = true
                delete!(z)
                writemetadata(z.storage, z.path, z.metadata)
                z.attrs["new"] = "1"
                writeattrs(z.storage, z.path, z.attrs)
            end
            if retry_f isa Function
                z = ensure_attrs(retry_f(), retry_f, remove_broken)
            end
        end
        z
    end

    function session(z, retry_f)
        as_z && return z
        results_only && return results!(DataFrame(), z)
        z = ensure_attrs(z, retry_f)
        attrs = z.attrs
        sess = OptSession(
            @something s st.strategy(Symbol(attrs["name"]); exchange=_anyexc(), mode=Sim());
            ctx=_deserattrs(attrs, "ctx"),
            params=_deserattrs(attrs, "params"),
            attrs=_deserattrs(attrs, "attrs"),
        )
        results!(sess.results, z)
        return sess
    end
    retry_f = nothing
    z = if all((x -> x != ".*").((name, startstop, params_k, code)))
        k = "Opt/$name/$startstop:$params_k$code"
        z = load(k)
    else
        rgx = rgx_key(startstop, params_k, code)
        root = zgroup_opt(zi)
        all_arrs = if haskey(root.groups, name)
            root.groups[name].arrays
        else
            root.arrays
        end
        arrs = filter(pair -> occursin(rgx, pair.first), all_arrs)
        if length(arrs) == 0
            parts = ((k for k in (name, startstop, params_k, code) if k != ".*")...,)
            throw(KeyError(parts))
        elseif length(arrs) == 1
            v = first(arrs)
            v.second
        else
            picks = string.(keys(arrs))
            pick_arr() = begin
                display("Select the session key: ")
                picked = request(RadioMenu(picks; pagesize=4))
                k = picks[picked]
                filter!(x -> x != k, picks)
                get(arrs, k, nothing)
            end
            retry_f = pick_arr
            pick_arr()
        end
    end
    return session(z, retry_f)
end

function load_session(sess::OptSession, args...; kwargs...)
    load_session(values(session_key(sess)[2])..., args...; sess.s, kwargs...)
end

function load_session(s::Strategy)
    load_session(string(nameof(s)); s)
end

@doc """ Calculates the small and big steps for the optimization context.

$(TYPEDSIGNATURES)

The function takes two arguments: `ctx` and `splits`.
`ctx` is the optimization context and `splits` is the number of splits for the optimization process.
The function returns a named tuple with `small_step` and `big_step` which represent the step size for the optimization process.
"""
function ctxsteps(ctx, splits, wp)
    small_step = Millisecond(ctx.range.step).value
    big_step =
        let timespan =
                Millisecond(ctx.range.stop - ctx.range.start).value - Millisecond(wp).value
            if timespan < 0
                timespan = 0
            end
            round(Int, timespan / max(1, splits - 1))
        end
    (; small_step, big_step)
end

@doc """ Calculates the metrics for a given strategy.

$(TYPEDSIGNATURES)

The function takes a strategy `s` and an initial cash amount as arguments.
It calculates the objective score, the current total cash, the profit and loss ratio, and the number of trades.
The function returns these metrics as a named tuple.
"""
metrics_func(s; initial_cash) = begin
    obj = call!(s, OptScore())
    # record run
    cash = value(st.current_total(s))
    pnl = cash / initial_cash - 1.0
    trades = st.trades_count(s)
    (; obj, cash, pnl, trades)
end

function ms_mult(ms, mult::DFT)
    round(Int, Millisecond(ms).value * mult) |> Millisecond
end

function random_ctx_length(ctx, splits, big_step, small_step)
    split = max(1, round(Int, length(ctx) / splits))
    pad_qt_1 = rand(1:splits) / splits
    pad_qt_2 = rand(1:splits) / splits
    pad_qt_3 = rand(1:splits) / splits
    step_type = typeof(ctx.range.step)
    step_type(round(Int, split * ctx.range.step.value * pad_qt_1)) +
    ms_mult(big_step, pad_qt_2) +
    ms_mult(small_step, pad_qt_3)
end

function random_ctx_start(ctx, splits, tid, wp, big_step, small_step)
    Random.seed!() # NOTE: this is to affect random_ctx_length
    pad_qt_1 = rand(1:splits) / splits
    pad_qt_2 = rand(1:splits) / splits
    pad_qt_3 = rand(1:splits) / splits
    ctx.range.start +
    wp +
    ms_mult(ctx.range.step, pad_qt_1) +
    ms_mult(big_step, pad_qt_2) * tid +
    ms_mult(small_step, pad_qt_3)
end

@doc """ Defines the backtest function for an optimization session.

$(TYPEDSIGNATURES)

The function takes three arguments: `sess`, `small_step`, and `big_step`.
`sess` is the optimization session, `small_step` is the small step size for the optimization process, and `big_step` is the big step size for the optimization process.
The function returns a function that performs a backtest for a given set of parameters and a given iteration number.
"""
function define_backtest_func(sess, small_step, big_step; verbose=false)
    splits = sess.attrs[:splits]
    function opt_backtest_func(params, n)
        tid = Threads.threadid()
        slot = sess.s_clones[tid]
        try
            @lock slot[1] begin
                s = slot[2]
                ctx = sess.ctx_clones[tid]
                # clear strat
                st.reset!(s, true)
                # set params as strategy attributes
                setparams!(s, sess, params)
                # Pre backtest hook
                call!(s, params, OptRun())
                # randomize strategy startup time
                let wp = call!(s, WarmupPeriod())
                    start_at = random_ctx_start(
                        ctx, splits, tid, wp, big_step, small_step
                    )
                    current!(ctx.range, start_at)
                    stop_at =
                        start_at + random_ctx_length(ctx, splits, big_step, small_step)
                    if stop_at < ctx.range.stop
                        ctx.range.stop = stop_at
                    end
                    @debug "optim backtest range" tid compact(ms(small_step)) compact(
                        ms(big_step)
                    ) start_at stop_at duration = compact(stop_at - start_at) source_duration = compact(
                        ctx.range.stop - ctx.range.start
                    ) source_start = ctx.range.start
                end
                # backtest and score
                initial_cash = value(s.cash)
                start!(s, ctx; doreset=false, resetctx=false)
                st.sizehint!(s) # avoid deallocations
                metrics = metrics_func(s; initial_cash)
                lock(sess.lock) do
                    push!(
                        sess.results,
                        (;
                            repeat=n,
                            metrics...,
                            (
                                pname => p for (pname, p) in zip(keys(sess.params), params)
                            )...,
                        ),
                    )
                    if verbose
                        if "print" ∈ metadatakeys(sess.results)
                            push!(metadata(sess.results, "print"), metrics)
                        else
                            metadata!(sess.results, "print", Any[metrics]; style=:note)
                        end
                    end
                    @debug "number of results: $(nrow(sess.results))"
                end
                metrics.obj
            end
        catch e
            @error "backtest run" exception = (e, catch_backtrace())
        end
    end
end

@doc """ Multi-threaded optimization function.

$(TYPEDSIGNATURES)

The function takes four arguments: `splits`, `backtest_func`, `median_func`, and `obj_type`.
`splits` is the number of splits for the optimization process, `backtest_func` is the backtest function, `median_func` is the function to calculate the median, and `obj_type` is the type of the objective.
The function returns a function that performs a multi-threaded optimization for a given set of parameters.
"""
function _get_color_and_update_best(sess, obj, pnl)
    # Check if this is the best objective yet
    best = sess.best[]
    is_best = best isa Ref{Nothing} || isbest(s, obj, best)
    if is_best
        sess.best[] = obj
    end
    
    # Color formatting
    if is_best
        color = "\033[1;32m"  # bold green
    elseif pnl > 0
        color = "\033[32m"    # green
    else
        color = "\033[0m"     # default
    end
    reset = "\033[0m"
    
    return color, reset
end

function _print_aggregated_metrics(sess, metrics_list, n)
    # Skip if all runs have no trades
    all(m -> m.trades == 0, metrics_list) && return
    
    # Calculate aggregated statistics
    objs = [length(m.obj) > 1 ? m.obj : m.obj[1] for m in metrics_list]
    pnls = [m.pnl for m in metrics_list]
    cashs = [m.cash for m in metrics_list]
    trades = [m.trades for m in metrics_list]
    
    obj_avg = mean(objs)
    obj_min = round(minimum(objs), digits=4)
    obj_max = round(maximum(objs), digits=4)
    
    pnl_avg = round(mean(pnls) * 100, digits=2)
    pnl_min = round(minimum(pnls) * 100, digits=2)
    pnl_max = round(maximum(pnls) * 100, digits=2)
    
    cash_avg = round(mean(cashs), digits=2)
    cash_min = round(minimum(cashs), digits=2)
    cash_max = round(maximum(cashs), digits=2)
    
    trades_avg = round(mean(trades), digits=1)
    trades_min = round(minimum(trades), digits=1)
    trades_max = round(maximum(trades), digits=1)
    
    # Get color and update best
    color, reset = _get_color_and_update_best(sess, obj_avg, mean(pnls))
    
    obj_avg_str = round(obj_avg, digits=4)
    println("$(color)run: $(n) | obj: $(obj_avg_str) [$(obj_min)-$(obj_max)] | pnl: $(pnl_avg)% [$(pnl_min)-$(pnl_max)] | cash: $(cash_avg) [$(cash_min)-$(cash_max)] | trades: $(trades_avg) [$(trades_min)-$(trades_max)]$(reset)")
end

function _print_metrics(sess, n=nothing)
    if "print" ∈ metadatakeys(sess.results)
        lock(sess.lock) do
            prints = metadata(sess.results, "print")
            if !isempty(prints)
                for m in prints
                    # Skip runs with no trades
                    m.trades == 0 && continue
                    
                    # Get color and update best
                    obj = length(m.obj) > 1 ? m.obj : m.obj[1]
                    color, reset = _get_color_and_update_best(sess, obj, m.pnl)
                    
                    # Format as table
                    pnl_pct = round(m.pnl * 100, digits=2)
                    cash_str = round(m.cash, digits=2)
                    obj_str = round(obj, digits=4)
                    
                    run_str = isnothing(n) ? "" : "run: $(n) | "
                    println("$(color)$(run_str)obj: $(obj_str) | pnl: $(pnl_pct)% | cash: $(cash_str) | trades: $(m.trades)$(reset)")
                end
                empty!(prints)
            end
        end
    end
end

function _multi_opt_func(sess, splits, backtest_func, median_func, obj_type)
    function parallel_backtest_func(params, n)
        scores = Vector{obj_type}(undef, splits)
        metrics_collected = Vector{Any}(undef, splits)
        Threads.@threads for i in 1:splits
            if isrunning()
                scores[i] = @something backtest_func(params, n) default_value(obj_type)
                @debug "parallel backtest job finished" i n
                # Collect metrics instead of printing immediately
                if "print" ∈ metadatakeys(sess.results)
                    lock(sess.lock) do
                        prints = metadata(sess.results, "print")
                        if !isempty(prints)
                            metrics_collected[i] = popfirst!(prints)
                        end
                    end
                end
            end
        end
        @debug "parallel backtest batch finished" n

        # Print aggregated metrics
        valid_metrics = filter(!isnothing, metrics_collected)
        if !isempty(valid_metrics)
            _print_aggregated_metrics(sess, valid_metrics, n)
        end

        mapreduce(permutedims, vcat, scores) |> median_func
    end
end

@doc """ Single-threaded optimization function.

$(TYPEDSIGNATURES)

The function takes four arguments: `splits`, `backtest_func`, `median_func`, and `obj_type`.
`splits` is the number of splits for the optimization process, `backtest_func` is the backtest function, `median_func` is the function to calculate the median, and `obj_type` is the type of the objective.
The function returns a function that performs a single-threaded optimization for a given set of parameters.
"""
function _single_opt_func(sess, splits, backtest_func, median_func, args...)
    function single_backtest_func(params, n=0)
        scores = Vector{Any}(undef, splits)
        for i in 1:splits
            scores[i] = backtest_func(params, n)
            _print_metrics(sess, n)
        end
        mapreduce(permutedims, vcat, scores) |> median_func
    end
end

@doc """ Defines the median function for multi-objective mode.

$(TYPEDSIGNATURES)

The function takes a boolean argument `ismulti` which indicates if the optimization is multi-objective.
If `ismulti` is `true`, the function returns a function that calculates the median over all the repeated iterations.
Otherwise, it returns a function that calculates the median of a given array.
"""
function define_median_func(splits)
    if splits > 1
        median_tuple(x) = tuple(median(x; dims=1)...)
    else
        median
    end
end

@doc """ Defines the optimization function for a given strategy.

$(TYPEDSIGNATURES)

The function takes several arguments: `s`, `backtest_func`, `ismulti`, `splits`, `obj_type`, and `isthreaded`.
`s` is the strategy, `backtest_func` is the backtest function, `ismulti` indicates if the optimization is multi-objective, `splits` is the number of splits for the optimization process, `obj_type` is the type of the objective, and `isthreaded` indicates if the optimization is threaded.
The function returns the appropriate optimization function based on these parameters.
"""
function define_opt_func(
    s::Strategy;
    backtest_func,
    split_test,
    splits,
    n_jobs,
    obj_type,
    isthreaded=isthreadsafe(s),
    sess,
)
    median_func = define_median_func(splits)
    opt_func = isthreaded && split_test ? _multi_opt_func : _single_opt_func
    epoch_splits = split_test ? n_jobs * splits : splits
    opt_func(sess, epoch_splits, backtest_func, median_func, obj_type)
end

@doc """ Returns the number of objectives and their type.

$(TYPEDSIGNATURES)

The function takes a strategy `s` as an argument.
It returns a tuple containing the type of the objective and the number of objectives.
"""
function objectives(s)
    let test_obj = call!(s, OptScore())
        typeof(test_obj), length(test_obj)
    end
end

@doc """ Fetches the named tuple of a single parameters combination.

$(TYPEDSIGNATURES)

The function takes an optimization session `sess` and an optional index `idx` (defaulting to the last row of the results).
It returns the parameters of the optimization session at the specified index as a named tuple.
"""
function result_params(sess::OptSession, idx=nrow(sess.results))
    iszero(idx) && return nothing
    row = sess.results[idx, :]
    (; (k => getproperty(row, k) for k in keys(sess.params))...)
end

@doc """ Generates the path for the log file of a given strategy.

$(TYPEDSIGNATURES)

The function takes a strategy `s` and an optional `name` (defaulting to the current timestamp).
It constructs a directory path based on the strategy's path, and ensures this directory exists.
Then, it returns the full path to the log file within this directory, along with the directory path itself.

"""
function log_path(s, name=split(string(now()), ".")[1])
    dirpath = joinpath(realpath(dirname(s.path)), "logs", "opt", string(nameof(s)))
    isdir(dirpath) || mkpath(dirpath)
    joinpath(dirpath, name * ".log"), dirpath
end

@doc """ Returns the paths to all log files for a given strategy.

$(TYPEDSIGNATURES)

The function takes a strategy `s` as an argument.
It retrieves the directory path for the strategy's log files and returns the full paths to all log files within this directory.

"""
function logs(s)
    dirpath = log_path(s, "")[2]
    joinpath.(dirpath, readdir(dirpath))
end

@doc """ Clears all log files for a given strategy.

$(TYPEDSIGNATURES)

The function takes a strategy `s` as an argument.
It retrieves the directory path for the strategy's log files and removes all files within this directory.

"""
function logs_clear(s)
    dirpath = log_path(s, "")[2]
    for f in readdir(dirpath)
        rm(joinpath(dirpath, f); force=true)
    end
end

@doc """ Prints the content of a specific log file for a given strategy.

$(TYPEDSIGNATURES)

The function takes a strategy `s` and an optional index `idx` (defaulting to the last log file).
It retrieves the directory path for the strategy's log files, selects the log file at the specified index, and prints its content.

"""
function print_log(s, idx=nothing)
    let logs = logs(s)
        isempty(logs) && error("no logs found for strategy $(nameof(s))")
        println(read(logs[@something idx lastindex(logs)], String))
    end
end

maybereduce(v::AbstractVector, f::Function) = f(v)
maybereduce(v, _) = v
function agg(f, sess::OptSession)
    res = sess.results
    if isempty(res)
        res
    else
        gd = groupby(res, [keys(sess.params)...])
        combine(gd, f; renamecols=false)
    end
end
@doc """ Aggregates the results of an optimization session.

$(TYPEDSIGNATURES)

The function takes an optimization session `sess` and optional functions `reduce_func` and `agg_func`.
It groups the results by the session parameters, applies the `reduce_func` to each group, and then applies the `agg_func` to the reduced results.

"""
function agg(sess::OptSession; reduce_func=mean, agg_func=median)
    agg(
        (
            Not([keys(sess.params)..., :repeat]) .=>
                x -> maybereduce(x, reduce_func) |> agg_func
        ),
        sess,
    )
end

function optsessions(s::Strategy; zi=get_zinstance(s))
    optsessions(string(nameof(s)); zi)
end

@doc """ Returns the zarrays storing all the optimization session over the specified zarrinstance.

$(TYPEDSIGNATURES)

The function takes a strategy `s` as an argument.
It retrieves the directory path for the strategy's log files and returns the full paths to all log files within this directory.

"""
function optsessions(s_name::String; zi=get_zinstance(s_name))
    opt_group = zgroup_opt(zi)
    if s_name in keys(opt_group.groups)
        opt_group.groups[s_name].arrays
    else
        nothing
    end
end

@doc """ Clears optimization sessions of a strategy.

$(TYPEDSIGNATURES)

The function accepts a strategy name `s_name` and an optional `keep_by` dictionary.
If `keep_by` is provided, sessions matching these attributes (`ctx`, `params`, or `attrs`) are not deleted.
It checks each session, and deletes it if it doesn't match `keep_by` or if `keep_by` is empty.

"""
function delete_sessions!(
    s_name::String; keep_by=Dict{String,Any}(), zi=get_zinstance(s_name)
)
    delete_all = isempty(keep_by)
    @assert delete_all || all(k ∈ ("ctx", "params", "attrs") for k in keys(keep_by)) "`keep_by` only support ctx, params or attrs keys."
    for z in values(optsessions(s_name; zi))
        delete_all && begin
            delete!(z)
            continue
        end
        let attrs = z.attrs
            for (k, v) in keep_by
                if k ∈ keys(attrs) && v == todata(Vector{UInt8}(attrs[k]))
                    continue
                else
                    delete!(z)
                    break
                end
            end
        end
    end
end

@doc """ Extracts the lower and upper bounds from a parameters dictionary.

$(TYPEDSIGNATURES)

The function takes a parameters dictionary `params` as an argument.
It returns two arrays, `lower` and `upper`, containing the first and last values of each parameter range in the dictionary, respectively.

"""
lowerupper(params) = begin
    lower, upper = Float64[], Float64[]
    for p in values(params)
        if p isa AbstractVector && eltype(p) <: Symbol
            # Categorical parameter - use indices
            push!(lower, 1.0)
            push!(upper, Float64(length(p)))
        else
            # Numeric parameter - use first and last values
            push!(lower, Float64(first(p)))
            push!(upper, Float64(last(p)))
        end
    end
    lower, upper
end

delete_sessions!(s::Strategy; kwargs...) = delete_sessions!(string(nameof(s)); kwargs...)
@doc """ Loads the BayesianOptimization extension.

The function checks if the BayesianOptimization package is installed in the current environment.
If not, it prompts the user to add it to the main environment.

"""
function extbayes!()
    let prev = Pkg.project().path
        try
            Pkg.activate("Optim"; io=devnull)
            if isnothing(@eval Main Base.find_package("BayesianOptimization"))
                if Base.prompt(
                    "BayesianOptimization package not found, add it to the main env? y/[n]"
                ) == "y"
                    try
                        Pkg.activate(; io=devnull)
                        Pkg.add("BayesianOptimization")
                    finally
                        Pkg.activate("Optim"; io=devnull)
                    end
                end
            end
            @eval Main using BayesianOptimization
        finally
            Pkg.activate(prev; io=devnull)
        end
    end
end

export OptSession, extbayes!

include("optimize.jl")
include("grid.jl")
include("params_selection.jl")
include("bbo.jl")
