module Lang
    using Distributed, DocStringExtensions, Logging, PrecompileTools, Preferences
    include("../Lang/module.jl")
    isdefined(@__MODULE__, :__doinit__) && __doinit__()
end
