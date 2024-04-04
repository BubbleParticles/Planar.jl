module Optimization

if get(ENV, "JULIA_NOPRECOMP", "") == "all"
    __init__() = begin
        @eval include(joinpath(@__DIR__, "optimization.jl"))
    end
else
    occursin(string(@__MODULE__), get(ENV, "JULIA_NOPRECOMP", "")) && __precompile__(false)
    include("module.jl")
    if occursin(string(@__MODULE__), get(ENV, "JULIA_PRECOMP", ""))
        include("precompile.jl")
    end
end

end # module Plotting
