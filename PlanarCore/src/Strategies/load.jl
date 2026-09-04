using ..Data.Cache: save_cache, load_cache
using ..Collections: snapshot
using ..Instances: raw, InstrumentInstance
using ..Instances.Instruments: AbstractInstrument, parse as parse_instrument
using ..Instances.DataStructures: SortedDict
using ..Instances.Data.TimeTicks: TimeFrame
using ..Instances.Data.DataFrames: DataFrame
using ..Misc: user_dir, config_path
using ..Misc.Lang: @debug_backtrace
using TOML
using JSON3

function _universe_members(cfg::Config)
    try
        if haskey(cfg.attrs, "universe")
            u = cfg.attrs["universe"]
            if u isa AbstractDict && haskey(u, "members")
                m = u["members"]
                # an explicitly-empty members list is treated as "no override"
                # so `StrategyMarkets()` remains the source of truth
                m isa Vector && !isempty(m) && return String.(m)
            elseif u isa Vector
                !isempty(u) && return String.(u)
            end
        end
        if !isnothing(cfg.toml) && haskey(cfg.toml, "universe")
            u = cfg.toml["universe"]
            if u isa AbstractDict && haskey(u, "members")
                m = u["members"]
                m isa Vector && !isempty(m) && return String.(m)
            end
        end
    catch e
        @debug "universe_members: parse failed" exception=(e, catch_backtrace())
    end
    return nothing
end


@doc """ Raises an error when a strategy is not found at a given path.  """
macro notfound(path)
    quote
        error("Strategy not found at $($(esc(path)))")
    end
end

@doc """ Finds the path of a given file.

$(TYPEDSIGNATURES)

The `find_path` function checks various locations to find the path of a given file.
It checks the current working directory, user directory, configuration directory, and project directory.
If the file is not found, it raises an error.
"""
function find_path(file, cfg)
    if !ispath(file)
        if isabspath(file)
            @notfound file
        else
            from_pwd = joinpath(pwd(), file)
            ispath(from_pwd) && return from_pwd
            from_user = joinpath(user_dir(), file)
            ispath(from_user) && return from_user
            from_cfg = joinpath(dirname(cfg.path), file)
            ispath(from_cfg) && return from_cfg
            from_proj = joinpath(dirname(Pkg.project().path), file)
            ispath(from_proj) && return from_proj
            @notfound file
        end
    end
    realpath(file)
end

@doc """ Retrieves the source file for a strategy without a project.

The `_include_projectless` function retrieves the source file for a strategy that does not have a project.
It checks the `sources` attribute of the strategy's configuration.
"""
_include_projectless(src, attrs) =
    if !isnothing(attrs)
        let sources = get(attrs, "sources", nothing)
            if !isnothing(sources)
                get(sources, string(src), nothing)
            end
        end
    end
_include_project(attrs) = get(attrs, "include_file", nothing)

@doc """ Determines the file path for a strategy source.

$(TYPEDSIGNATURES)

This function determines the file path for a strategy source based on whether it is a project or not.
If it is a project, it constructs the file path relative to the configuration path.
If it is not a project, it retrieves the source file from the strategy's configuration or defaults to a predefined path.
In case the file path is not found, it throws an `ArgumentError` with a detailed message.
"""
function _file(src, cfg, is_project)
    file = if is_project
        file = joinpath(dirname(realpath(cfg.path)), "src", string(src, ".jl"))
        if ispath(file)
            file
        else
        end
    else
        let f = _include_project(cfg.attrs); f === nothing ? _include_projectless(src, cfg.toml) : f; end
    end
    if isnothing(file)
        file = get(cfg.sources, src, nothing)
        if isnothing(file)
            return nothing
        end
    end
    file
end

@doc """ Determines the margin mode of a module.

$(TYPEDSIGNATURES)

This function attempts to determine the margin mode of a given module.
It first tries to access the `S` property of the module to get the margin mode.
If this fails, it then tries to access the `SC` property of the module.
"""
function _defined_marginmode(mod)
    if isdefined(mod, :S)
        S = invokelatest(getfield, mod, :S)
        # Handle both concrete types and UnionAll (parametric) type aliases
        if S isa Type{<:Strategy}
            return marginmode(S)
        elseif S isa UnionAll
            # For parametric type alias like S{M}, the margin mode is in the DataType body
            body = S.body
            while body isa UnionAll
                body = body.body
            end
            if body isa DataType && body.name.wrapper == Strategy
                mm_type = body.parameters[4]  # MarginMode is 4th parameter of Strategy
                return mm_type()  # Return instance, not type
            end
        end
    end
    if isdefined(mod, :SC)
        SC = invokelatest(getfield, mod, :SC)
        if SC isa Type{<:Strategy}
            return marginmode(SC)
        elseif SC isa UnionAll
            body = SC.body
            while body isa UnionAll
                body = body.body
            end
            if body isa DataType && body.name.wrapper == Strategy
                mm_type = body.parameters[4]
                return mm_type()
            end
        end
    end
    error("Strategy module $mod does not define S or SC margin mode")
end

@doc """ Performs checks on a loaded strategy.

$(TYPEDSIGNATURES)

This function performs checks on a loaded strategy.
It asserts that the margin mode and execution mode of the strategy match the configuration.
It also sets the `verbose` property of the strategy to `false`.
"""
_strat_load_checks(s::Strategy, config::Config) = begin
    @assert marginmode(s) == config.margin
    @assert execmode(s) == config.mode
    @assert account(s) == config.account
    s[:verbose] = false
    s
end

@doc """ Loads a strategy with default settings.

$(TYPEDSIGNATURES)

This function loads a strategy with default settings.
It invokes the `call!` function of the module with the strategy type and `StrategyMarkets()`.
It then creates a new `Strategy` instance with the module, assets, and configuration.
The `sandbox` property is set based on the mode of the configuration.
Finally, it performs checks on the loaded strategy.
"""
function default_load(mod::Module, t::Type, config::Config)
    call_func = if isdefined(mod, :call!)
        invokelatest(getfield, mod, :call!)
    else
        call!
    end
    assets = @something _universe_members(config) invokelatest(call_func, t, StrategyMarkets())
    # Sandbox must stay an explicit user choice (keys, exchange selection and
    # margin-mode support checks all depend on it). Forcing it here silently
    # swaps the exchange object under strategies that set `sandbox=false`
    # (e.g. ExampleMargin via `SANDBOX[] = config.sandbox`), breaking live
    # margin-mode validation. Warn on a suspicious Paper+sandbox=false combo
    # (the inner constructor already warns the inverse) instead of mutating.
    if config.mode == Paper() && !config.sandbox
        @warn "Paper mode usually runs against a sandbox exchange; config.sandbox=false keeps live keys and endpoints."
    end
    s = Strategy(mod, assets; config)
    _strat_load_checks(s, config)
end


@doc """ Loads a strategy without default settings.

$(TYPEDSIGNATURES)

This function loads a strategy without default settings.
It invokes the `call!` function of the module with the strategy type and `StrategyMarkets()`.
It then creates a new `Strategy` instance with the module, assets, and configuration.
The `sandbox` property is set based on the mode of the configuration.
Finally, it performs checks on the loaded strategy.
"""
function bare_load(mod::Module, t::Type, config::Config)
    call_func = if isdefined(mod, :call!)
        invokelatest(getfield, mod, :call!)
    else
        call!
    end
    syms = @something _universe_members(config) invokelatest(call_func, t, StrategyMarkets())
    exc = Exchanges.getexchange!(config.exchange; sandbox=config.sandbox, config.account)
    TF = invokelatest(getfield, mod, :TF)
    uni = InstrumentCollection(syms; load_data=false, timeframe=TF, exc, config.margin)
    s = Strategy(mod, config.mode, config.margin, TF, exc, uni; config)
    _strat_load_checks(s, config)
end

@doc """ Loads a strategy from a symbol source.

$(TYPEDSIGNATURES)

This function loads a strategy from a given symbol source.
It first determines the file path for the strategy source and checks if it is a project.
If it is a project, it activates and instantiates the project.
The function then includes the source file and uses it.
If the source file is not defined in the parent module, it is evaluated and tracked for changes.
Finally, the function returns the loaded strategy.
"""
function strategy!(src::Symbol, cfg::Config)
    # --- Built-in BareStrat (preserved single-file path) ---
    if src == :BareStrat
        file = joinpath(user_dir(), "strategies", "BareStrat.jl")
        isproject = false
        project_file = nothing
        prev_proj = Base.active_project()
        path = find_path(file, cfg)
        parent = get(cfg.attrs, :parent_module, Strategies)
        @assert parent isa Module
        mod = if !isdefined(parent, src)
            try
                @eval parent begin
                    include($(path))
                    using .$(src)
                    $(src)
                end
            catch e
                @error "strategy loading: failed to load BareStrat" exception=(e, catch_backtrace())
                return nothing
            end
        else
            @eval parent $(src)
        end
        isnothing(mod) && return nothing
        return strategy!(mod, cfg)
    end

    # --- Project-based strategies only ---
    file = _file(src, cfg, false)
    if isnothing(file)
        # A strategy project under `user/strategies/$src` can be loaded without an
        # explicit `[sources]` entry: register it on the fly and proceed.
        if _register_present_strategy!(src, cfg)
            file = _file(src, cfg, false)
        else
            error("Strategy `$src` not found. Add it under `[sources]` in `user/planar.toml`.")
        end
    end
    if splitext(file)[2] != ".toml"
        error("Strategy `$src` at `$file` is not a project-based strategy. " *
              "Single-file .jl strategies are no longer supported. " *
              "Create a project at `user/strategies/$src/` with a Project.toml " *
              "and add it under `[sources]` in `user/planar.toml`.")
    end
    project_file = find_path(file, cfg)
    path = find_path(file, cfg)
    name = string(src)
    Misc.config!(name; cfg, path, check=false)
    file = _file(src, cfg, true)  # resolve .jl source within the project
    path = find_path(file, cfg)  # resolve .jl source path for include

    prev_proj = Base.active_project()
    parent = get(cfg.attrs, :parent_module, Main)
    @assert parent isa Module

    mod = if !isdefined(parent, src)
        @eval parent begin
            try
                $Pkg.activate($(project_file); io=Base.devnull)
                try
                    $Pkg.instantiate(; io=Base.devnull)
                catch e
                    @warn "loading: instantiation failed, will try direct include" exception = e
                end
                include($(path))
                using .$(src)
                if isinteractive() && isdefined(Main, :Revise)
                    try
                        Main.Revise.track($(src), $(path))
                    catch e
                        @warn "strategy: Revise tracking failed" _module=$(src) exception=e
                    end
                end
                $(src)
            catch e
                @error "strategy loading: failed to load module" _module=$(src) exception=(e, catch_backtrace())
                rethrow(e)
            finally
                $Pkg.activate($(prev_proj); io=Base.devnull)
            end
        end
    else
        @eval parent $(src)
    end
    isnothing(mod) && return nothing
    strategy!(mod, cfg)
end
_concrete(type, param) = isconcretetype(type) ? type : type{param}
@doc """ Determines the strategy type of a module.

$(TYPEDSIGNATURES)

This function determines the strategy type of a given module.
It first tries to access the `S` property of the module to get the strategy type.
If this fails, it then tries to access the `SC` property of the module.
The function also checks if the exchange is specified in the strategy or in the configuration.
"""
function _strategy_type(mod, cfg)
    S = if isdefined(mod, :S)
        invokelatest(getfield, mod, :S)
    end
    E = if isdefined(mod, :EXCID)
        invokelatest(getfield, mod, :EXCID)
    end
    s_type =
        if S !== nothing &&
            S isa Type{<:Strategy} &&
            exchangeid(S) == exchangeid(cfg.exchange)
            S
        else
            if cfg.exchange == Symbol()
                if E !== nothing && E !== Symbol()
                    cfg.exchange = E
                elseif S !== nothing
                    cfg.exchange = exchangeid(S)
                else
                    error(
                        "loading: exchange not specified (neither in strategy nor in config)",
                    )
                end
            end
            try
                if E !== nothing && E !== cfg.exchange
                    @warn "loading: overriding default exchange with config" E cfg.exchange
                end
                invokelatest(getfield, mod, :SC){ExchangeID{cfg.exchange}}
            catch
                error(
                    "loading: strategy main type `S` or `SC` not defined in strategy module.",
                )
            end
        end
    mode_type = s_type{typeof(cfg.mode)}
    margin_type = _concrete(mode_type, typeof(cfg.margin))
    _concrete(margin_type, typeof(cfg.qc))
end
@doc """ Loads a strategy from a module.

$(TYPEDSIGNATURES)

This function loads a strategy from a given module.
It first checks and sets the mode and margin of the configuration if they are not set.
It then determines the strategy type of the module and checks if the exchange is specified in the strategy or in the configuration.
Finally, it tries to load the strategy with default settings, if it fails, it loads the strategy without default settings.
"""
function strategy!(mod::Module, cfg::Config)
    if isnothing(cfg.mode)
        cfg.mode = Sim()
    end
    def_mm = _defined_marginmode(mod)
    if isnothing(cfg.margin)
        cfg.margin = def_mm
    elseif def_mm != cfg.margin
        # The strategy object's margin type param `M` is authoritative for all
        # local dispatch (`singlewaycheck`, `positions!`, `isopen`, ...), and
        # `_strat_load_checks` asserts `marginmode(s) == config.margin`. A
        # mismatch would only fail at load time, so reconcile here: adopt the
        # strategy-defined mode and warn loudly instead of proceeding into a
        # guaranteed assertion failure.
        @warn "Mismatching margin mode — adopting strategy-defined mode" config = cfg.margin strategy = def_mm
        cfg.margin = def_mm
    end
    s_type = _strategy_type(mod, cfg)
    strat_exc = Symbol(exchangeid(s_type))
    # The strategy can have a default exchange symbol
    if cfg.exchange == Symbol()
        cfg.exchange = strat_exc
        if strat_exc == Symbol()
            @warn "Strategy exchange unset"
        end
    end
    if cfg.min_timeframe == tf"0s" # any zero tf should match
        cfg.min_timeframe = tf"1m" # default to 1 minute timeframe
        tfs = cfg.timeframes
        sort!(tfs)
        idx = searchsortedfirst(tfs, tf"1m")
        if length(tfs) < idx || tfs[idx] != tf"1m"
            insert!(tfs, idx, tf"1m")
        end
    end
    @assert nameof(s_type) isa Symbol "Source $src does not define a strategy name."
    call_func = if isdefined(mod, :call!)
        invokelatest(getfield, mod, :call!)
    else
        call!
    end
    s = @something invokelatest(call_func, s_type, cfg, LoadStrategy()) try
        default_load(mod, s_type, cfg)
    catch e
        @error "strategy loading: default_load failed, falling back to bare_load" exception=(e, catch_backtrace())
        bare_load(mod, s_type, cfg)
    end
    # ensure strategy is stopped on process termination is paper or live
    if cfg.mode in (Paper(), Live())
        atexit(() -> stop!(s))
    end
    # auto-restore persisted universe if present and not overridden by config
    try
        upath = logpath(s; name="universe.json")
        if isfile(upath)
            cfg_members = _universe_members(cfg)
            persist_flag = get(cfg.attrs, "persist_universe", get(cfg.attrs, :persist_universe, false))
            # string/symbol key tolerance
            if persist_flag === true || persist_flag === "true"
                load_universe!(s, upath)
            elseif cfg_members === nothing
                # no explicit config members → restore persisted (kill-and-resume)
                load_universe!(s, upath)
            end
        end
    catch e
        @debug "auto load_universe! failed" exception=(e, catch_backtrace())
    end
    return s
end

@doc """ Returns the path to the strategy cache.

$(TYPEDSIGNATURES)

This function returns the path to the strategy cache.
It checks if the path exists and creates it if it doesn't.
"""
function strategy_cache_path()
    cache_path = user_dir()
    @assert ispath(cache_path) "Can't load strategy state, no directory at $cache_path"
    cache_path = joinpath(cache_path, "cache")
    mkpath(cache_path)
    cache_path
end

@doc """ Determines the configuration for a strategy.

$(TYPEDSIGNATURES)

This function determines the configuration for a strategy based on the source and path.
If the strategy is to be loaded, it attempts to load the strategy cache.
If the cache does not exist or is not a valid configuration, it creates a new configuration.
"""
function _strategy_config(src, path; load, config_args...)
    if load
        cache_path = strategy_cache_path()
        cfg = load_cache(string(src); raise=false, cache_path)
        if !(cfg isa Config)
            @warn "Strategy state ($src) not found at $cache_path"
            Config(src, path; config_args...)
        else
            cfg
        end
    else
        Config(src, path; config_args...)
    end
end

@doc """ Loads a strategy from a source, module, or string.

$(TYPEDSIGNATURES)

This function loads a strategy from a given source, module, or string.
It first determines the configuration for the strategy based on the source and path.
If the strategy is to be loaded, it attempts to load the strategy cache.
Finally, it returns the loaded strategy.
"""
function strategy(
    src::Union{Symbol,Module,String}, path::String=config_path(); load=false, config_args...
)
    cfg = _strategy_config(src, path; load, config_args...)
    strategy(src, cfg; save=load)
end

function strategy(src::Union{Symbol,Module,String}, cfg::Config; save=false)
    s = strategy!(src, cfg)
    save && save_strategy(s)
    s
end

@doc """ Returns the default strategy (`BareStrat`). """
strategy(; kwargs...) = strategy(:BareStrat; parent_module=Strategies, kwargs...)

@doc """ Returns a strategy by name, defaulting to parent_module=Planar for non-BareStrat strategies. """
function strategy(name::Symbol; parent_module=nothing, kwargs...)
    if parent_module === nothing
        parent_module = if name === :BareStrat
            Strategies
        elseif isdefined(Main, :Planar)
            getproperty(Main, :Planar)
        else
            error("Planar is not defined in Main. Please `using Planar` first.")
        end
    end
    return strategy(name, config_path(); parent_module=parent_module, kwargs...)
end

@doc """ Saves the state of a strategy.

$(TYPEDSIGNATURES)

This function saves the state of a given strategy.
It determines the cache path and saves the strategy state to this path.
"""
function save_strategy(s)
    cache_path = @lget! attrs(s) :config_cache_path strategy_cache_path()
    save_cache(string(nameof(s)); raise=false, cache_path)
end

@doc """ Checks for inverse contracts in an exchange.

$(TYPEDSIGNATURES)

This function checks for the presence of inverse contracts in a given exchange.
If any inverse contracts are found, it asserts an error.
"""
function _no_inv_contracts(exc::Exchange, uni)
    for ii in uni
        sym = raw(ii)
        mkt = get(exc.markets, string(sym), nothing)
        # unknown market (e.g. mock exchanges in tests): skip rather than KeyError
        isnothing(mkt) && continue
        @assert something(get(mkt, "linear", true), true) "Inverse contracts are not supported by SimMode. $(sym)"
    end
end

#= Registers a strategy project found under `user/strategies/$src` by appending a
`[sources]` entry to `planar.toml` (the file at `cfg.path`) and updating `cfg.sources`.

Returns `true` if the strategy project exists and was registered, `false` otherwise. =#
function _register_present_strategy!(src::Symbol, cfg::Config)
    rel = "strategies/$src/Project.toml"
    candidates = (
        rel,
        joinpath(pwd(), rel),
        joinpath(user_dir(), rel),
        joinpath(dirname(realpath(cfg.path)), rel),
    )
    any(isfile, candidates) || return false
    cfg.sources[src] = rel
    user_config = TOML.parsefile(cfg.path)
    sources = @lget! user_config "sources" Dict{String,Any}()
    key = string(src)
    if key ∉ keys(sources)
        sources[key] = rel
        open(cfg.path, "w") do f
            TOML.print(f, SortedDict(user_config))
        end
        @info "Registered strategy `$src` under [sources] in $(cfg.path)"
    end
    return true
end

function save_universe!(s::Strategy, path=logpath(s; name="universe.json"))
    try
        ver = get(attrs(s), :universe_version, 0)
        members = [string(raw(ii)) for ii in snapshot(universe(s))]
        data = Dict("version" => ver, "members" => members)
        mkpath(dirname(path))
        open(path, "w") do io
            JSON3.write(io, data)
        end
        @info "save_universe!: saved" path ver members
    catch e
        @warn "save_universe! failed" exception=(e, catch_backtrace())
    end
    return path
end

function load_universe!(s::Strategy, path=logpath(s; name="universe.json"))
    isfile(path) || return nothing
    try
        data = open(path, "r") do io
            JSON3.read(io, Dict{String,Any})
        end
        ver = get(data, "version", 0)
        members = get(data, "members", String[])
        # Prefer exchange already in universe to avoid gateway lookup for mock :test
        exc = try
            snap = snapshot(universe(s))
            !isempty(snap) ? first(snap).exchange : exchange(s)
        catch
            try exchange(s) catch; first(snapshot(universe(s))).exchange end
        end
        new_instances = InstrumentInstance[]
        for sym in members
            try
                a = parse_instrument(AbstractInstrument, string(sym))
                ii = InstrumentInstance(a; data=SortedDict{TimeFrame, DataFrame}(), exc, margin=s.margin)
                push!(new_instances, ii)
            catch e
                @warn "load_universe!: failed to resolve" sym exception=(e, catch_backtrace())
            end
        end
        replace_universe!(s, new_instances)
        attrs(s)[:universe_version] = ver
        @info "load_universe!: loaded" path ver members
        return s
    catch e
        @warn "load_universe! failed" exception=(e, catch_backtrace())
        return nothing
    end
end
