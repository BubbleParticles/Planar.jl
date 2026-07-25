module ExchangeTypes
    using FunctionalCollections, JSON3, OrderedCollections
    include("../ExchangeTypes/module.jl")
    isdefined(@__MODULE__, :__doinit__) && __doinit__()
end
