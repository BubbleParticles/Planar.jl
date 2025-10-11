#!/usr/bin/env julia

"""
Documentation Test Runner

This script runs all documentation tests, including:
1. Link checking
2. Format consistency validation

Usage:
    julia docs/test/runtests.jl [options]

Options:
    --project=PATH    Path to Julia project (default: Planar)
    --docs=PATH       Path to docs directory (default: docs/src)
    --skip-links      Skip link validation
    --skip-format     Skip format validation
    --verbose         Enable verbose output
    --help            Show this help message
"""

using Pkg
using Test
using TOML
using Dates

# Add the test directory to load path
push!(LOAD_PATH, @__DIR__)

# Include local modules
include("config_validator.jl")
include("LinkValidator.jl")
include("ContentConsistency.jl")
include("TestResultsReporter.jl")

using .ConfigValidator
using .LinkValidator
using .ContentConsistency
using .TestResultsReporter

function parse_args(args)
    options = Dict(
        :project_path => "PlanarDev",
        :docs_path => "docs/src",
        :config_path => "docs/test/config.toml",

        :skip_links => false,
        :skip_format => false,
        :verbose => false,
        :help => false,
        :julia_version => string(VERSION),
        :output_file => nothing
    )
    
    for arg in args
        if startswith(arg, "--project=")
            options[:project_path] = arg[11:end]
        elseif startswith(arg, "--docs=")
            options[:docs_path] = arg[8:end]
        elseif startswith(arg, "--config=")
            options[:config_path] = arg[10:end]
        elseif startswith(arg, "--output=")
            options[:output_file] = arg[10:end]

        elseif arg == "--skip-links"
            options[:skip_links] = true
        elseif arg == "--skip-format"
            options[:skip_format] = true
        elseif arg == "--verbose"
            options[:verbose] = true
        elseif arg == "--help"
            options[:help] = true
        else
            @warn "Unknown option: $arg"
        end
    end
    
    return options
end

function show_help()
    println(__doc__)
end

function main()
    options = parse_args(ARGS)
    
    if options[:help]
        show_help()
        return
    end
    
    if options[:verbose]
        ENV["JULIA_DEBUG"] = "LinkValidator,ContentConsistency"
    end
    
    # Load and validate configuration
    config = validate_config_or_default(options[:config_path])
    
    @info "Starting Planar documentation tests"
    @info "Project path: $(options[:project_path])"
    @info "Docs path: $(options[:docs_path])"
    @info "Julia version: $(options[:julia_version])"
    @info "Config file: $(options[:config_path])"
    
    all_tests_passed = true
    test_results = Dict{String, Any}(
        "julia_version" => options[:julia_version],
        "timestamp" => string(Dates.now()),
        "config" => config,
        "results" => Dict{String, Any}()
    )
    
    # Test 1: Link Validation
    if !options[:skip_links]
        @testset "Link Validation" begin
            @info "Running link validation tests..."
            link_results = validate_all_links(options[:docs_path]; config=config)
            
            # Count results
            valid_links = count(r -> r.valid, link_results)
            invalid_links = count(r -> !r.valid, link_results)
            
            # Report invalid links
            for result in link_results
                if !result.valid
                    @warn "Invalid link in $(result.source_file):$(result.line_number): $(result.url)" error=result.error
                end
            end
            
            # Test passes if no broken internal links (external links may be warnings)
            internal_failures = count(r -> !r.valid && r.link_type == :internal, link_results)
            @test internal_failures == 0
            
            all_tests_passed &= (internal_failures == 0)
            test_results["results"]["link_validation"] = Dict(
                "total" => length(link_results),
                "valid" => valid_links,
                "invalid" => invalid_links,
                "internal_failures" => internal_failures,
                "timestamp" => string(Dates.now())
            )
        end
    else
        @info "Skipping link validation tests"
        test_results["results"]["link_validation"] = Dict("skipped" => true)
    end
    
    # Test 2: Content Consistency
    if !options[:skip_format]
        @testset "Content Consistency" begin
            @info "Running content consistency tests..."
            consistency_results = validate_content_consistency(options[:docs_path]; config=config)
            
            # Count results by severity
            errors = count(r -> r.severity == :error, consistency_results)
            warnings = count(r -> r.severity == :warning, consistency_results)
            info_issues = count(r -> r.severity == :info, consistency_results)
            
            # Report issues
            for result in consistency_results
                severity_symbol = result.severity == :error ? "❌" : 
                                result.severity == :warning ? "⚠️" : "ℹ️"
                @info "$severity_symbol $(result.check_type) issue in $(result.file):$(result.line): $(result.issue)"
                if result.suggestion !== nothing
                    @info "  Suggestion: $(result.suggestion)"
                end
            end
            
            # Test passes if no errors (warnings and info are allowed)
            @test errors == 0
            
            all_tests_passed &= (errors == 0)
            test_results["results"]["content_consistency"] = Dict(
                "total" => length(consistency_results),
                "errors" => errors,
                "warnings" => warnings,
                "info" => info_issues,
                "timestamp" => string(Dates.now())
            )
        end
    else
        @info "Skipping content consistency tests"
        test_results["results"]["content_consistency"] = Dict("skipped" => true)
    end
    
    # Save test results if output file specified
    if options[:output_file] !== nothing
        mkpath(dirname(options[:output_file]))
        open(options[:output_file], "w") do f
            TOML.print(f, test_results)
        end
        @info "Test results saved to $(options[:output_file])"
    end
    
    if all_tests_passed
        @info "All documentation tests passed! ✅"
        exit(0)
    else
        @error "Some documentation tests failed! ❌"
        exit(1)
    end
end

# Run main function if script is executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
