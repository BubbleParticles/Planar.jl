module Scrapers
    using CSV, CodecZlib, EzXML, HTTP, URIs, ZipFile
    include("../../../Scrapers/src/module.jl")
    isdefined(@__MODULE__, :__doinit__) && __doinit__()
end
