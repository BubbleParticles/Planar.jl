#!/usr/bin/env julia

# Coverage analysis for Planar.jl packages using Coverage.jl.
# Usage: julia scripts/coverage.jl <package-name>
#
# 1. Clears precompile cache for the package and its manifest deps
# 2. Runs Pkg.test(coverage=true)
# 3. Uses Coverage.jl to parse .jl.PID.cov files and print per-file coverage

package_name = length(ARGS) >= 1 ? ARGS[1] : error("Usage: coverage.jl <package-name>")
pkg_path = joinpath(@__DIR__, "..", package_name)
isdir(pkg_path) || error("Package directory not found: $pkg_path")
isfile(joinpath(pkg_path, "Project.toml")) || error("No Project.toml in $pkg_path")

import Pkg
import TOML
import Coverage

function depot_compiled_dir()
    major_minor = string(VERSION.major) * "." * string(VERSION.minor)
    for depot in Pkg.depots()
        dir = joinpath(depot, "compiled", major_minor)
        if isdir(dir)
            return dir
        end
    end
    return joinpath(first(Pkg.depots()), "compiled", major_minor)
end

function clear_precompile_cache(pkg_name)
    compiled_dir = depot_compiled_dir()
    cache_dir = joinpath(compiled_dir, pkg_name)
    if isdir(cache_dir)
        rm(cache_dir; recursive=true, force=true)
        return true
    end
    return false
end

function clear_old_cov(src_dir)
    removed = 0
    isdir(src_dir) || return removed
    for (root, dirs, files) in walkdir(src_dir)
        for f in files
            endswith(f, ".cov") || continue
            rm(joinpath(root, f))
            removed += 1
        end
    end
    return removed
end

function read_manifest_deps(manifest_path)
    deps = String[]
    isfile(manifest_path) || return deps
    data = TOML.parsefile(manifest_path)
    for (name, _) in data
        push!(deps, name)
    end
    return deps
end

# ---- Main ----
let
    src_dir = joinpath(pkg_path, "src")

    # Step 0: Activate the package project
    Pkg.activate(pkg_path)

    # Step 1: Clear precompile cache
    println("="^60)
    println("Coverage analysis for: $package_name")
    println("="^60)
    println("\n[1/4] Clearing precompile caches...")
    manifest_path = joinpath(pkg_path, "Manifest.toml")
    deps = read_manifest_deps(manifest_path)
    cleared = 0
    for dep in deps
        if clear_precompile_cache(dep)
            println("  Cleared: $dep")
            cleared += 1
        end
    end
    if clear_precompile_cache(package_name)
        println("  Cleared: $package_name")
        cleared += 1
    end
    if cleared == 0
        println("  No caches found to clear")
    else
        println("  Cleared $cleared package cache(s)")
    end

    # Step 2: Clean old .cov files
    println("\n[2/4] Cleaning old .cov files...")
    removed = clear_old_cov(src_dir)
    println("  Removed $removed old .cov file(s)")

    # Step 3: Run tests with coverage
    println("\n[3/4] Running tests with coverage...\n")
    flush(stdout)
    Pkg.test(; coverage=true)
    println()

    # Step 4: Analyze coverage using Coverage.jl
    println("\n[4/4] Analyzing coverage...\n")
    flush(stdout)

    println("-"^60)
    println("Coverage Results for: $package_name")
    println("-"^60)
    total_covered = 0
    total_instr = 0
    total_src = 0
    for (root, dirs, files) in walkdir(src_dir)
        for f in sort(files)
            endswith(f, ".jl") || continue
            src_path = joinpath(root, f)
            src_n = countlines(src_path)
            total_src += src_n
            rel = relpath(src_path, src_dir)
            clean = splitext(rel)[1]

            # Find .cov files for this .jl file
            cov_files = filter(readdir(root)) do cf
                startswith(cf, f * ".") && endswith(cf, ".cov")
            end
            if isempty(cov_files)
                println(rpad(clean, 20), " 0/", lpad(src_n, 4), " =  0.0%  (no cov)")
                continue
            end

            # Use Coverage.jl's process_cov to parse raw .cov data
            cov = Coverage.process_cov(f, root)
            instr = count(!isnothing, cov)
            covd = count(x -> x isa Int && x > 0, cov)
            total_instr += instr
            total_covered += covd

            pct = instr > 0 ? round(100.0 * covd / instr; digits=1) : 0.0
            uncovered = instr - covd
            println(rpad(clean, 20), " ", lpad(covd, 3), "/", lpad(instr, 4), " = ", lpad(string(pct), 5), "%  ($uncovered uncovered)")
        end
    end
    println("-"^60)
    total_pct = total_instr > 0 ? round(100.0 * total_covered / total_instr; digits=1) : 0.0
    println(rpad("TOTAL", 20), " ", lpad(total_covered, 3), "/", lpad(total_instr, 5), " = ", lpad(string(total_pct), 5), "%  ($total_src total source lines)")
    println("-"^60)
end
