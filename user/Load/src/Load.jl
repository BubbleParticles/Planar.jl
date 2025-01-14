module Load
using PrecompileTools

@compile_workload begin
    using Planar
    using Stubs
    using Scrapers
    using Metrics
end

end # module Load
