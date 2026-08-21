#!/usr/bin/env julia
# Type-instability check harness for the Planar package.
#
# Run as:  julia --project=Planar scripts/typecheck.jl
#
# If JET.jl is available (add it to [extras] of Planar/Project.toml and install),
# this runs JET.report_package on the package. If JET is not installed or fails to
# load for any reason, it prints the manual @code_warntype recipe and exits 0.
# The script always runs without error (CI-friendly).
#
# NOTE: JET.@report_call is a macro and must resolve at parse time, so it cannot be
# used behind a runtime `using JET` in a script. Run targeted @report_call calls
# interactively after `using JET`. The ranked analysis lives in
# TYPE_INSTABILITY_REPORT.md.

const TARGET_PKG = "Planar"

function fallback()
    println("JET.jl is not available in this environment (or failed to load).")
    println("To enable: julia --project=Planar -e 'using Pkg; Pkg.add(\"JET\")'")
    println("           (also add JET to [extras] of Planar/Project.toml)")
    println()
    println("Manual @code_warntype recipe (REPL, package loaded):")
    println("  using Planar, PlanarCore")
    println("  @code_warntype fetch_ohlcv!(s, tfs...)   # data-loading hot path")
    println("  @code_warntype LiveMode.send!(s, o)       # order send path")
    println("  @code_warntype cash!(ii, side)           # cash mutation path")
    println("  @code_warntype fill!(s, ii, o, trade)    # order-fill path")
    println()
    println("For targeted JET reports, run interactively after `using JET`:")
    println("  using JET, Planar, PlanarCore")
    println("  JET.report_package(\"Planar\")")
    println("  JET.@report_call fetch_ohlcv!(s, tfs...)")
    println()
    println("See TYPE_INSTABILITY_REPORT.md for the ranked hotspot analysis and fixes.")
end

try
    using JET
    println("=== JET type report for $TARGET_PKG ===")
    JET.report_package(TARGET_PKG)
    println("\n=== Done (JET) ===")
catch e
    println("JET run failed: $(typeof(e)): $e")
    println()
    fallback()
end
