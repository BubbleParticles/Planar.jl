module Metrics
    using Statistics, StatsBase, OnlineStats
    include("../../../Metrics/src/module.jl")
    isdefined(@__MODULE__, :__doinit__) && __doinit__()
end
