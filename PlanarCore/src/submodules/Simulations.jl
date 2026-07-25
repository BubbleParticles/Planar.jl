module Simulations
    using IterTools, Random, Statistics, StatsBase
    include("../Simulations/module.jl")
    isdefined(@__MODULE__, :__doinit__) && __doinit__()
end
