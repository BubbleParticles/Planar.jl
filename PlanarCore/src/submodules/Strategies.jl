module Strategies
    using Pkg
    include("../Strategies/module.jl")
    isdefined(@__MODULE__, :__doinit__) && __doinit__()
end
