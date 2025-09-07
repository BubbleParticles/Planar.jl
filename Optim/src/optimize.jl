using SimMode.TimeTicks: current!, compact, Second, Millisecond
using SimMode: start!
using Random
using SimMode.Lang: @debug_backtrace
using Base.Threads: ReentrantLock
using SimMode.Dates: Second

# Add Optimization.jl imports
using Optimization
using OptimizationBBO
using OptimizationCMAEvolutionStrategy
using OptimizationEvolutionary
using OptimizationOptimJL
using OptimizationManopt
using Symbolics
using ModelingToolkit
# using OptimizationNOMAD
# using OptimizationSpeedMapping
# using Zygote
using Optimization: OptimizationProblem, OptimizationFunction, solve

# Optimization.jl provides various optimization algorithms through different packages
# such as OptimizationBBO, OptimizationCMAEvolutionStrategy, etc.

_tsaferesolve(v::Ref{Bool}) = v[]
_tsaferesolve(v::Bool) = v
@doc """ Tests if if the strategy is thread safe by looking up the `THREADSAFE` global. """
isthreadsafe(s::Strategy) =
    if isdefined(s.self, :THREADSAFE)
        _tsaferesolve(s.self.THREADSAFE)
    else
        false
    end

@doc """ Extracts the context, parameters, and bounds from a given strategy.

$(TYPEDSIGNATURES)

This function takes a strategy as input and returns the context, parameters, and bounds associated with that strategy.
The bounds can be specified as:
- A tuple of (lower, upper) bounds
- A function that returns bounds
- A NamedTuple with :bounds and optional :precision and :categorical fields
"""
function ctxfromstrat(s)
    ctx, params, s_space = call!(s, OptSetup())
    # Record parameter names order for later value extraction/conversions
    try
        s[:opt_param_names] = keys(params)
    catch
        # ignore if params is not a NamedTuple
    end
    ctx,
    params,
    s_space,
    if s_space isa Function
        s_space()
    elseif s_space isa Tuple && length(s_space) == 2
        # Direct bounds specification (lower, upper)
        s_space
    elseif s_space isa NamedTuple && hasproperty(s_space, :bounds)
        # New format with bounds and optional precision/categorical info
        bounds = s_space.bounds
        precision = get(s_space, :precision, nothing)
        categorical = get(s_space, :categorical, nothing)

        if !isnothing(precision)
            # Store precision info for later use in parameter conversion
            s[:opt_precision] = precision
        end

        if !isnothing(categorical)
            # Store categorical info for later use in parameter conversion
            s[:opt_categorical] = categorical
        end

        bounds
    elseif s_space isa NamedTuple && hasproperty(s_space, :kind)
        # Legacy BlackBoxOptim space specification - convert to bounds
        lower, upper = lowerupper(params)
        if hasproperty(s_space, :precision)
            # Store precision info for later use
            s[:opt_precision] = s_space.precision
            @warn "Mixed precision search spaces are deprecated. Use direct bounds specification with :precision field."
        end
        (lower, upper)
    else
        error(
            "Wrong optimization parameters. Pass either bounds as (lower, upper) tuple, a function that returns bounds, or a NamedTuple with :bounds field.",
        )
    end
end

@doc """ Returns the dimension of the search space.

$(TYPEDSIGNATURES)

This function takes the parameters as input, which should include lower and upper bounds arrays as the second and third elements. It asserts that the lengths of these arrays are equal and returns their common length, which represents the dimension of the search space.
"""
function _spacedims(params)
    @assert length(params) > 2 "Params second and third element should be lower and upper bounds arrays."
    lower = params[2]
    upper = params[3]
    @assert length(lower) == length(upper) "Params lower and upper bounds do not match in length."
    length(lower)
end

function default_opt_method(solve_method)
    if solve_method in (:lbfgs, :sophia)
        :zygote
    elseif solve_method in (:poly, :prima, :speed)
        :afd
    end
end

function get_method(v, method_kwargs)
    if isnothing(v)
        return nothing
    elseif v == :bbo
        # BBO is a solve method, not an opt method; return the constructor
        BBO_adaptive_de_rand_1_bin(; method_kwargs...)
    elseif v == :evo_cma
        CMAEvolutionStrategyOpt() # no args
    elseif v == :evo_cmaes
        CMAES(; method_kwargs...)
    elseif v == :evo_ga
        GA(; method_kwargs...)
    elseif v == :evo_de
        DE(; method_kwargs...)
    elseif v == :evo_tree
        TreeGP(; method_kwargs...)
    elseif v == :lbfgs
        LBFGS()
    elseif v == :afd
        AutoForwardDiff(; method_kwargs...)
    elseif v == :speed
        SpeedMappingOpt()
    elseif v == :zygote
        AutoZygote()
    elseif v == :nomad
        NOMADOpt()
    elseif v == :nelder
        Optim.NelderMead()
    elseif v == :ann
        Optim.SimulatedAnnealing()
    elseif v == :swarm
        Optim.ParticleSwarm()
    elseif v == :cgradient
        Optim.ConjugateGradient()
    elseif v == :gradientd
        Optim.GradientDescent()
    elseif v == :opt_bfgs
        Optim.BFGS()
    elseif v == :opt_lbfgs
        Optim.LBFGS()
    elseif v == :ngm
        Optim.NGMRES()
    elseif v == :oaccel
        Optim.OACCEL()
    elseif v == :newton_trust
        Optim.NewtonTrustRegion()
    elseif v == :newton
        Optim.Newton()
    elseif v == :ipnewton
        Optim.IPNewton()
    elseif v == :krylov
        Optim.KrylovTrustRegion()
    elseif v == :automod
        Optimization.AutoModelingToolkit()
    else
        @assert !(v isa DataType) "Expected an instance of an Optimization.jl method, got $(v)"
        v
    end
end

inc!(s::Strategy) = s[:strategy] += 1

#############################
# Internal helper functions #
#############################

# Session and space setup
function _create_session_and_space(s::Strategy{Sim}; resume::Bool, zi)
    ctx, params, s_space, space = ctxfromstrat(s)
    sess = OptSession(s; ctx, params, attrs=Dict{Symbol,Any}(pairs((; s_space))))
    resume && resume!(sess; zi)
    return sess, ctx, params, space
end

# Build save callback args
function _build_save_args(sess; save_freq, zi, resume::Bool)
    from = Ref(nrow(sess.results) + 1)
    if isnothing(save_freq)
        return (), from
    end
    resume || save_session(sess; zi)
    return (
        CallbackFunction=(_...) -> begin
            lock(sess.lock) do
                save_session(sess; from=from[], zi)
                from[] = nrow(sess.results) + 1
            end
        end,
        CallbackInterval=Millisecond(save_freq).value / 1000.0,
    ),
    from
end

# Propagate precision/categorical/bounds to thread clones
function _propagate_clone_attrs!(sess::OptSession, s::Strategy)
    for (lock, strategy_clone) in sess.s_clones
        if haskey(s, :opt_precision)
            strategy_clone[:opt_precision] = s[:opt_precision]
        end
        if haskey(s, :opt_categorical)
            strategy_clone[:opt_categorical] = s[:opt_categorical]
        end
        if haskey(s, :opt_bounds)
            strategy_clone[:opt_bounds] = s[:opt_bounds]
        end
    end
    return nothing
end

# Build the objective used by Optimization.jl
function _make_opt_function(
    sess::OptSession,
    s::Strategy,
    backtest_func,
    n_obj::Int,
    split_test::Bool,
    splits::Int,
    n_jobs::Int,
    obj_type,
)
    # Shared cache across all multi-start tasks; use tuple keys for content-based equality
    evaluation_cache = Dict{Tuple,Any}()
    cache_lock = ReentrantLock()
    counter = (; lock=ReentrantLock(), n=Ref(0))

    run_func = define_opt_func(s; sess, backtest_func, split_test, splits, n_jobs, obj_type)

    function opt_function(u, p)
        u_rounded = apply_precision(u, s)
        key = Tuple(float.(u_rounded))
        @lock cache_lock if haskey(evaluation_cache, key)
            return evaluation_cache[key]
        end
        # Reset strategy and re-init context
        this_n = counter.n[] + 1
        @lock counter.lock counter.n[] = this_n
        result = run_func(u_rounded, this_n)
        objective_value = n_obj == 1 ? result[1] : result
        @lock cache_lock evaluation_cache[key] = objective_value
        return objective_value
    end

    return opt_function
end

# Extract lower/upper bounds
function _bounds_from_space(space)
    if space isa Tuple && length(space) == 2
        return space[1], space[2]
    else
        error("Expected space to be a tuple (lower, upper), got $(typeof(space))")
    end
end

function is_not_subtype_of_any(T, supertypes)
    return nothing
end

# Check if a solve method is compatible with box constraints
function supports_box_constraints(solve_method)
    this_type = typeof(solve_method)
    return all(s -> !(this_type <: s), (Optim.Newton,))
end

# Build OptimizationProblem
function _build_problem(
    optf, initial_guess, lower_float, upper_float, integer_mask; solve_method_instance
)
    # Always provide bounds; some algorithms require them
    kwargs = Dict{Symbol,Any}()

    # Check if the solve method supports box constraints
    if supports_box_constraints(solve_method_instance)
        kwargs[:lb] = lower_float
        kwargs[:ub] = upper_float
    else
        # Provide specific warning for Newton optimizer
        if typeof(solve_method_instance) == Optim.Newton
            @warn "$solve_method_instance optimizer is not compatible with box constraints (Fminbox). Excluding bounds for this optimization. Consider using :ipnewton instead for box-constrained Newton optimization."
        end
    end

    any(integer_mask) && (kwargs[:int] = integer_mask)
    return OptimizationProblem(optf, initial_guess, ; kwargs...)
end

# Try to build an initial guess vector from the strategy's current defaults
function _initial_guess_from_strategy(
    s::Strategy, lower::AbstractVector, upper::AbstractVector
)
    names = get(s, :opt_param_names, nothing)
    isnothing(names) && return nothing
    categorical_info = get(s, :opt_categorical, nothing)
    ig = Vector{DFT}(undef, length(lower))
    i = 0
    for pname in names
        i += 1
        v = get(s, pname, nothing)
        v === nothing && return nothing
        # Map categoricals to index if applicable
        if !isnothing(categorical_info) && i <= length(categorical_info)
            cats = categorical_info[i]
            if !(cats === nothing)
                idx = findfirst(==(v), cats)
                idx === nothing && return nothing
                ig[i] = DFT(idx)
                # proceed to clamp later
                continue
            end
        end
        # Map time periods (Minute/Second/etc.) and numbers to DFT
        if v isa Dates.Period
            ig[i] = DFT(Dates.value(v))
        elseif v isa Integer
            ig[i] = DFT(v)
        elseif v isa AbstractFloat
            ig[i] = DFT(v)
        else
            # Unsupported type for numeric optimization
            return nothing
        end
    end
    # Clamp and apply precision if available
    @inbounds for j in eachindex(ig)
        ig[j] = clamp(ig[j], lower[j], upper[j])
    end
    ig = apply_precision(ig, s)
    return ig
end

# Prepare bounds, initial guess, integer mask and build the OptimizationProblem
function _setup_problem_and_bounds(
    s::Strategy,
    space,
    opt_function_or_optf;
    opt_method_instance=nothing,
    solve_method_instance=nothing,
    initial_guess_override=nothing,
)
    # Get bounds from the strategy setup or stored bounds
    lower, upper = if space === nothing
        bounds = get(s, :opt_bounds, nothing)
        isnothing(bounds) && error(
            "opt_bounds not set on strategy; call _setup_problem_and_bounds earlier"
        )
        bounds
    elseif space isa Tuple
        space
    else
        _bounds_from_space(space)
    end

    # Store bounds for later use in parameter clamping
    s[:opt_bounds] = (copy(lower), copy(upper))

    # Ensure bounds are Float arrays for Optimization.jl compatibility
    lower_float = DFT.(lower)
    upper_float = DFT.(upper)

    # Create or accept OptimizationFunction
    optf = if opt_function_or_optf isa Function
        opt_func_args = isnothing(opt_method_instance) ? () : (opt_method_instance,)
        OptimizationFunction(opt_function_or_optf, opt_func_args...)
    else
        opt_function_or_optf
    end

    # Use provided override, otherwise attempt strategy defaults, otherwise midpoint
    initial_guess = if !isnothing(initial_guess_override)
        initial_guess_override
    else
        strategy_guess = _initial_guess_from_strategy(s, lower_float, upper_float)
        if isnothing(strategy_guess)
            ((lower_float .+ upper_float) ./ 2.0)
        else
            strategy_guess
        end
    end

    # Check if we have integer parameters
    precision = get(s, :opt_precision, nothing)
    integer_mask = if !isnothing(precision)
        [prec == -1 for prec in precision]
    else
        falses(length(lower_float))
    end

    # Create problem with integer constraints if needed
    prob = _build_problem(
        optf, initial_guess, lower_float, upper_float, integer_mask; solve_method_instance
    )

    return prob
end

# Build early-termination callback
function _build_callback(early_threshold, max_failures)
    # Track consecutive failures
    consecutive_failures = Ref(0)

    return (u, p) -> begin
        # Normalize objective value possibly being a vector/tuple
        objective_value = p isa Number ? p : (p isa AbstractArray || p isa Tuple ? p[1] : p)

        # Check early termination threshold
        if objective_value isa Number && objective_value < early_threshold
            @info "Early termination: objective value below threshold" objective_value =
                objective_value early_threshold = early_threshold
            return true
        end

        # Check for consecutive failures
        if max_failures < Inf
            is_bad = false
            if p isa Number
                is_bad = (p == Inf || isnan(p))
            elseif p isa AbstractArray || p isa Tuple
                # consider any bad component as a failure
                @inbounds for v in p
                    if v == Inf || isnan(v)
                        is_bad = true
                        break
                    end
                end
            end

            if is_bad
                consecutive_failures[] += 1
                if consecutive_failures[] >= max_failures
                    @info "Early termination: maximum consecutive failures reached" consecutive_failures = consecutive_failures[] max_failures =
                        max_failures
                    return true
                end
            else
                consecutive_failures[] = 0
            end
        end

        return false
    end
end

# Compose early termination and periodic save callbacks
function _compose_callbacks(solve_method, save_args, early_threshold, max_failures)
    # speedmapping does not support callbacks
    if solve_method in (:speed, :nomad)
        return nothing
    end
    # Create callback for early termination
    early_term_callback = _build_callback(early_threshold, max_failures)
    # Combine with periodic save callback if present
    periodic_save_callback = nothing
    callback_interval = nothing
    if !isempty(save_args)
        nt = save_args[1]
        if hasproperty(nt, :CallbackFunction)
            periodic_save_callback = getproperty(nt, :CallbackFunction)
        end
        if hasproperty(nt, :CallbackInterval)
            callback_interval = getproperty(nt, :CallbackInterval)
        end
    end
    # Compose callbacks if both exist
    callback = nothing
    if !isnothing(early_term_callback) && !isnothing(periodic_save_callback)
        @debug "callback: combining early termination and periodic save callbacks"
        callback = (u, p) -> begin
            early_stop = early_term_callback(u, p)
            periodic_save_callback(u, p)
            return early_stop
        end
    elseif !isnothing(early_term_callback)
        @debug "callback: using early termination callback"
        callback = early_term_callback
    elseif !isnothing(periodic_save_callback)
        @debug "callback: using periodic save callback"
        # Ensure boolean return value expected by solver callbacks
        callback = (u, p) -> begin
            periodic_save_callback(u, p)
            return false
        end
    else
        @debug "callback: no callback provided"
    end
    return callback
end

# Single-job solve
function _run_single(prob, solve_method_instance, callback, solve_kwargs)
    if isnothing(callback)
        return solve(prob, solve_method_instance; solve_kwargs...)
    else
        # merge callback into kwargs for a single call site
        return solve(prob, solve_method_instance; callback=callback, solve_kwargs...)
    end
end

# Pre-initialize all exchanges to avoid race conditions during parallel execution
# This ensures getexchange! is called safely before multithreading begins
function preinitialize_exchanges(sess::OptSession)
    for thread_id in 1:min(Threads.nthreads(), length(sess.s_clones))
        try
            strategy_clone = sess.s_clones[thread_id][2]
            # Force exchange initialization by accessing the exchange
            exc_id = st.exchangeid(strategy_clone)
            sandbox = get(strategy_clone.config, :sandbox, true)
            account = get(strategy_clone.config, :account, "")
            # This will populate the cache safely through Instances
            Instances.getexchange!(exc_id; sandbox, account)
        catch e
            # Exchange initialization might fail, continue anyway
            @debug "Exchange pre-initialization failed for thread $thread_id: $e"
        end
    end
end

# Build a thread-safe OptimizationFunction wrapper around the backtest
function build_safe_optimization_function(
    s::Strategy, n_obj::Int, backtest_func, opt_method_instance
)
    counter = Ref(0)
    counter_lock = ReentrantLock()

    function safe_opt_function(u, p)
        u_rounded = apply_precision(u, s)

        # Thread-safe counter increment
        this_n = @lock counter_lock begin
            counter[] += 1
        end

        result = backtest_func(u_rounded, this_n)
        return n_obj == 1 ? result[1] : result
    end

    opt_func_args = isnothing(opt_method_instance) ? () : (opt_method_instance,)
    return OptimizationFunction(safe_opt_function, opt_func_args...)
end

# Build the collection of initial guesses for multi-start optimization
function build_initial_guesses(s::Strategy, n_jobs::Int)
    bounds = get(s, :opt_bounds, nothing)
    isnothing(bounds) &&
        error("opt_bounds not set on strategy; call _setup_problem_and_bounds first")
    lower_float, upper_float = DFT.(bounds[1]), DFT.(bounds[2])
    # Baseline guess: use strategy defaults if available, else midpoint
    strategy_guess = _initial_guess_from_strategy(s, lower_float, upper_float)
    initial_guess =
        isnothing(strategy_guess) ? ((lower_float .+ upper_float) ./ 2.0) : strategy_guess
    function random_initial_guess()
        ig = similar(initial_guess)
        @inbounds for i in eachindex(ig)
            ig[i] = rand() * (upper_float[i] - lower_float[i]) + lower_float[i]
        end
        apply_precision(ig, s)
    end

    initial_guesses = Vector{typeof(initial_guess)}(undef, n_jobs)
    initial_guesses[1] = initial_guess
    for j in 2:n_jobs
        initial_guesses[j] = random_initial_guess()
    end
    return initial_guesses
end

# Multi-start concurrent solves with thread-safe exchange access
function _run_multi_start(
    sess::OptSession,
    s::Strategy,
    backtest_func;
    n_obj::Int,
    n_jobs::Int,
    solve_method_instance,
    opt_method_instance,
    callback,
    solve_kwargs,
)
    # Generate initial guesses (first is provided initial)
    initial_guesses = build_initial_guesses(s, n_jobs)

    # Pre-initialize all exchanges to avoid race conditions during parallel execution
    # This ensures getexchange! is called safely before multithreading begins
    preinitialize_exchanges(sess)

    # Create thread-safe optimization function
    safe_optf = build_safe_optimization_function(
        s, n_obj, backtest_func, opt_method_instance
    )

    # Now run concurrent optimization jobs - exchanges are pre-cached
    tasks = Vector{Task}(undef, n_jobs)
    for j in 1:n_jobs
        tasks[j] = Threads.@spawn begin
            prob = _setup_problem_and_bounds(
                s,
                nothing,
                safe_optf;
                initial_guess_override=initial_guesses[j, solve_method_instance],
            )
            if isnothing(callback)
                solve(prob, solve_method_instance; solve_kwargs...)
            else
                solve(prob, solve_method_instance; callback=callback, solve_kwargs...)
            end
        end
    end

    solutions = map(fetch, tasks)

    best_idx = argmin([
        sol.objective isa Number ? sol.objective : sol.objective[1] for sol in solutions
    ])
    return solutions[best_idx]
end

function requires_opt_method(solve_method)
    solve_method in (
        :cgradient,
        :gradientd,
        :opt_lbfgs,
        :opt_bfgs,
        :newton,
        :ipnewton,
        :newton_trust,
        :oaccel,
    )
end

@doc """ Optimize parameters using the Optimization.jl framework.

$(TYPEDSIGNATURES)

- `splits`: how many times to run the backtest for each step
- `seed`: random seed
- `method`: optimization method (defaults to BBO_adaptive_de_rand_1_bin())
- `maxiters`: maximum number of iterations
 - `maxtime`: maximum time budget for the optimization
- `kwargs`: The arguments to pass to the underlying Optimization.jl solve function.
- `parallel`: if true, enables parallel evaluation of multiple parameter combinations (default: false)
- `early_threshold`: if specified, terminates evaluation early if objective is below this threshold (default: -Inf)
- `max_failures`: maximum number of consecutive failures before stopping (default: Inf)

From within your strategy, define three `call!` functions:
- `call!(::Strategy, ::OptSetup)`: for the period of time to evaluate and the bounds for the optimization.
- `call!(::Strategy, params, ::OptRun)`: called before running the backtest, should apply the parameters to the strategy.

!!! warning
    For compatibility between optimization methods and solvers read [Optimization.jl](https://github.com/SciML/Optimization.jl) documentation carefully.
    Solvers that require auto differentiation might not work with your strategy.

## Examples

```julia
# Optimize all parameters
optimize(s)

# Exclude signal_lifetime and trade_cooldown from optimization
optimize(s)

# Exclude multiple parameters
optimize(s)
```
"""
function optimize(
    s::Strategy{Sim};
    seed=1,
    splits=1,
    resume=true,
    save_freq=nothing,
    zi=get_zinstance(s),
    maxiters=nothing,
    maxtime=nothing,
    opt_method=nothing,
    opt_method_kwargs=(;),
    solve_method=:bbo,
    solve_method_kwargs=(;),
    split_test=true,
    multistart=false,
    n_jobs=1,
    early_threshold=-Inf,
    max_failures=Inf,
    kwargs...,
)
    running!()
    Random.seed!(seed)

    local ctx, params, space, sess, callback
    try
        sess, ctx, params, space = _create_session_and_space(s; resume, zi)
    catch
        @debug_backtrace
        if isinteractive()
            let resp = Base.prompt(
                    "Can't resume the session. Continue? [y/n] (pass resume=false to skip this)",
                )
                if startswith(resp, "n")
                    return nothing
                end
            end
        end
        sess, ctx, params, space = _create_session_and_space(s; resume=false, zi)
    end

    save_args, from = _build_save_args(sess; save_freq, zi, resume)
    # record total slots (n_jobs * splits) to space out runs without collisions
    sess.attrs[:splits] = n_jobs * splits

    steps_args = ctxsteps(ctx, n_jobs * splits, call!(s, WarmupPeriod()))
    backtest_func = define_backtest_func(sess, steps_args...; verbose=true)
    obj_type, n_obj = objectives(s)

    if isnothing(opt_method)
        opt_method = default_opt_method(solve_method)
    end
    solve_method_instance = get_method(solve_method, solve_method_kwargs)
    opt_method_instance = get_method(opt_method, opt_method_kwargs)
    if isnothing(opt_method_instance) && requires_opt_method(solve_method)
        opt_method_instance = get_method(:automod, (;))
    end
    if n_obj > 1 && (solve_method_instance isa LBFGS)
        @warn "BFGS does not support multi-objective optimization. Switching to GA."
        solve_method_instance = get_method(:bbo, solve_method_kwargs)
    end

    _propagate_clone_attrs!(sess, s)
    # Define the optimization function for Optimization.jl
    opt_function = _make_opt_function(
        sess, s, backtest_func, n_obj, split_test && !multistart, splits, n_jobs, obj_type
    )

    # Prepare problem and helpers
    prob = _setup_problem_and_bounds(
        s, space, opt_function; opt_method_instance, solve_method_instance
    )

    # Configure parallel evaluation if requested
    # collect keyword arguments as a NamedTuple for splatting
    solve_kwargs = (; kwargs...)
    # Ensure iteration limits are honored across different solver backends
    # Some read :maxiters while others (e.g., Evolutionary/CMAES wrappers) read :iterations
    # Only add maxiters or maxtime if they are not nothing
    if maxiters !== nothing
        solve_kwargs = merge(solve_kwargs, (maxiters=maxiters,))
    end
    if maxtime !== nothing
        solve_kwargs = merge(solve_kwargs, (maxtime=maxtime,))
    end
    if n_jobs > 1 && !isthreadsafe(s)
        @warn "Parallel optimization requested but strategy is not thread-safe. Disabling parallel mode."
    end

    # Solve with Optimization.jl
    r = nothing
    try
        callback = _compose_callbacks(
            solve_method, save_args, early_threshold, max_failures
        )
        if multistart && n_jobs > 1
            r = _run_multi_start(
                sess,
                s,
                backtest_func;
                n_obj,
                n_jobs,
                solve_method_instance,
                opt_method_instance,
                callback,
                solve_kwargs,
            )
        else
            @info "optimize: running single optimization" n_params = length(sess.params) n_jobs maxiters maxtime = compact(
                Second(isnothing(maxtime) ? 0 : maxtime)
            ) s = nameof(s)
            r = _run_single(prob, solve_method_instance, callback, solve_kwargs)
        end
        @info "optimize: optimization complete"
        sess.best[] = r.u
        # Persist all results gathered during this run
        save_session(sess; from=from[], zi)
    catch e
        stopcall!()
        @error "optimize: optimization failed" exception = (e, catch_backtrace())
        save_session(sess; from=from[], zi)
        e isa InterruptException || showerror(stdout, e)
    end

    stopcall!()
    (sess, r)
end

get_value(p) =
    if hasproperty(p, :value)
        p.value
    elseif hasproperty(p, :val)
        p.val
    else
        p
    end

@doc """ Applies precision constraints to optimization parameters.

$(TYPEDSIGNATURES)

This function rounds parameters according to the precision specification stored in the strategy's attributes.
If no precision is specified, returns the parameters unchanged.
"""
function apply_precision(u, s::Strategy)
    if eltype(u) <: Symbolics.Num
        return u
    end
    precision = get(s, :opt_precision, nothing)
    categorical_info = get(s, :opt_categorical, nothing)

    if isnothing(precision) && isnothing(categorical_info)
        return u
    end

    u_rounded = [get_value(p) for p in u]

    # Get bounds for clamping
    bounds = get(s, :opt_bounds, nothing)

    # Apply precision constraints
    if !isnothing(precision)
        for (i, prec) in enumerate(precision)
            # Clamp to bounds first if available
            if !isnothing(bounds)
                lower, upper = bounds
                u[i] = clamp(u[i], lower[i], upper[i])
            end

            val = get_value(u[i])
            if prec >= 0
                # Round to specified number of decimal places
                u_rounded[i] = round(val; digits=prec)
            elseif prec == -1
                # Integer parameter
                u_rounded[i] = round(Int, val)
            end

            # Ensure rounded value is within bounds
            if !isnothing(bounds)
                lower, upper = bounds
                u_rounded[i] = clamp(u_rounded[i], lower[i], upper[i])
            end
        end
    end

    # Apply categorical constraints
    if !isnothing(categorical_info)
        for (i, categories) in enumerate(categorical_info)
            if !isnothing(categories)
                # Convert continuous value to categorical index
                val = get_value(u[i])
                cat_index = round(Int, clamp(val, 1, length(categories)))
                u_rounded[i] = cat_index
            end
        end
    end

    return u_rounded
end

@doc """ Checks if a strategy supports parallel optimization.

$(TYPEDSIGNATURES)

This function checks if the strategy has the THREADSAFE flag set to true.
"""
function supports_parallel(s::Strategy)
    isthreadsafe(s)
end

export optimize, @optimize, best_fitness, best_candidate, apply_precision, supports_parallel

"""
    @optimize strategy [options...]

Macro for optimizing strategy parameters using Optimization.jl framework.

# Arguments
- `strategy`: The strategy to optimize
- `options`: Optional keyword arguments for the optimization

# Examples
```julia
@optimize my_strategy maxiters=500
@optimize my_strategy method=BBO_adaptive_de_rand_1_bin() maxiters=1000
```
"""
macro optimize(strategy, args...)
    # Parse arguments
    kwargs = []
    for arg in args
        if arg isa Expr && arg.head == :(=)
            push!(kwargs, Expr(:kw, arg.args[1], arg.args[2]))
        else
            push!(kwargs, arg)
        end
    end

    # Create the function call
    if isempty(kwargs)
        return :(optimize($(esc(strategy))))
    else
        return :(optimize($(esc(strategy)); $(kwargs...)))
    end
end
