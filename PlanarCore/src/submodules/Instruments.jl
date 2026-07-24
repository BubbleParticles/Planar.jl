module Instruments
    using Printf
    include("../../../Instruments/src/module.jl")
    isdefined(@__MODULE__, :__doinit__) && __doinit__()
end
