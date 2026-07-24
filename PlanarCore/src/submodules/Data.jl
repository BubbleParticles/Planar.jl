module Data
    using CodecZlib, DataFrames, DataFramesMeta, DataStructures, LMDB, Reexport, Serialization, Zarr
    include("../../../Data/src/module.jl")
    isdefined(@__MODULE__, :__doinit__) && __doinit__()
end
