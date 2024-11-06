module VindictaInteractive

using Pkg: Pkg

if isdefined(Main, :Vindicta) && Main.Vindicta isa Module
    error(
        """Can't load VindictaInteractive because Vindicta has already been loaded.
  Restart the repl and run `Pkg.activate("VindictaInteractive"); using VindictaInteractive;`
  """
    )
end

let this_proj = Symbol(Pkg.project().name), vdni_proj = nameof(@__MODULE__)
    if this_proj != vdni_proj
        error(
            "VindictaInteractive should only be loaded after activating it's project dir. ",
            this_proj,
            " ",
            vdni_proj,
        )
    end
end

using Vindicta
using WGLMakie
using Plotting
using Optimization
using Watchers
using Scrapers

export Plotting, Optimization, Watchers, Scrapers

end # module IVindicta
