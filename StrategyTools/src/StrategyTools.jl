module StrategyTools

let entry_path = joinpath(@__DIR__, "module.jl")
    include(entry_path)
    if occursin(string(@__MODULE__), get(ENV, "JULIA_PRECOMP", ""))
        include("precompile.jl")
    end
end

end # module StrategyTools
