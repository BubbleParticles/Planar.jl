__precompile__(false)
module PaperMode
    using PlanarCore.Fetch: Fetch
    using PlanarCore.SimMode
    using PlanarCore.SimMode.Executors
    using Random
    include("../PaperMode/module.jl")
    isdefined(@__MODULE__, :__doinit__) && __doinit__()
end
