#!/usr/bin/env julia

"""
Code Example Testing System for Planar Documentation

This script extracts and tests all Julia code examples from the documentation
to ensure they work with the current Planar version.
"""

using Dates
using Pkg

# Configuration
const DOCS_ROOT = joinpath(@__DIR__, "..", "src")
const REPORT_DIR = joinpath(@__DIR__, "..", "reports")
const TEST_DIR = joinpath(@__DIR__, "..", "test_examples")

# Code example test results
struct CodeExample
    file_path::String
    line_start::Int
    line_end::Int
    code::String
    language::String
    example_id::String
end

struct TestResult
    example::CodeExample
    status::String  # "passed", "failed", "skipped"
    output::String
    error_message::Union{String, Nothing}
    execution_time::Union{Float64, Nothing}
    timestamp::DateTime
end

struct CodeTestReport
    timestamp::DateTime
    total_examples::Int
    passed_examples::Int
    failed_examples::Int
    skipped_examples::Int
    results::Vector{TestResult}
    summary::Dict{String, Any}
end

# Utility functions
function ensure_directories()
    for dir in [REPORT_DIR, TEST_DIR]
        if !isdir(dir)
            mkpath(dir)
        end
    end
end

function extract_code_blocks(content::String, file_path::String)::Vector{CodeExample}
    examples = CodeExample[]
    lines = split(content, '\n')
    
    i = 1
    example_counter = 1
    
    while i <= length(lines)
        line = lines[i]
        
        # Look for code block start
        if startswith(strip(line), "```")
            # Extract language
            lang_match = match(r"```(\w+)", line)
            language = lang_match !== nothing ? lang_match.captures[1] : "text"
            
            # Only process Julia code blocks
            if language in ["julia", "jl"]
                start_line = i
                i += 1
                code_lines = String[]
                
                # Collect code until end of block
                while i <= length(lines) && !startswith(strip(lines[i]), "```")
                    push!(code_lines, lines[i])
                    i += 1
                end
                
                if i <= length(lines)  # Found closing ```
                    end_line = i
                    code = join(code_lines, '\n')
                    
                    # Skip empty code blocks
                    if !isempty(strip(code))
                        example_id = "$(basename(file_path))_example_$(example_counter)"
                        push!(examples, CodeExample(
                            file_path,
                            start_line,
                            end_line,
                            code,
                            language,
                            example_id
                        ))
                        example_counter += 1
                    end
                end
            end
        end
        i += 1
    end
    
    return examples
end

function should_skip_example(code::String)::Bool
    # Skip examples that are clearly not meant to be executed
    skip_patterns = [
        r"#\s*This is just an example",
        r"#\s*Not executable",
        r"#\s*Pseudo-?code",
        r"#\s*Example output",
        r"^\s*#.*only\s*$"i,
        r"using\s+NonExistentPackage",
        r"import\s+FakeModule"
    ]
    
    for pattern in skip_patterns
        if occursin(pattern, code)
            return true
        end
    end
    
    # Skip if it's just comments or empty
    non_comment_lines = filter(line -> !startswith(strip(line), "#") && !isempty(strip(line)), split(code, '\n'))
    return isempty(non_comment_lines)
end

function create_test_environment()
    # Create a temporary test environment
    test_project = joinpath(TEST_DIR, "Project.toml")
    
    if !isfile(test_project)
        # Create a minimal project for testing
        project_content = """
        name = "DocTestEnvironment"
        uuid = "12345678-1234-1234-1234-123456789abc"
        version = "0.1.0"
        
        [deps]
        """
        
        write(test_project, project_content)
    end
    
    return TEST_DIR
end

function test_code_example(example::CodeExample)::TestResult
    if should_skip_example(example.code)
        return TestResult(
            example,
            "skipped",
            "",
            "Skipped: Example marked as non-executable",
            nothing,
            now()
        )
    end
    
    # Create test file
    test_file = joinpath(TEST_DIR, "$(example.example_id).jl")
    
    # Wrap code in try-catch for better error handling
    wrapped_code = """
    # Auto-generated test for $(example.example_id)
    # Source: $(example.file_path):$(example.line_start)-$(example.line_end)
    
    try
        $(example.code)
        println("✅ Example executed successfully")
    catch e
        println("❌ Error: ", e)
        rethrow(e)
    end
    """
    
    write(test_file, wrapped_code)
    
    try
        start_time = time()
        
        # Run the test in the test environment
        result = read(`julia --project=$TEST_DIR $test_file`, String)
        
        execution_time = time() - start_time
        
        # Check if execution was successful
        if occursin("✅ Example executed successfully", result)
            return TestResult(
                example,
                "passed",
                result,
                nothing,
                execution_time,
                now()
            )
        else
            return TestResult(
                example,
                "failed",
                result,
                "Example did not complete successfully",
                execution_time,
                now()
            )
        end
        
    catch e
        return TestResult(
            example,
            "failed",
            "",
            string(e),
            nothing,
            now()
        )
    finally
        # Clean up test file
        if isfile(test_file)
            rm(test_file)
        end
    end
end

function find_markdown_files(root_dir::String)::Vector{String}
    files = String[]
    for (root, dirs, filenames) in walkdir(root_dir)
        for filename in filenames
            if endswith(filename, ".md")
                push!(files, joinpath(root, filename))
            end
        end
    end
    return files
end

function generate_code_test_report()::CodeTestReport
    ensure_directories()
    create_test_environment()
    
    markdown_files = find_markdown_files(DOCS_ROOT)
    all_examples = CodeExample[]
    
    println("🔍 Extracting code examples from documentation...")
    
    # Extract all code examples
    for file_path in markdown_files
        if isfile(file_path)
            content = read(file_path, String)
            examples = extract_code_blocks(content, file_path)
            append!(all_examples, examples)
            
            if !isempty(examples)
                relative_path = replace(file_path, DOCS_ROOT => "docs/src")
                println("  Found $(length(examples)) Julia code examples in $relative_path")
            end
        end
    end
    
    println("Found $(length(all_examples)) total Julia code examples")
    
    if isempty(all_examples)
        println("No Julia code examples found to test")
        return CodeTestReport(
            now(),
            0, 0, 0, 0,
            TestResult[],
            Dict("success_rate" => 100.0, "files_with_examples" => 0)
        )
    end
    
    println("\n🧪 Testing code examples...")
    
    # Test each example
    results = TestResult[]
    for (i, example) in enumerate(all_examples)
        relative_path = replace(example.file_path, DOCS_ROOT => "docs/src")
        println("  Testing example $i/$(length(all_examples)): $relative_path:$(example.line_start)")
        
        result = test_code_example(example)
        push!(results, result)
        
        # Show immediate result
        status_icon = result.status == "passed" ? "✅" : result.status == "failed" ? "❌" : "⏭️"
        println("    $status_icon $(result.status)")
        if result.status == "failed" && result.error_message !== nothing
            println("      Error: $(result.error_message)")
        end
    end
    
    # Calculate summary statistics
    passed = count(r -> r.status == "passed", results)
    failed = count(r -> r.status == "failed", results)
    skipped = count(r -> r.status == "skipped", results)
    
    success_rate = length(all_examples) > 0 ? round((passed / length(all_examples)) * 100, digits=2) : 100.0
    files_with_examples = length(unique(ex.file_path for ex in all_examples))
    
    summary = Dict(
        "success_rate" => success_rate,
        "files_with_examples" => files_with_examples,
        "avg_execution_time" => begin
            execution_times = [r.execution_time for r in results if r.execution_time !== nothing]
            isempty(execution_times) ? 0.0 : round(sum(execution_times) / length(execution_times), digits=3)
        end
    )
    
    return CodeTestReport(
        now(),
        length(all_examples),
        passed,
        failed,
        skipped,
        results,
        summary
    )
end

function save_test_report(report::CodeTestReport)
    ensure_directories()
    
    # Generate text report
    report_file = joinpath(REPORT_DIR, "code_examples_test_report.txt")
    
    open(report_file, "w") do io
        println(io, "Planar Documentation Code Examples Test Report")
        println(io, "Generated: $(report.timestamp)")
        println(io, "=" ^ 60)
        println(io, "")
        println(io, "Summary:")
        println(io, "  Total examples: $(report.total_examples)")
        println(io, "  Passed: $(report.passed_examples)")
        println(io, "  Failed: $(report.failed_examples)")
        println(io, "  Skipped: $(report.skipped_examples)")
        println(io, "  Success rate: $(report.summary["success_rate"])%")
        println(io, "  Files with examples: $(report.summary["files_with_examples"])")
        println(io, "  Average execution time: $(report.summary["avg_execution_time"])s")
        println(io, "")
        
        if report.failed_examples > 0
            println(io, "Failed Examples:")
            println(io, "-" ^ 40)
            for result in report.results
                if result.status == "failed"
                    relative_path = replace(result.example.file_path, DOCS_ROOT => "docs/src")
                    println(io, "")
                    println(io, "❌ $relative_path:$(result.example.line_start)-$(result.example.line_end)")
                    println(io, "   Example ID: $(result.example.example_id)")
                    if result.error_message !== nothing
                        println(io, "   Error: $(result.error_message)")
                    end
                    println(io, "   Code:")
                    for line in split(result.example.code, '\n')
                        println(io, "     $line")
                    end
                end
            end
        end
        
        if report.skipped_examples > 0
            println(io, "")
            println(io, "Skipped Examples:")
            println(io, "-" ^ 40)
            for result in report.results
                if result.status == "skipped"
                    relative_path = replace(result.example.file_path, DOCS_ROOT => "docs/src")
                    println(io, "⏭️  $relative_path:$(result.example.line_start)-$(result.example.line_end)")
                    if result.error_message !== nothing
                        println(io, "   Reason: $(result.error_message)")
                    end
                end
            end
        end
    end
    
    println("📄 Test report saved to: $report_file")
end

function generate_html_test_report(report::CodeTestReport)
    ensure_directories()
    
    html_file = joinpath(REPORT_DIR, "code_examples_dashboard.html")
    
    html_content = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Planar Documentation Code Examples Test Dashboard</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
            .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
            .header { text-align: center; margin-bottom: 30px; }
            .stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin-bottom: 30px; }
            .stat-card { background: #f8f9fa; padding: 20px; border-radius: 8px; text-align: center; }
            .stat-number { font-size: 2em; font-weight: bold; color: #007bff; }
            .stat-label { color: #666; margin-top: 5px; }
            .success-rate { font-size: 3em; font-weight: bold; }
            .rate-good { color: #28a745; }
            .rate-warning { color: #ffc107; }
            .rate-danger { color: #dc3545; }
            .example-list { margin-top: 30px; }
            .example-item { margin-bottom: 15px; padding: 15px; border: 1px solid #ddd; border-radius: 5px; }
            .example-header { font-weight: bold; margin-bottom: 10px; }
            .example-code { background: #f8f9fa; padding: 10px; border-radius: 4px; font-family: monospace; white-space: pre-wrap; margin: 10px 0; }
            .status-passed { color: #28a745; }
            .status-failed { color: #dc3545; }
            .status-skipped { color: #6c757d; }
            .filter-buttons { margin-bottom: 20px; text-align: center; }
            .filter-btn { padding: 8px 16px; margin: 0 5px; border: 1px solid #007bff; background: white; color: #007bff; cursor: pointer; border-radius: 4px; }
            .filter-btn.active { background: #007bff; color: white; }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <h1>🧪 Planar Documentation Code Examples Test Dashboard</h1>
                <p>Test report generated on $(report.timestamp)</p>
            </div>
            
            <div class="stats">
                <div class="stat-card">
                    <div class="stat-number success-rate $(report.summary["success_rate"] >= 90 ? "rate-good" : report.summary["success_rate"] >= 70 ? "rate-warning" : "rate-danger")">
                        $(report.summary["success_rate"])%
                    </div>
                    <div class="stat-label">Success Rate</div>
                </div>
                <div class="stat-card">
                    <div class="stat-number">$(report.total_examples)</div>
                    <div class="stat-label">Total Examples</div>
                </div>
                <div class="stat-card">
                    <div class="stat-number status-passed">$(report.passed_examples)</div>
                    <div class="stat-label">Passed</div>
                </div>
                <div class="stat-card">
                    <div class="stat-number status-failed">$(report.failed_examples)</div>
                    <div class="stat-label">Failed</div>
                </div>
                <div class="stat-card">
                    <div class="stat-number status-skipped">$(report.skipped_examples)</div>
                    <div class="stat-label">Skipped</div>
                </div>
                <div class="stat-card">
                    <div class="stat-number">$(report.summary["avg_execution_time"])s</div>
                    <div class="stat-label">Avg Execution Time</div>
                </div>
            </div>
            
            <div class="filter-buttons">
                <button class="filter-btn active" onclick="filterExamples('all')">All Examples</button>
                <button class="filter-btn" onclick="filterExamples('passed')">Passed</button>
                <button class="filter-btn" onclick="filterExamples('failed')">Failed</button>
                <button class="filter-btn" onclick="filterExamples('skipped')">Skipped</button>
            </div>
            
            <div class="example-list" id="exampleList">
    """
    
    for result in report.results
        relative_path = replace(result.example.file_path, DOCS_ROOT => "docs/src")
        status_class = "status-$(result.status)"
        status_icon = result.status == "passed" ? "✅" : result.status == "failed" ? "❌" : "⏭️"
        
        html_content *= """
                <div class="example-item" data-status="$(result.status)">
                    <div class="example-header">
                        $status_icon $relative_path:$(result.example.line_start)-$(result.example.line_end)
                        <span class="$status_class">($(uppercase(result.status)))</span>
                    </div>
        """
        
        if result.execution_time !== nothing
            html_content *= "<div>Execution time: $(result.execution_time)s</div>"
        end
        
        if result.error_message !== nothing
            html_content *= "<div style='color: #dc3545; margin: 5px 0;'>Error: $(result.error_message)</div>"
        end
        
        html_content *= """
                    <div class="example-code">$(result.example.code)</div>
                </div>
        """
    end
    
    html_content *= """
            </div>
        </div>
        
        <script>
            function filterExamples(status) {
                const buttons = document.querySelectorAll('.filter-btn');
                const examples = document.querySelectorAll('.example-item');
                
                buttons.forEach(btn => btn.classList.remove('active'));
                event.target.classList.add('active');
                
                examples.forEach(example => {
                    const exampleStatus = example.getAttribute('data-status');
                    if (status === 'all' || exampleStatus === status) {
                        example.style.display = 'block';
                    } else {
                        example.style.display = 'none';
                    }
                });
            }
        </script>
    </body>
    </html>
    """
    
    write(html_file, html_content)
    println("📊 HTML dashboard saved to: $html_file")
end

# Main execution
function main()
    println("🧪 Starting code example testing for Planar documentation...")
    
    report = generate_code_test_report()
    
    println("\n📊 Test Summary:")
    println("  Total examples: $(report.total_examples)")
    println("  Passed: $(report.passed_examples)")
    println("  Failed: $(report.failed_examples)")
    println("  Skipped: $(report.skipped_examples)")
    println("  Success rate: $(report.summary["success_rate"])%")
    
    save_test_report(report)
    generate_html_test_report(report)
    
    if report.failed_examples > 0
        println("\n⚠️  $(report.failed_examples) code examples failed!")
        println("Check the detailed report at: $(joinpath(REPORT_DIR, "code_examples_test_report.txt"))")
        exit(1)
    else
        println("\n✅ All code examples passed!")
        exit(0)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end