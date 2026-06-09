#!/usr/bin/env julia
"""Update Zarr from vendored to upstream v0.10.0 in all downstream packages."""
using Pkg

packages = [
    "Cli", "Collections", "Engine", "Executors", "Exchanges", "FeatureSelection",
    "Fetch", "Instances", "LiveMode", "Metrics", "Opt", "PaperMode",
    "Planar", "PlanarDev", "PlanarInteractive", "Plotting", "Processing",
    "Remote", "Scrapers", "SimMode", "Simulations", "Strategies",
    "StrategyStats", "StrategyTools", "Stubs", "Watchers",
]

base = "/project"
skipped = 0
updated = 0

for pkg in packages
    pkg_path = joinpath(base, pkg)
    manifest = joinpath(pkg_path, "Manifest.toml")
    
    if !isfile(manifest)
        println("SKIP $pkg (no Manifest)")
        global skipped += 1
        continue
    end
    
    # Check if it references vendored Zarr
    content = read(manifest, String)
    if !occursin("vendor/Zarr", content)
        println("SKIP $pkg (no vendored Zarr)")
        global skipped += 1
        continue
    end
    
    println("UPDATING $pkg...")
    try
        Pkg.update(; io=devnull)
        global updated += 1
        println("  OK")
    catch e
        println("  FAILED: $e")
    end
end

println("\nDone! Updated: $updated, Skipped: $skipped")
