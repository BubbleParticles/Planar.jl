#!/usr/bin/env julia

using Pkg
Pkg.activate("../")

include("../test/LinkValidator.jl")
using .LinkValidator

println("Starting link validation...")
results = validate_all_links("../src")

total_links = length(results)
valid_links = count(r -> r.valid, results)
invalid_links = total_links - valid_links

# Count by type using functional approach
internal_failures = count(r -> !r.valid && r.link_type == :internal, results)
external_failures = count(r -> !r.valid && r.link_type == :external, results)

println("\n=== LINK VALIDATION RESULTS ===")
println("Total links: $total_links")
println("Valid links: $valid_links")
println("Invalid links: $invalid_links")
println("Internal failures: $internal_failures")
println("External failures: $external_failures")
println("Success rate: $(round(valid_links/total_links*100, digits=1))%")

if internal_failures > 0
    println("\nFirst 10 internal link failures:")
    counter = 0
    for result in results
        if !result.valid && result.link_type == :internal && counter < 10
            println("  $(result.source_file):$(result.line_number) -> $(result.url)")
            counter += 1
        end
    end
end