"""
Test Results Reporter

This module provides functionality to generate reports from documentation test results.
It supports:
- HTML report generation
- JSON report generation
- Summary statistics
- CI-friendly output formats
"""
module TestResultsReporter

using TOML
using JSON3
using Dates

export generate_html_report, generate_json_report, generate_summary_report,
       format_results_for_ci, TestSummary

"""
    TestSummary

Summary statistics for test results.
"""
struct TestSummary
    total_files::Int
    total_code_blocks::Int
    code_blocks_passed::Int
    code_blocks_failed::Int
    code_blocks_skipped::Int
    total_links::Int
    links_valid::Int
    links_invalid::Int
    consistency_issues::Int
    consistency_errors::Int
    consistency_warnings::Int
    execution_time::Float64
end

"""
    calculate_summary(results::Dict) -> TestSummary

Calculate summary statistics from test results.
"""
function calculate_summary(results::Dict)
    # Extract results data
    test_results = get(results, "results", Dict())
    
    # Code example results
    code_results = get(test_results, "code_examples", Dict())
    code_passed = get(code_results, "passed", 0)
    code_failed = get(code_results, "failed", 0)
    code_skipped = get(code_results, "skipped", 0)
    
    # Link validation results
    link_results = get(test_results, "link_validation", Dict())
    links_valid = get(link_results, "valid", 0)
    links_invalid = get(link_results, "invalid", 0)
    
    # Consistency results
    consistency_results = get(test_results, "content_consistency", Dict())
    consistency_errors = get(consistency_results, "errors", 0)
    consistency_warnings = get(consistency_results, "warnings", 0)
    consistency_info = get(consistency_results, "info", 0)
    
    # Calculate totals
    total_code_blocks = code_passed + code_failed + code_skipped
    total_links = links_valid + links_invalid
    consistency_issues = consistency_errors + consistency_warnings + consistency_info
    
    # Execution time
    execution_time = get(results, "execution_time", 0.0)
    
    return TestSummary(
        1, # total_files - would need to be calculated differently
        total_code_blocks,
        code_passed,
        code_failed,
        code_skipped,
        total_links,
        links_valid,
        links_invalid,
        consistency_issues,
        consistency_errors,
        consistency_warnings,
        execution_time
    )
end

"""
    generate_html_report(results_file::String, output_file::String)

Generate an HTML report from test results.
"""
function generate_html_report(results_file::String, output_file::String)
    if !isfile(results_file)
        @warn "Results file not found: $results_file"
        return
    end
    
    results = TOML.parsefile(results_file)
    summary = calculate_summary(results)
    
    html_content = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Planar Documentation Test Results</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 20px; }
            .header { background-color: #f8f9fa; padding: 20px; border-radius: 5px; }
            .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin: 20px 0; }
            .metric { background-color: #e9ecef; padding: 15px; border-radius: 5px; text-align: center; }
            .metric-value { font-size: 2em; font-weight: bold; }
            .metric-label { font-size: 0.9em; color: #6c757d; }
            .success { color: #28a745; }
            .warning { color: #ffc107; }
            .error { color: #dc3545; }
            .details { margin-top: 30px; }
            .section { margin-bottom: 30px; }
            .section h3 { border-bottom: 2px solid #dee2e6; padding-bottom: 10px; }
            table { width: 100%; border-collapse: collapse; margin-top: 10px; }
            th, td { padding: 8px 12px; text-align: left; border-bottom: 1px solid #dee2e6; }
            th { background-color: #f8f9fa; }
            .status-pass { color: #28a745; font-weight: bold; }
            .status-fail { color: #dc3545; font-weight: bold; }
            .status-skip { color: #6c757d; font-weight: bold; }
        </style>
    </head>
    <body>
        <div class="header">
            <h1>Planar Documentation Test Results</h1>
            <p>Generated on $(Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))</p>
            <p>Julia Version: $(get(results, "julia_version", "Unknown"))</p>
        </div>
        
        <div class="summary">
            <div class="metric">
                <div class="metric-value $(summary.code_blocks_failed > 0 ? "error" : "success")">
                    $(summary.code_blocks_passed)/$(summary.total_code_blocks)
                </div>
                <div class="metric-label">Code Examples Passed</div>
            </div>
            
            <div class="metric">
                <div class="metric-value $(summary.links_invalid > 0 ? "error" : "success")">
                    $(summary.links_valid)/$(summary.total_links)
                </div>
                <div class="metric-label">Links Valid</div>
            </div>
            
            <div class="metric">
                <div class="metric-value $(summary.consistency_errors > 0 ? "error" : summary.consistency_warnings > 0 ? "warning" : "success")">
                    $(summary.consistency_issues)
                </div>
                <div class="metric-label">Consistency Issues</div>
            </div>
            
            <div class="metric">
                <div class="metric-value">$(round(summary.execution_time, digits=2))s</div>
                <div class="metric-label">Execution Time</div>
            </div>
        </div>
        
        <div class="details">
            $(generate_detailed_sections(results))
        </div>
    </body>
    </html>
    """
    
    mkpath(dirname(output_file))
    write(output_file, html_content)
    @info "HTML report generated: $output_file"
end

"""
    generate_detailed_sections(results::Dict) -> String

Generate detailed sections for the HTML report.
"""
function generate_detailed_sections(results::Dict)
    sections = String[]
    
    # Code Examples section
    code_results = get(get(results, "results", Dict()), "code_examples", Dict())
    if !isempty(code_results)
        push!(sections, """
        <div class="section">
            <h3>Code Examples</h3>
            <p>Status: $(get(code_results, "passed", false) ? "✅ All tests passed" : "❌ Some tests failed")</p>
            <!-- Detailed code example results would go here -->
        </div>
        """)
    end
    
    # Link Validation section
    link_results = get(get(results, "results", Dict()), "link_validation", Dict())
    if !isempty(link_results)
        push!(sections, """
        <div class="section">
            <h3>Link Validation</h3>
            <p>Valid Links: $(get(link_results, "valid", 0))</p>
            <p>Invalid Links: $(get(link_results, "invalid", 0))</p>
            <!-- Detailed link validation results would go here -->
        </div>
        """)
    end
    
    # Content Consistency section
    consistency_results = get(get(results, "results", Dict()), "content_consistency", Dict())
    if !isempty(consistency_results)
        push!(sections, """
        <div class="section">
            <h3>Content Consistency</h3>
            <p>Errors: $(get(consistency_results, "errors", 0))</p>
            <p>Warnings: $(get(consistency_results, "warnings", 0))</p>
            <p>Info: $(get(consistency_results, "info", 0))</p>
            <!-- Detailed consistency results would go here -->
        </div>
        """)
    end
    
    return join(sections, "\n")
end

"""
    generate_json_report(results_file::String, output_file::String)

Generate a JSON report from test results.
"""
function generate_json_report(results_file::String, output_file::String)
    if !isfile(results_file)
        @warn "Results file not found: $results_file"
        return
    end
    
    results = TOML.parsefile(results_file)
    summary = calculate_summary(results)
    
    # Create JSON-friendly structure
    json_report = Dict(
        "metadata" => Dict(
            "generated_at" => string(now()),
            "julia_version" => get(results, "julia_version", "Unknown"),
            "test_framework_version" => "1.0.0"
        ),
        "summary" => Dict(
            "total_files" => summary.total_files,
            "code_examples" => Dict(
                "total" => summary.total_code_blocks,
                "passed" => summary.code_blocks_passed,
                "failed" => summary.code_blocks_failed,
                "skipped" => summary.code_blocks_skipped
            ),
            "links" => Dict(
                "total" => summary.total_links,
                "valid" => summary.links_valid,
                "invalid" => summary.links_invalid
            ),
            "consistency" => Dict(
                "total_issues" => summary.consistency_issues,
                "errors" => summary.consistency_errors,
                "warnings" => summary.consistency_warnings
            ),
            "execution_time" => summary.execution_time
        ),
        "results" => get(results, "results", Dict())
    )
    
    mkpath(dirname(output_file))
    open(output_file, "w") do f
        JSON3.pretty(f, json_report)
    end
    
    @info "JSON report generated: $output_file"
end

"""
    generate_summary_report(results_file::String)

Generate a summary report and print to stdout.
"""
function generate_summary_report(results_file::String)
    if !isfile(results_file)
        @warn "Results file not found: $results_file"
        return
    end
    
    results = TOML.parsefile(results_file)
    summary = calculate_summary(results)
    
    println("📊 Planar Documentation Test Summary")
    println("=" ^ 50)
    println("Julia Version: $(get(results, "julia_version", "Unknown"))")
    println("Generated: $(Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))")
    println()
    
    # Code Examples
    println("📝 Code Examples:")
    println("  Total: $(summary.total_code_blocks)")
    println("  Passed: $(summary.code_blocks_passed) ✅")
    if summary.code_blocks_failed > 0
        println("  Failed: $(summary.code_blocks_failed) ❌")
    end
    if summary.code_blocks_skipped > 0
        println("  Skipped: $(summary.code_blocks_skipped) ⏭️")
    end
    println()
    
    # Links
    if summary.total_links > 0
        println("🔗 Link Validation:")
        println("  Total: $(summary.total_links)")
        println("  Valid: $(summary.links_valid) ✅")
        if summary.links_invalid > 0
            println("  Invalid: $(summary.links_invalid) ❌")
        end
        println()
    end
    
    # Consistency
    if summary.consistency_issues > 0
        println("📋 Content Consistency:")
        println("  Total Issues: $(summary.consistency_issues)")
        if summary.consistency_errors > 0
            println("  Errors: $(summary.consistency_errors) ❌")
        end
        if summary.consistency_warnings > 0
            println("  Warnings: $(summary.consistency_warnings) ⚠️")
        end
        println()
    end
    
    # Overall status
    overall_success = summary.code_blocks_failed == 0 && 
                     summary.links_invalid == 0 && 
                     summary.consistency_errors == 0
    
    println("⏱️  Execution Time: $(round(summary.execution_time, digits=2))s")
    println()
    println("🎯 Overall Status: $(overall_success ? "✅ PASSED" : "❌ FAILED")")
end

"""
    format_results_for_ci(results_file::String) -> String

Format results for CI systems (GitHub Actions, etc.).
"""
function format_results_for_ci(results_file::String)
    if !isfile(results_file)
        return "❌ Results file not found: $results_file"
    end
    
    results = TOML.parsefile(results_file)
    summary = calculate_summary(results)
    
    # Create CI-friendly output
    output_lines = String[]
    
    # Summary line
    overall_success = summary.code_blocks_failed == 0 && 
                     summary.links_invalid == 0 && 
                     summary.consistency_errors == 0
    
    status_emoji = overall_success ? "✅" : "❌"
    push!(output_lines, "$status_emoji Documentation Tests $(overall_success ? "PASSED" : "FAILED")")
    
    # Details
    push!(output_lines, "📝 Code Examples: $(summary.code_blocks_passed)/$(summary.total_code_blocks) passed")
    
    if summary.total_links > 0
        push!(output_lines, "🔗 Links: $(summary.links_valid)/$(summary.total_links) valid")
    end
    
    if summary.consistency_issues > 0
        push!(output_lines, "📋 Consistency: $(summary.consistency_issues) issues ($(summary.consistency_errors) errors)")
    end
    
    push!(output_lines, "⏱️ Time: $(round(summary.execution_time, digits=2))s")
    
    return join(output_lines, "\n")
end

end # module TestResultsReporter