module Load
using PrecompileTools

@compile_workload begin
    using Planar
    using PlanarCore.Stubs
    using DownloadTool
    using Metrics
end

end # module Load
