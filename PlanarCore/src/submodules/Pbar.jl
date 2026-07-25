module Pbar
    using Term
    include("../Pbar/module.jl")
    isdefined(@__MODULE__, :__doinit__) && __doinit__()
end
