module Plotting
    using Makie, Random
    include("Plotting/module.jl")
    isdefined(@__MODULE__, :__doinit__) && __doinit__()
end
