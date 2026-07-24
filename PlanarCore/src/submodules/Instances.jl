module Instances
    include("../../../Instances/src/module.jl")
    isdefined(@__MODULE__, :__doinit__) && __doinit__()
end
