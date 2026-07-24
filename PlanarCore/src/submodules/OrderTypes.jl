module OrderTypes
    include("../../../OrderTypes/src/module.jl")
    isdefined(@__MODULE__, :__doinit__) && __doinit__()
end
