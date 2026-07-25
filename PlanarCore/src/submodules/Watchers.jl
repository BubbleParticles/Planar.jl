module Watchers
    using HTTP, JSON3, Rocket, Statistics, URIs
    include("../Watchers/module.jl")
    isdefined(@__MODULE__, :__doinit__) && __doinit__()
end
