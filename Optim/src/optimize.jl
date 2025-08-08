using SimMode.TimeTicks: current!
using SimMode: start!
using Random
using SimMode.Lang: @debug_backtrace

# Add Optimization.jl imports
using Optimization
using OptimizationBBO
using OptimizationCMAEvolutionStrategy
using OptimizationEvolutionary
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
function ctxfromstrat(s; disabled_params=Symbol[])
    ctx, params, s_space = call!(s, OptSetup(); disabled_params)
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
        error("Wrong optimization parameters. Pass either bounds as (lower, upper) tuple, a function that returns bounds, or a NamedTuple with :bounds field.")
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

function opt_method(v)
    if v == :bbo
        BBO_adaptive_de_rand_1_bin()
    elseif v == :evo_cma
        CMAEvolutionStrategyOpt()
    elseif v == :evo_ga
        GA()
    elseif v == :evo_de
        DE()
    else
        v
    end
end

inc!(s::Strategy) = s[:strategy] += 1

#############################
# Internal helper functions #
#############################

# Session and space setup
function _create_session_and_space(s::Strategy{Sim}; disabled_params, resume::Bool, zi)
    ctx, params, s_space, space = ctxfromstrat(s; disabled_params)
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
            save_session(sess; from=from[], zi)
            from[] = nrow(sess.results) + 1
        end,
        CallbackInterval=Millisecond(save_freq).value / 1000.0,
    ), from
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
function _make_opt_function(sess::OptSession, s::Strategy, backtest_func, n_obj::Int)
    evaluation_cache = Dict{Vector{Float64}, Float64}()
    cache_lock = ReentrantLock()
    counter = (; lock = ReentrantLock(), n = Ref(0))

    function opt_function(u, p)
        u_rounded = apply_precision(u, s)
        @lock cache_lock begin
            if haskey(evaluation_cache, u_rounded)
                return evaluation_cache[u_rounded]
            end
        end
        thread_id = Threads.threadid()
        current_strategy = sess.s_clones[thread_id][2]
        call!(current_strategy, u_rounded, OptRun())
        this_n = counter.n[] + 1
        @lock counter.lock counter.n[] = this_n
        result = backtest_func(u_rounded, this_n)
        objective_value = n_obj == 1 ? result[1] : result
        @lock cache_lock evaluation_cache[u_rounded] = objective_value
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

# Build OptimizationProblem
function _build_problem(optf, initial_guess, lower_float, upper_float, integer_mask, maxiters)
    if any(integer_mask)
        return OptimizationProblem(
            optf, initial_guess; lb=lower_float, ub=upper_float, int=integer_mask, maxiters=maxiters,
        )
    else
        return OptimizationProblem(
            optf, initial_guess; lb=lower_float, ub=upper_float, maxiters=maxiters,
        )
    end
end

# Build early-termination callback
function _build_callback(solve_kwargs::Dict{Symbol,Any})
    early_termination_kwargs = Dict{Symbol, Any}()
    for (key, value) in solve_kwargs
        if key in [:early_termination_threshold, :max_consecutive_failures]
            early_termination_kwargs[key] = value
        end
    end
    if isempty(early_termination_kwargs)
        return nothing
    end
    return (u, p) -> begin
        threshold = get(early_termination_kwargs, :early_termination_threshold, -Inf)
        if p < threshold
            return true
        end
        return false
    end
end

# Single-job solve
function _run_single(prob, method, callback, solve_kwargs)
    if isnothing(callback)
        return solve(prob, method; solve_kwargs...)
    else
        return solve(prob, method; callback=callback, solve_kwargs...)
    end
end

# Multi-start concurrent solves
function _run_multi_start(optf, initial_guess, lower_float, upper_float, integer_mask, n_jobs::Int, method, callback, solve_kwargs, s::Strategy, maxiters)
    # Generate initial guesses (first is midpoint)
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

    # Problems per job
    probs = Vector{OptimizationProblem}(undef, n_jobs)
    for j in 1:n_jobs
        probs[j] = _build_problem(optf, initial_guesses[j], lower_float, upper_float, integer_mask, maxiters)
    end

    # Spawn tasks
    tasks = Vector{Task}(undef, n_jobs)
    for j in 1:n_jobs
        if isnothing(callback)
            tasks[j] = Threads.@spawn solve(probs[j], method; solve_kwargs...)
        else
            tasks[j] = Threads.@spawn solve(probs[j], method; callback=callback, solve_kwargs...)
        end
    end
    solutions = map(fetch, tasks)
    best_idx = argmin([sol.objective isa Number ? sol.objective : sol.objective[1] for sol in solutions])
    return solutions[best_idx]
end

#############################
# Internal helper functions #
#############################

# Session and space setup
function _create_session_and_space(s::Strategy{Sim}; disabled_params, resume::Bool, zi)
    ctx, params, s_space, space = ctxfromstrat(s; disabled_params)
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
            save_session(sess; from=from[], zi)
            from[] = nrow(sess.results) + 1
        end,
        CallbackInterval=Millisecond(save_freq).value / 1000.0,
    ), from
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
function _make_opt_function(sess::OptSession, s::Strategy, backtest_func, n_obj::Int)
    evaluation_cache = Dict{Vector{Float64}, Float64}()
    cache_lock = ReentrantLock()
    counter = (; lock = ReentrantLock(), n = Ref(0))

    function opt_function(u, p)
        u_rounded = apply_precision(u, s)
        @lock cache_lock begin
            if haskey(evaluation_cache, u_rounded)
                return evaluation_cache[u_rounded]
            end
        end
        thread_id = Threads.threadid()
        current_strategy = sess.s_clones[thread_id][2]
        call!(current_strategy, u_rounded, OptRun())
        this_n = counter.n[] + 1
        @lock counter.lock counter.n[] = this_n
        result = backtest_func(u_rounded, this_n)
        objective_value = n_obj == 1 ? result[1] : result
        @lock cache_lock evaluation_cache[u_rounded] = objective_value
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

# Build OptimizationProblem
function _build_problem(optf, initial_guess, lower_float, upper_float, integer_mask, maxiters)
    if any(integer_mask)
        return OptimizationProblem(
            optf, initial_guess; lb=lower_float, ub=upper_float, int=integer_mask, maxiters=maxiters,
        )
    else
        return OptimizationProblem(
            optf, initial_guess; lb=lower_float, ub=upper_float, maxiters=maxiters,
        )
    end
end

# Build early-termination callback
function _build_callback(solve_kwargs::Dict{Symbol,Any})
    early_termination_kwargs = Dict{Symbol, Any}()
    for (key, value) in solve_kwargs
        if key in [:early_termination_threshold, :max_consecutive_failures]
            early_termination_kwargs[key] = value
        end
    end
    if isempty(early_termination_kwargs)
        return nothing
    end
    return (u, p) -> begin
        threshold = get(early_termination_kwargs, :early_termination_threshold, -Inf)
        if p < threshold
            return true
        end
        return false
    end
end

# Single-job solve
function _run_single(prob, method, callback, solve_kwargs)
    if isnothing(callback)
        return solve(prob, method; solve_kwargs...)
    else
        return solve(prob, method; callback=callback, solve_kwargs...)
    end
end

# Multi-start concurrent solves
function _run_multi_start(optf, initial_guess, lower_float, upper_float, integer_mask, n_jobs::Int, method, callback, solve_kwargs, s::Strategy, maxiters)
    # Generate initial guesses (first is midpoint)
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

    # Problems per job
    probs = Vector{OptimizationProblem}(undef, n_jobs)
    for j in 1:n_jobs
        probs[j] = _build_problem(optf, initial_guesses[j], lower_float, upper_float, integer_mask, maxiters)
    end

    # Spawn tasks
    tasks = Vector{Task}(undef, n_jobs)
    for j in 1:n_jobs
        if isnothing(callback)
            tasks[j] = Threads.@spawn solve(probs[j], method; solve_kwargs...)
        else
            tasks[j] = Threads.@spawn solve(probs[j], method; callback=callback, solve_kwargs...)
        end
    end
    solutions = map(fetch, tasks)
    best_idx = argmin([sol.objective isa Number ? sol.objective : sol.objective[1] for sol in solutions])
    return solutions[best_idx]
end

@doc """ Optimize parameters using the Optimization.jl framework.

$(TYPEDSIGNATURES)

- `splits`: how many times to run the backtest for each step
- `seed`: random seed
- `method`: optimization method (defaults to BBO_adaptive_de_rand_1_bin())
- `maxiters`: maximum number of iterations
- `kwargs`: The arguments to pass to the underlying Optimization.jl solve function.
- `parallel`: if true, enables parallel evaluation of multiple parameter combinations (default: false)
- `early_termination_threshold`: if specified, terminates evaluation early if objective is below this threshold
- `disabled_params`: array of parameter symbols to exclude from optimization (e.g., `[:signal_lifetime, :trade_cooldown]`)

From within your strategy, define three `call!` functions:
- `call!(::Strategy, ::OptSetup)`: for the period of time to evaluate and the bounds for the optimization.
- `call!(::Strategy, params, ::OptRun)`: called before running the backtest, should apply the parameters to the strategy.

## Examples

```julia
# Optimize all parameters
optimize(s)

# Exclude signal_lifetime and trade_cooldown from optimization
optimize(s; disabled_params=[:signal_lifetime, :trade_cooldown])

# Exclude multiple parameters
optimize(s; disabled_params=[:buy_trigger, :sell_trigger, :ordertype])
```
"""
function optimize(
    s::Strategy{Sim};
    seed=1,
    splits=1,
    resume=true,
    save_freq=nothing,
    zi=get_zinstance(s),
    method=:evo_ga,
    maxiters=1000,
    n_jobs=1,
    disabled_params=Symbol[],
    kwargs...,
)
    running!()
    Random.seed!(seed)
    method = opt_method(method)
    
    local ctx, params, s_space, space, sess, callback
    try
        sess, ctx, params, space = _create_session_and_space(s; disabled_params, resume, zi)
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
        sess, ctx, params, space = _create_session_and_space(s; disabled_params, resume=false, zi)
    end
    
    save_args, from = _build_save_args(sess; save_freq, zi, resume)
    
    backtest_func = define_backtest_func(sess, ctxsteps(ctx, splits)...)
    obj_type, n_obj = objectives(s)
    _propagate_clone_attrs!(sess, s)
    
    # Define the optimization function for Optimization.jl
    opt_function = _make_opt_function(sess, s, backtest_func, n_obj)
    
    # Get bounds from the strategy setup
    lower, upper = _bounds_from_space(space)
    
    # Store bounds for later use in parameter clamping
    s[:opt_bounds] = (copy(lower), copy(upper))
    
    # Ensure bounds are Float64 arrays for Optimization.jl compatibility
    lower_float = lower  # Already Float64 from lowerupper function
    upper_float = upper  # Already Float64 from lowerupper function
    
    # Create OptimizationProblem
    optf = OptimizationFunction(opt_function, Optimization.AutoForwardDiff())
    # Use the midpoint of bounds as initial guess
    initial_guess = (lower_float .+ upper_float) ./ 2.0
    
    # Check if we have integer parameters
    precision = get(s, :opt_precision, nothing)
    integer_mask = if !isnothing(precision)
        [prec == -1 for prec in precision]
    else
        falses(length(lower_float))
    end
    
    # Create problem with integer constraints if needed
    prob = _build_problem(optf, initial_guess, lower_float, upper_float, integer_mask, maxiters)
    
    # Configure parallel evaluation if requested
    solve_kwargs = Dict{Symbol, Any}(kwargs...)
    if n_jobs > 1 && !isthreadsafe(s)
        @warn "Parallel optimization requested but strategy is not thread-safe. Disabling parallel mode."
    end
    
    # Solve with Optimization.jl
    r = nothing
    try
        # Create callback for early termination
        callback = _build_callback(solve_kwargs)

        if n_jobs > 1 && isthreadsafe(s)
            r = _run_multi_start(optf, initial_guess, lower_float, upper_float, integer_mask, n_jobs, method, callback, solve_kwargs, s, maxiters)
        else
            r = _run_single(prob, method, callback, solve_kwargs)
        end
        sess.best[] = r.u
    catch e
        stopcall!()
        Base.show_backtrace(stdout, catch_backtrace())
        save_session(sess; from=from[], zi)
        e isa InterruptException || showerror(stdout, e)
    end
    
    stopcall!()
    (sess, r)
end

@doc """ Applies precision constraints to optimization parameters.

$(TYPEDSIGNATURES)

This function rounds parameters according to the precision specification stored in the strategy's attributes.
If no precision is specified, returns the parameters unchanged.
"""
function apply_precision(u, s::Strategy)
    precision = get(s, :opt_precision, nothing)
    categorical_info = get(s, :opt_categorical, nothing)
    
    if isnothing(precision) && isnothing(categorical_info)
        return u
    end
    
    u_rounded = copy(u)
    
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
            
            if prec >= 0
                # Round to specified number of decimal places
                u_rounded[i] = round(u[i], digits=prec)
            elseif prec == -1
                # Integer parameter
                u_rounded[i] = round(Int, u[i])
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
                cat_index = round(Int, clamp(u[i], 1, length(categories)))
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
