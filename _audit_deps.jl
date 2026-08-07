#!/usr/bin/env julia
# Audit stale deps - extracts top-level module names from `using/import` lines.

using TOML

pkgs = [
    "PlanarCore", "PlanarOptim", "PlanarDev", "Planar",
    "PlanarDownloadTool", "PlanarFeatureSelection", "PlanarStrategyTools",
    "PlanarStrategyStats"
]

function referenced_modules(text)
    """Return set of all top-level module names in `using`/`import` statements.
    Handles: `using Foo`, `import Foo`, `using Foo.Bar`, `using A, B.C`,
             `using .Foo`, `using ..Foo`, `@reexport using Foo`."""
    names = Set{String}()
    for line in split(text, '\n')
        m = match(r"\b(?:using|import)\b\s*(?:@reexport\s+)?(.*?)$", line)
        m === nothing && continue
        rest = strip(m[1])
        isempty(rest) && continue
        # Split by comma for `using A, B, C.D`
        parts = split(rest, r",\s*")
        for part in parts
            part = strip(part)
            # Strip leading dots: `..Foo` or `.Foo`
            part = lstrip(part, '.')
            # Strip whitespace after dots
            part = strip(part)
            # Handle `using Foo: x, y` — take module part before `:`
            colon_idx = findfirst(':', part)
            if colon_idx !== nothing
                part = strip(part[1:colon_idx-1])
            end
            isempty(part) && continue
            # Get the top-level module name (first component of dotted path)
            first_dot = findfirst('.', part)
            if first_dot !== nothing
                mod = strip(part[1:first_dot-1])
            else
                mod = part
            end
            if occursin(r"^\w+$", mod)
                push!(names, mod)
            end
        end
    end
    return names
end

results = []

for pkg in pkgs
    proj_file = joinpath(pkg, "Project.toml")
    !isfile(proj_file) && continue
    proj = TOML.parsefile(proj_file)
    deps = get(proj, "deps", Dict{String,Any}())
    isempty(deps) && continue

    src_dir = joinpath(pkg, "src")
    !isdir(src_dir) && continue

    combined = ""
    for (root, dirs, files) in walkdir(src_dir)
        for f in files
            endswith(f, ".jl") && (combined *= read(joinpath(root, f), String) * "\n")
        end
    end

    refd = referenced_modules(combined)

    stale = String[]
    for dep in sort!(collect(keys(deps)))
        if dep ∉ refd
            push!(stale, dep)
        end
    end
    push!(results, (pkg, stale, length(deps)))
end

println("=== Stale Dependency Audit ===\n")
any_stale = false
for (pkg, stale, total) in results
    if isempty(stale)
        println("✓ $pkg ($total deps) — all used")
    else
        any_stale = true
        println("✗ $pkg ($total deps): $(length(stale)) stale:")
        for d in stale
            println("    $d")
        end
    end
end
println("\n=== Done ===")
