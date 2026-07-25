module Fetch
    include("../Fetch/module.jl")
    isdefined(@__MODULE__, :__doinit__) && __doinit__()
end
