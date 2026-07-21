#!/usr/bin/env julia

using Pkg
Pkg.activate("../")

include("../test/LinkValidator.jl")
using .LinkValidator

println("Starting comprehensive link validation...")
results = validate_all_links("../src")

total_links = length(results)
valid_links = count(r -> r.valid, results)
invalid_links = total_links - valid_links

# Count by type using functional approach
internal_failures = count(r -> !r.valid && r.link_type == :internal, results)
external_failures = count(r -> !r.valid && r.link_type == :external, results)

println("")
println("=== COMPREHENSIVE LINK VALIDATION RESULTS ===")
println("Total links checked: $total_links")
println("Valid links: $valid_links")
println("Invalid links: $invalid_links")
println("Internal link failures: $internal_failures")
println("External link failures: $external_failures")
println("Success rate: $(round(valid_links/total_links*100, digits=1))%")
println("Internal success rate: $(round((total_links-internal_failures)/total_links*100, digits=1))%")

if internal_failures > 0
    println("")
    println("Sample internal link failures (first 15):")
    counter = 0
    for result in results
        if !result.valid && result.link_type == :internal && counter < 15
            println("  $(result.source_file):$(result.line_number) -> $(result.url)")
            counter += 1
        end
    end
end

# Show improvement from original 502 failures
original_failures = 502
improvement = original_failures - internal_failures
improvement_pct = round(improvement/original_failures*100, digits=1)

println("")
println("=== IMPROVEMENT ANALYSIS ===")
println("Original internal failures: $original_failures")
println("Current internal failures: $internal_failures")
println("Failures resolved: $improvement")
println("Improvement: $improvement_pct%")