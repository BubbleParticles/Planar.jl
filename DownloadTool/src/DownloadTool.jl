module DownloadTool
    using PlanarCore
    using CSV, CodecZlib, EzXML, HTTP, URIs, ZipFile
    include("module.jl")
    include("Cli/Cli.jl")
    __init__() = _doinit()
end
