#!/usr/bin/env julia
# Usage: julia package-hierarchy.jl [--dot] [repo_root]
#   --dot       Output Graphviz DOT format instead of indented text
#   repo_root   Path to repository root (default: current directory, then /project)

using TOML

function find_project_tomls(root)
    tomls = String[]
    for (dirpath, dirnames, filenames) in walkdir(root)
        # Skip hidden, vendored, and user directories
        base = basename(dirpath)
        startswith(base, '.') && continue
        startswith(dirpath, joinpath(root, "user")) && continue
        startswith(dirpath, joinpath(root, "vendor")) && continue
        startswith(dirpath, joinpath(root, "deps")) && continue
        startswith(dirpath, joinpath(root, "docs")) && continue
        "Project.toml" in filenames && push!(tomls, joinpath(dirpath, "Project.toml"))
    end
    tomls
end

function read_package_info(toml_path)
    d = TOML.parsefile(toml_path)
    name = get(d, "name", "")
    isempty(name) && return nothing
    deps = keys(get(d, "deps", Dict())) |> collect
    (name=name, path=dirname(toml_path), deps=deps, local_deps=String[], ext_deps=String[])
end

function build_hierarchy(root)
    tomls = find_project_tomls(root)
    packages = Dict{String, Any}()
    all_dep_names = Set{String}()

    for t in tomls
        info = read_package_info(t)
        info === nothing && continue
        packages[info.name] = info
        push!(all_dep_names, info.name)
    end

    # Identify which deps are local vs. external
    for (name, info) in packages
        info = (;
            info...,
            local_deps=filter(d -> d in all_dep_names, info.deps),
            ext_deps=filter(d -> !(d in all_dep_names), info.deps),
        )
        packages[name] = info
    end

    packages
end

function compute_tiers(packages)
    tiers = Dict{String, Int}()
    remaining = Set(keys(packages))

    # Seed: packages with no local deps are tier 1
    for (name, info) in packages
        if isempty(info.local_deps)
            tiers[name] = 1
            delete!(remaining, name)
        end
    end

    # Iteratively assign tiers
    while !isempty(remaining)
        for name in collect(remaining)
            info = packages[name]
            if all(d -> haskey(tiers, d), info.local_deps)
                tiers[name] = maximum(tiers[d] for d in info.local_deps; init=0) + 1
                delete!(remaining, name)
            end
        end
    end

    tiers
end

function print_hierarchy(packages, tiers)
    # Group by tier
    by_tier = Dict{Int, Vector{String}}()
    for (name, tier) in tiers
        push!(get!(by_tier, tier, String[]), name)
    end

    println("Package Hierarchy (excluding user strategies)")
    println("=" ^ 50)
    for tier in sort(collect(keys(by_tier)))
        println("\nTier $tier:")
        for name in sort(by_tier[tier])
            info = packages[name]
            indent = "  "
            println(indent * name)
            if !isempty(info.local_deps)
                println(indent * "  Dependencies: " * join(sort(info.local_deps), ", "))
            end
        end
    end
end

function print_dot(packages, tiers)
    println("digraph packages {")
    println("  rankdir=LR;")
    println("  node [shape=box, style=rounded];")

    # Group by tier for rank=same
    by_tier = Dict{Int, Vector{String}}()
    for (name, tier) in tiers
        push!(get!(by_tier, tier, String[]), name)
    end

    for tier in sort(collect(keys(by_tier)))
        println("  subgraph cluster_tier_$tier {")
        println("    label=\"Tier $tier\";")
        println("    style=invis;")
        for name in by_tier[tier]
            println("    \"$name\";")
        end
        println("  }")
    end

    # Edges
    for (name, info) in packages
        for dep in sort(info.local_deps)
            println("  \"$dep\" -> \"$name\";")
        end
    end

    println("}")
end

function main()
    args = copy(ARGS)
    dot_mode = false
    if !isempty(args) && args[1] == "--dot"
        dot_mode = true
        popfirst!(args)
    end

    root = isempty(args) ? (isfile("/project/Project.toml") ? "/project" : pwd()) : args[1]

    packages = build_hierarchy(root)
    tiers = compute_tiers(packages)

    if dot_mode
        print_dot(packages, tiers)
    else
        print_hierarchy(packages, tiers)
    end
end

main()
