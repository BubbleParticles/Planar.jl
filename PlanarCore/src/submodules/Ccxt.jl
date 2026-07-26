module Ccxt
    using FileWatching, HTTP, JSON3, MbedTLS, OrderedCollections, PrecompileTools, WebSockets
    include("../Ccxt/module.jl")
    isdefined(@__MODULE__, :__doinit__) && __doinit__()
end
