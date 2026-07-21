#!/usr/bin/env julia
# Usage: julia scripts/coverage_quick.jl <package-name>
# Quick coverage analysis using raw .cov file parsing.

package_name = ARGS[1]
pkg_path = joinpath(@__DIR__, "..", package_name)
src_dir = joinpath(pkg_path, "src")
test_dir = joinpath(pkg_path, "test")

# Clear old .cov files
for (root, dirs, files) in walkdir(src_dir)
    for f in files
        endswith(f, ".cov") && rm(joinpath(root, f))
    end
end

# Run tests with coverage via subprocess
run(`julia --project=$(test_dir) --code-coverage=all -e "include(\\\"$(test_dir)/runtests.jl\\\")"`)

# Analyze with local function
function analyze_cov(src_file, srcdir)
    src_name = basename(src_file)
    cov_files = filter(readdir(srcdir)) do cf
        startswith(cf, src_name) && endswith(cf, ".cov")
    end
    isempty(cov_files) && return (0, 0, countlines(src_file))
    instr_sum = 0
    covd_sum = 0
    for covf in cov_files
        cov_lines = readlines(joinpath(srcdir, covf))
        instr = count(l -> l != "-", cov_lines)
        covd = count(l -> l != "-" && l != "0" && l != "", cov_lines)
        instr_sum += instr
        covd_sum += covd
    end
    return (covd_sum, instr_sum, countlines(src_file))
end

let
    local total_covered = 0
    local total_instr = 0
    local total_src = 0
    for (root, dirs, files) in walkdir(src_dir)
        for f in sort(files)
            endswith(f, ".jl") || continue
            endswith(f, ".jl.cov") && continue
            src_path = joinpath(root, f)
            rel = relpath(src_path, src_dir)
            covd, instr, src_n = analyze_cov(src_path, root)
            total_covered += covd
            total_instr += instr
            total_src += src_n
            pct = instr > 0 ? round(100.0 * covd / instr; digits=1) : 0.0
            println(rpad(rel, 30), " ", lpad(covd, 3), "/", lpad(instr, 4), " = ", lpad(string(pct), 5), "%  ($instr exec lines)")
        end
    end
    println("-"^60)
    local total_pct = total_instr > 0 ? round(100.0 * total_covered / total_instr; digits=1) : 0.0
    println(rpad("TOTAL", 30), " ", lpad(total_covered, 3), "/", lpad(total_instr, 5), " = ", lpad(string(total_pct), 5), "%  ($total_src src lines)")
end
