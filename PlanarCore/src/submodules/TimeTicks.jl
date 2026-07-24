module TimeTicks
    using Dates, Reexport, Serialization, TimeFrames
    include("../../../TimeTicks/src/module.jl")
    isdefined(@__MODULE__, :__doinit__) && __doinit__()
end
