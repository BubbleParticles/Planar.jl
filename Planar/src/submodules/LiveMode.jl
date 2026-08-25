module LiveMode
    using LRUCache
    using PlanarCore.Ccxt: Rocket
    include("../LiveMode/module.jl")
    isdefined(@__MODULE__, :__doinit__) && __doinit__()
end
