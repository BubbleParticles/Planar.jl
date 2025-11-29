module PlanarInteractive

using Pkg: Pkg

if isdefined(Main, :Planar) && Main.Planar isa Module
    error(
        """Can't load PlanarInteractive because Planar has already been loaded.
  Restart the repl and run `Pkg.activate("PlanarInteractive"); using PlanarInteractive;`
  """
    )
end

let this_proj = Symbol(Pkg.project().name), plni_proj = nameof(@__MODULE__)
    if this_proj != plni_proj
        error(
            "PlanarInteractive should only be loaded after activating it's project dir. ",
            this_proj,
            " ",
            plni_proj,
        )
    end
end

using Planar
using WGLMakie
using Plotting
using Opt
using Watchers
using Scrapers

export Plotting, Opt, Watchers, Scrapers

end # module IPlanar
