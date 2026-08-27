module Watchers
    using PlanarCore.Ccxt: HTTP, JSON3
    using Rocket
    const URIs = HTTP.URIs
    using Statistics
    include("../Watchers/module.jl")
    isdefined(@__MODULE__, :__doinit__) && __doinit__()
end
