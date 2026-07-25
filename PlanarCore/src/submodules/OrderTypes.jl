module OrderTypes
    include("../OrderTypes/module.jl")
    isdefined(@__MODULE__, :__doinit__) && __doinit__()
end
