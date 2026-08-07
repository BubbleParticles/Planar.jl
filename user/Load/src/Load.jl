module Load
using PrecompileTools

@compile_workload begin
    using Planar
    using PlanarCore.Stubs
    using PlanarDownloadTool
    using PlanarCore.Metrics
end

end # module Load
