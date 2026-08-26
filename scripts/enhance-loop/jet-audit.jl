#!/usr/bin/env julia
# JET audit for hot files
try
    using JET
    for pkg in ["PlanarCore", "Planar"]
        println("JET report for $pkg")
        try
            JET.report_package(pkg; toplevel_logger=nothing)
        catch e
            @warn "JET failed for $pkg: $e"
        end
    end
    for f in ["Planar/src/strat.jl", "PlanarCore/src/SimMode/backtest.jl", "PlanarCore/src/Data/candles.jl", "PlanarStrategyStats/src/slope.jl"]
        println("JET file $f")
        try
            JET.report_file(f)
        catch e
            @warn "JET file $f failed: $e"
        end
    end
catch e
    @warn "JET not installed: $e"
end
open(joinpath(@__DIR__, "../../reports/enhance-loop/jet-report.txt"), "w") do io
    println(io, "JET audit stub — see console")
end
