#!/usr/bin/env julia
# Profile precompilation workloads and invalidations
using SnoopCompile
println("Precompile profile stub — uses SnoopCompile.@snoop_invalidations if available")
try
    using SnoopCompileCore
    println("SnoopCompile available")
catch e
    @warn "SnoopCompile not installed: $e"
end
# Emit workload coverage placeholder
open(joinpath(@__DIR__, "../../reports/enhance-loop/precompile-report.md"), "w") do io
    println(io, "# Precompile profile $(now())")
    println(io, "Snoop invalidations: run `julia --project=Planar -e 'using SnoopCompile; @snoop_invalidations using Planar'`")
end
println("Wrote precompile-report.md")
