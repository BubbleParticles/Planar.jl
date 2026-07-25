module Exchanges
    using JSON, Reexport, Serialization
    include("../Exchanges/module.jl")
    isdefined(@__MODULE__, :__doinit__) && __doinit__()
end
