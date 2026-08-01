#!/usr/bin/env julia
using TOML

pkg = "PlanarCore"
proj_file = joinpath(pkg, "Project.toml")
proj = TOML.parsefile(proj_file)
deps = get(proj, "deps", Dict{String,Any}())

src_files = String[]
for (root, dirs, files) in walkdir(joinpath(pkg, "src"))
    for f in files
        endswith(f, ".jl") && push!(src_files, joinpath(root, f))
    end
end

println("src files: $(length(src_files))")
for dep in sort!(collect(keys(deps)))
    found = false
    found_in = ""
    for sf in src_files
        content = read(sf, String)
        if occursin(r"\b" * dep * r"\b", content)
            found = true
            found_in = sf
            break
        end
    end
    if !found
        println("  STALE: $dep")
    end
end
println("Done.")
