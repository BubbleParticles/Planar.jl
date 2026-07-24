module Load
using PrecompileTools

@compile_workload begin
    using Planar
    using PlanarCore.Stubs
    using PlanarCore.Scrapers
    using Metrics
end

end # module Load
