"""
Test Results Reporter

This module provides functionality to generate comprehensive reports
from documentation test results, including:
- HTML reports for CI artifacts
- JSON reports for programmatic analysis
- Summary statistics and trends
"""
module TestResultsReporter

using JSON3
using TOML
using Dates

export generate_html_report, generate_json_report, generate_summary_report

"""
    TestSummary

Summary statistics for a test run.
"""
struct TestSummary
    total_files::Int
    total_blocks::Int
    passed::Int
    failed::Int
    skipped::Int
    execution_time::Float64
    julia_version::String
    timestamp::DateTime
end

"""
    generate_html_report(results_file::String, output_file::String)

Generate an HTML report from test results.
"""
function generate_html_report(results_file::String, output_file::String)
    results = TOML.parsefile(results_file)
    
    html_content = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Planar Documentation Test Results</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 20px; }
            .header { background-color: #f0f0f0; padding: 20px; border-radius: 5px; }
            .summary { margin: 20px 0; }
            .passed { color: green; }
            .failed { color: red; }
            .skipped { color: orange; }
            .test-section { margin: 20px 0; border: 1px solid #ddd; padding: 15px; }
            .file-results { margin: 10px 0; }
            .code-block { background-color: #f8f8f8; padding: 10px; margin: 5px 0; border-left: 3px solid #ddd; }
            .error { background-color: #ffe6e6; border-left-color: red; }
            .success { background-color: #e6ffe6; border-left-color: green; }
        </style>
    </head>
    <body>
        <div class="header">
            <h1>Planar Documentation Test Results</h1>
            <p><strong>Julia Version:</strong> $(get(results, "julia_version", "Unknown"))</p>
            <p><strong>Timestamp:</strong> $(get(results, "timestamp", "Unknown"))</p>
        </div>
        
        <div class="summary">
            <h2>Summary</h2>
    """
    
    # Add summary statistics
    test_results = get(results, "results", Dict())
    
    for (test_type, result) in test_results
        if haskey(result, "passed")
            status = result["passed"] ? "✅ PASSED" : "❌ FAILED"
            status_class = result["passed"] ? "passed" : "failed"
            html_content *= """
            <div class="test-section">
                <h3>$(uppercasefirst(replace(test_type, "_" => " "))) <span class="$status_class">$status</span></h3>
            """
            
            if haskey(result, "details")
                details = result["details"]
                html_content *= """
                <p><strong>Total Files:</strong> $(get(details, "total_files", 0))</p>
                <p><strong>Total Code Blocks:</strong> $(get(details, "total_blocks", 0))</p>
                <p><strong>Passed:</strong> <span class="passed">$(get(details, "passed", 0))</span></p>
                <p><strong>Failed:</strong> <span class="failed">$(get(details, "failed", 0))</span></p>
                <p><strong>Skipped:</strong> <span class="skipped">$(get(details, "skipped", 0))</span></p>
                """
            end
            
            html_content *= "</div>"
        elseif haskey(result, "skipped")
            html_content *= """
            <div class="test-section">
                <h3>$(uppercasefirst(replace(test_type, "_" => " "))) <span class="skipped">⏭️ SKIPPED</span></h3>
            </div>
            """
        end
    end
    
    html_content *= """
        </div>
    </body>
    </html>
    """
    
    write(output_file, html_content)
    @info "HTML report generated: $output_file"
end

"""
    generate_json_report(results_file::String, output_file::String)

Generate a JSON report from test results for programmatic analysis.
"""
function generate_json_report(results_file::String, output_file::String)
    results = TOML.parsefile(results_file)
    
    # Convert to JSON-friendly format
    json_results = Dict(
        "metadata" => Dict(
            "julia_version" => get(results, "julia_version", "unknown"),
            "timestamp" => get(results, "timestamp", "unknown"),
            "generator" => "Planar Documentation Test Framework"
        ),
        "summary" => Dict(),
        "details" => get(results, "results", Dict())
    )
    
    # Calculate summary statistics
    total_tests = 0
    total_passed = 0
    total_failed = 0
    total_skipped = 0
    
    for (test_type, result) in get(results, "results", Dict())
        if haskey(result, "details")
            details = result["details"]
            total_tests += get(details, "total_blocks", 0)
            total_passed += get(details, "passed", 0)
            total_failed += get(details, "failed", 0)
            total_skipped += get(details, "skipped", 0)
        end
    end
    
    json_results["summary"] = Dict(
        "total_tests" => total_tests,
        "passed" => total_passed,
        "failed" => total_failed,
        "skipped" => total_skipped,
        "success_rate" => total_tests > 0 ? round(total_passed / total_tests * 100, digits=2) : 0.0
    )
    
    open(output_file, "w") do f
        JSON3.pretty(f, json_results)
    end
    
    @info "JSON report generated: $output_file"
end

"""
    generate_summary_report(results_file::String)

Generate a concise summary report for console output.
"""
function generate_summary_report(results_file::String)
    results = TOML.parsefile(results_file)
    
    println("=" ^ 60)
    println("PLANAR DOCUMENTATION TEST SUMMARY")
    println("=" ^ 60)
    println("Julia Version: $(get(results, "julia_version", "Unknown"))")
    println("Timestamp: $(get(results, "timestamp", "Unknown"))")
    println()
    
    test_results = get(results, "results", Dict())
    
    for (test_type, result) in test_results
        test_name = uppercasefirst(replace(test_type, "_" => " "))
        
        if haskey(result, "passed")
            status = result["passed"] ? "✅ PASSED" : "❌ FAILED"
            println("$test_name: $status")
            
            if haskey(result, "details")
                details = result["details"]
                println("  Files: $(get(details, "total_files", 0))")
                println("  Blocks: $(get(details, "total_blocks", 0))")
                println("  Passed: $(get(details, "passed", 0))")
                println("  Failed: $(get(details, "failed", 0))")
                println("  Skipped: $(get(details, "skipped", 0))")
            end
        elseif haskey(result, "skipped")
            println("$test_name: ⏭️ SKIPPED")
        end
        println()
    end
    
    println("=" ^ 60)
end

end # module TestResultsReporter