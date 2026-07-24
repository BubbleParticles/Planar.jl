module PaperMode
    using PlanarCore.Fetch: Fetch
    using PlanarCore.SimMode
    using PlanarCore.SimMode.Executors
    using Random
    include("../../../PaperMode/src/module.jl")
    isdefined(@__MODULE__, :__doinit__) && __doinit__()
end
