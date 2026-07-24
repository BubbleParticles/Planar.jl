module Strategies
    using Pkg
    include("../../../Strategies/src/module.jl")
    isdefined(@__MODULE__, :__doinit__) && __doinit__()
end
