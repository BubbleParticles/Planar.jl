module FeatureSelection
    using Clustering, Distances, Distributions, GLM, LinearAlgebra, OnlineStats
    using OnlineTechnicalIndicators, Statistics, StatsBase
    include("../../../FeatureSelection/src/module.jl")
    isdefined(@__MODULE__, :__doinit__) && __doinit__()
end
