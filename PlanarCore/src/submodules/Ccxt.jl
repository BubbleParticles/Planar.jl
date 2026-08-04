module Ccxt
    using FileWatching, HTTP, JSON3, MbedTLS, OrderedCollections, PrecompileTools, WebSockets
    include("../Ccxt/module.jl")
    isdefined(@__MODULE__, :__doinit__) && __doinit__()
    # Run the precompile workload when Ccxt itself or PlanarCore (its host) is
    # being precompiled — it syncs the ccxt-gateway venv before Ccxt compiles.
    if occursin(string(@__MODULE__), get(ENV, "JULIA_PRECOMP", "")) ||
       occursin("PlanarCore", get(ENV, "JULIA_PRECOMP", ""))
        include("../Ccxt/precompile.jl")
    end
end
