module LiveMode
    using LRUCache, Rocket
    include("../../../LiveMode/src/module.jl")
    isdefined(@__MODULE__, :__doinit__) && __doinit__()
end
