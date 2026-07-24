module Plotting
    using Makie, Random
    include("../../../Plotting/src/module.jl")
    isdefined(@__MODULE__, :__doinit__) && __doinit__()
end
