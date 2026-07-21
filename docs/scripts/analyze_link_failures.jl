#!/usr/bin/env julia

"""
Link Failure Analysis Script

This script analyzes the 502 link failures and categorizes them by type.
"""

using Pkg
Pkg.activate("docs")

# Include the test modules
include("docs/test/LinkValidator.jl")
using .LinkValidator

# Run link validation and capture results
println("Running link validation...")
results = validate_all_links("docs/src")

# Categorize failures
missing_files = String[]
malformed_links = String[]
self_references = String[]
at_ref_issues = String[]
external_issues = String[]
path_issues = String[]

for result in results
    if !result.valid
        link = result.url
        source = result.source_file
        
        # Categorize the failure
        if startswith(link, "@ref")
            push!(at_ref_issues, "$(source): $(link)")
        elseif contains(link, "[") && contains(link, "](")
            # Malformed markdown link
            push!(malformed_links, "$(source): $(link)")
        elseif startswith(link, "http")
            push!(external_issues, "$(source): $(link)")
        elseif contains(link, "../") && contains(basename(source), basename(link))
            # Self-reference
            push!(self_references, "$(source): $(link)")
        else
            # Check if target file actually exists
            target_path = if startswith(link, "../")
                # Relative path from source file
                source_dir = dirname(source)
                joinpath(source_dir, link)
            else
                link
            end
            
            # Normalize path
            target_path = normpath(target_path)
            
            if isfile(target_path)
                push!(path_issues, "$(source): $(link) -> $(target_path) (EXISTS but validator says missing)")
            else
                push!(missing_files, "$(source): $(link) -> $(target_path)")
            end
        end
    end
end

# Print analysis
println("\n=== LINK FAILURE ANALYSIS ===")
println("Total failures: $(length([r for r in results if !r.valid]))")
println()

println("1. @ref Issues ($(length(at_ref_issues))):")
for issue in at_ref_issues[1:min(10, end)]
    println("   $issue")
end
if length(at_ref_issues) > 10
    println("   ... and $(length(at_ref_issues) - 10) more")
end
println()

println("2. Malformed Links ($(length(malformed_links))):")
for issue in malformed_links[1:min(10, end)]
    println("   $issue")
end
if length(malformed_links) > 10
    println("   ... and $(length(malformed_links) - 10) more")
end
println()

println("3. Self-References ($(length(self_references))):")
for issue in self_references[1:min(5, end)]
    println("   $issue")
end
if length(self_references) > 5
    println("   ... and $(length(self_references) - 5) more")
end
println()

println("4. Path Resolution Issues ($(length(path_issues))):")
for issue in path_issues[1:min(10, end)]
    println("   $issue")
end
if length(path_issues) > 10
    println("   ... and $(length(path_issues) - 10) more")
end
println()

println("5. Actually Missing Files ($(length(missing_files))):")
for issue in missing_files[1:min(10, end)]
    println("   $issue")
end
if length(missing_files) > 10
    println("   ... and $(length(missing_files) - 10) more")
end
println()

println("6. External Link Issues ($(length(external_issues))):")
for issue in external_issues[1:min(5, end)]
    println("   $issue")
end
if length(external_issues) > 5
    println("   ... and $(length(external_issues) - 5) more")
end
println()

# Find most frequently referenced missing files
missing_targets = Dict{String, Int}()
for result in results
    if !result.valid && !startswith(result.url, "http") && !startswith(result.url, "@ref")
        target = result.url
        missing_targets[target] = get(missing_targets, target, 0) + 1
    end
end

println("Most frequently referenced targets:")
sorted_targets = sort(collect(missing_targets), by=x->x[2], rev=true)
for (target, count) in sorted_targets[1:min(15, end)]
    println("   $count times: $target")
end