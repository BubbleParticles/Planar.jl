@doc "Watchers are data feeds, that keep track of stale data."
module Watchers

    include("module.jl")

    if get(ENV, "JULIA_PRECOMP", "") == "true"
        include("precompile.jl")
    end

end
