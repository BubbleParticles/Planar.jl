module Watchers
    using PlanarCore.Ccxt: HTTP, JSON3, Rocket, URIs
    using Statistics
    include("../Watchers/module.jl")
    isdefined(@__MODULE__, :__doinit__) && __doinit__()
end
