module Processing
    using StatsBase
    include("../Processing/module.jl")
    isdefined(@__MODULE__, :__doinit__) && __doinit__()
end
