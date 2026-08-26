#!/usr/bin/env julia
# Check compat bounds for all Project.toml
using TOML
for proj in ["Planar/Project.toml", "PlanarCore/Project.toml", "ccxt-gateway/pyproject.toml"]
    p = joinpath(@__DIR__, "../..", proj)
    isfile(p) || continue
    data = TOML.parsefile(p)
    compat = get(data, "compat", Dict())
    println("$proj compat: ", keys(compat))
    for (k,v) in compat
        if v == ""
            @warn "Missing compat for $k in $proj"
        end
    end
end
