@doc """ Module for data resampling, cleaning, aligning, etc.

"""
module Processing

    include("module.jl")
    if occursin(string(@__MODULE__), get(ENV, "JULIA_PRECOMP", ""))
        include("precompile.jl")
    end


end # module Processing
