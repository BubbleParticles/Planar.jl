#!/usr/bin/env julia

"""
Documentation Single-File Test

Runs link validation and content consistency checks on a single markdown file.

Usage:
    julia docs/test/test_file.jl path/to/file.md [--verbose]

The file path is resolved relative to the repository root when not absolute.
Exits with code 1 if any broken internal link or :error-severity issue is found.
"""

using Pkg, TOML, Dates

isempty(ARGS) && error("Usage: julia docs/test/test_file.jl path/to/file.md [--verbose]")
file_arg = ARGS[1]
verbose = "--verbose" in ARGS

push!(LOAD_PATH, @__DIR__)
include(joinpath(@__DIR__, "config_validator.jl"))
include(joinpath(@__DIR__, "LinkValidator.jl"))
include(joinpath(@__DIR__, "ContentConsistency.jl"))

using .ConfigValidator
using .LinkValidator
using .ContentConsistency

const REPO_ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const DOCS_SRC_DIR = joinpath(REPO_ROOT, "docs", "src")

file = isabspath(file_arg) ? file_arg : normpath(joinpath(REPO_ROOT, file_arg))
isfile(file) || error("File not found: $file")

config = validate_config_or_default(joinpath(@__DIR__, "config.toml"))

function run_checks(file::String, docs_src::String, config::Dict)
    failed = false

    link_results = validate_links_in_file(file, docs_src; config=config)
    for r in link_results
        if !r.valid
            @warn "Invalid $(r.link_type) link: $(r.url)" error=r.error
            r.link_type == :internal && (failed = true)
        end
    end

    for (name, results) in [
        ("terminology", check_terminology_consistency(file, config)),
        ("format", check_format_consistency(file, config)),
        ("cross-reference", check_cross_references(file, docs_src, config)),
    ]
        for r in results
            severity = r.severity == :error ? "❌" : r.severity == :warning ? "⚠️" : "ℹ️"
            println("$severity [$name] $(r.file):$(r.line) $(r.issue)")
            if r.suggestion !== nothing
                println("    suggestion: $(r.suggestion)")
            end
            r.severity == :error && (failed = true)
        end
    end
    return failed
end

failed = run_checks(file, DOCS_SRC_DIR, config)

println(failed ? "\nFAILED: issues found in $file" : "\nOK: no issues in $file")
exit(failed ? 1 : 0)
