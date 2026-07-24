module Pbar
    using Term
    include("../../../Pbar/src/module.jl")
    isdefined(@__MODULE__, :__doinit__) && __doinit__()
end
