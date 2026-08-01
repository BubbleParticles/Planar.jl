module Scrapers
    using PlanarCore
    using CSV, CodecZlib, EzXML, HTTP, URIs, ZipFile
    include("module.jl")
    isdefined(@__MODULE__, :__doinit__) && __doinit__()
end
