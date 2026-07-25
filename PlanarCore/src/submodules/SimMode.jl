module SimMode
    using Random
    include("../SimMode/module.jl")
    isdefined(@__MODULE__, :__doinit__) && __doinit__()
end
