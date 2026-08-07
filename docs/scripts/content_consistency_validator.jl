#!/usr/bin/env julia

"""
Content Consistency Validator

Validates content consistency across all documentation files:
- Terminology consistency
- Format consistency (headings, code blocks, lists)
- Cross-reference validation

Usage:
    julia docs/scripts/content_consistency_validator.jl

Exits with code 1 if any :error-severity issues are found.
"""

using Pkg
Pkg.activate("../")

push!(LOAD_PATH, joinpath(@__DIR__, "..", "test"))
include(joinpath(@__DIR__, "..", "test", "ContentConsistency.jl"))
using .ContentConsistency
using TOML

const DOCS_SRC_DIR = joinpath(@__DIR__, "..", "src")
const CONFIG_PATH = joinpath(@__DIR__, "..", "test", "config.toml")

config = isfile(CONFIG_PATH) ? TOML.parsefile(CONFIG_PATH) : Dict{String, Any}()

results = validate_content_consistency(DOCS_SRC_DIR; config=config)

errors = count(r -> r.severity == :error, results)
warnings = count(r -> r.severity == :warning, results)
infos = count(r -> r.severity == :info, results)

for r in results
    severity = r.severity == :error ? "ERROR" : r.severity == :warning ? "WARN" : "INFO"
    println("[$severity] $(r.check_type) | $(r.file):$(r.line) | $(r.issue)")
    if r.suggestion !== nothing
        println("           suggestion: $(r.suggestion)")
    end
end

println("\n=== CONTENT CONSISTENCY RESULTS ===")
println("Total: $(length(results)) | Errors: $errors | Warnings: $warnings | Info: $infos")

exit(errors > 0 ? 1 : 0)
