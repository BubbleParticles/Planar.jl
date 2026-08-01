module Load
using PrecompileTools

@compile_workload begin
    using Planar
    using PlanarCore.Stubs
    using Scrapers
    using Metrics
end

end # module Load
