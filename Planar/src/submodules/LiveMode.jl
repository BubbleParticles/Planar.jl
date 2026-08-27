module LiveMode
    using LRUCache
    using Rocket
    include("../LiveMode/module.jl")
    isdefined(@__MODULE__, :__doinit__) && __doinit__()
end
