module Fetch
    include("../../../Fetch/src/module.jl")
    isdefined(@__MODULE__, :__doinit__) && __doinit__()
end
