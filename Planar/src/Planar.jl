module Planar
    include("submodules/PaperMode.jl")
    include("submodules/LiveMode.jl")
    include("submodules/Remote.jl")
    include("submodules/Engine.jl")

    # Re-exports for backward compat
    include("repl.jl")
    include("strat.jl")
    include("dev.jl")
    include("user.jl")

    _activate_and_import(args...) = begin
        # placeholder
    end
end
