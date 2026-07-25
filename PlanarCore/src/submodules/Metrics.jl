module Metrics
    using Statistics, StatsBase, OnlineStats
    include("../Metrics/module.jl")
    isdefined(@__MODULE__, :__doinit__) && __doinit__()
end
