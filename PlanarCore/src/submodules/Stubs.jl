module Stubs
    using CSV, Pkg, Random
    include("../../../Stubs/src/module.jl")
    isdefined(@__MODULE__, :__doinit__) && __doinit__()
end
