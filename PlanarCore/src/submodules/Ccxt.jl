module Ccxt
    using FileWatching, HTTP, JSON3, MbedTLS, OrderedCollections, PrecompileTools, PythonCall, WebSockets
    include("../../../Ccxt/src/module.jl")
    isdefined(@__MODULE__, :__doinit__) && __doinit__()
end
