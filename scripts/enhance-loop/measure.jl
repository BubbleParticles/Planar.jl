#!/usr/bin/env julia
"""Measure baseline metrics: Julia cold-start, precompile cache, deps."""
using Dates, JSON

function measure_cold_start(project::String="Planar")
    t0 = time()
    # We measure via subprocess to avoid current process warm cache
    t = @elapsed run(`julia --project=$project -e "using Planar"`)
    # Alternative: just time the subprocess externally; here we fallback to elapsed
    return t
end
function cache_size()
    dir = joinpath(homedir(), ".julia", "compiled")
    isdir(dir) || return 0
    total = 0
    for (root, _, files) in walkdir(dir)
        for f in files
            p = joinpath(root, f)
            try; total += filesize(p); catch; end
        end
    end
    return total
end
function main()
    metrics = Dict(
        "timestamp" => string(now(UTC)),
        "julia_version" => string(VERSION),
        "cache_bytes" => cache_size(),
        "cold_start_s" => try
            @elapsed run(`julia --project=Planar -e "using Planar; println(\"ok\")"`)
        catch e
            -1.0
        end,
    )
    out = joinpath(@__DIR__, "../../reports/enhance-loop-baseline.json")
    mkpath(dirname(out))
    open(out, "w") do io; JSON.print(io, metrics, 2); end
    println(JSON.json(metrics))
end
main()
