using Pkg: Pkg as Pkg

macro in_repl()
    quote
        @eval begin
            Misc.clearpypath!()
            sst = PlanarStrategyStats
            using PlanarOptim.Plotting: plotone, @plotone
            using Misc: config, @margin!, @margin!!
        end
        exc = setexchange!(:kucoin)
    end
end

function analyze!()
    @eval using PlanarStrategyStats, PlanarOptim.Plotting
end

function user!()
    @eval include(joinpath(@__DIR__, "user.jl"))
    @eval using Misc: config
    @eval export results, exc, config
    @eval sst = PlanarStrategyStats
    nothing
end

@doc """ Binds a module to a symbol in the Main namespace.

$(TYPEDSIGNATURES)

This function attempts to bind a module to a symbol in the Main namespace.
If the module is not already defined, it tries to activate the module's project and import it.
"""
function module!(sym, bind)
    if !isdefined(Main, bind)
        projpath = dirname(dirname(pathof(Planar)))
        modpath = joinpath(projpath, string(sym, ".jl"))
        try
            @eval Main using $sym: $sym as $bind
        catch e
            Base.showerror(stdout, e)
            prev = Pkg.project().path
            Pkg.activate(modpath)
            try
                @eval Main using $sym: $sym as $bind
            finally
                Pkg.activate(prev)
            end
        end
    end
    @info "`$sym` module bound to `$bind`"
end

# NOTE: required to register extensions hooks
@doc """ Activates and imports a given module.

$(TYPEDSIGNATURES)

This function activates the project of a given module and imports it.
It binds the module to a symbol in the Main namespace.
If the module is not already defined, it tries to activate the module's project and import it.
"""
function _activate_and_import(name, bind)
    proj_name = string(name)
    # For PlanarFeatureSelection and other packages in the Planar.jl monorepo, look in parent dir of Planar.jl
    base_dir = dirname(dirname(dirname(pathof(Planar))))  # /Planar.jl
    proj_path = isfile(joinpath(proj_name, "Project.toml")) ? proj_name : joinpath(base_dir, proj_name)
    @assert isfile(joinpath(proj_path, "Project.toml"))
    prev = Base.active_project()
    Pkg.activate(proj_path, io=devnull)
    try
        module!(Symbol(name), Symbol(bind))
    finally
        Pkg.activate(prev, io=devnull)
    end
end

@doc """ Imports the `Metrics` module. """
metrics!() = module!(:Metrics, :ss)
@doc """ Imports the `PlanarStrategyStats` module. """
analysis!() = module!(:PlanarStrategyStats, :sst)
@doc """ Activates and Imports the `PlanarOptim` module. """
optim!() = _activate_and_import(:PlanarOptim, :opt)
@doc """ Activates and Imports the `PlanarOptim` module (formerly PlanarInteractive). """
interactive!() = _activate_and_import(:PlanarOptim, :plni)
@doc """ Activates and Imports the `PlanarDownloadTool` module. """
scrape!() = _activate_and_import(:PlanarDownloadTool, :scr)
feats!() = _activate_and_import(:PlanarFeatureSelection, :feats)

export optim!, metrics!, analysis!, interactive!, scrape!, feats!
