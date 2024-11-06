module Load
using PrecompileTools

@compile_workload begin
    using Vindicta
    using Stubs
    using Scrapers
    using Metrics
end

end # module Load
