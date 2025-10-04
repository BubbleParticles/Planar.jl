#!/usr/bin/env julia

"""
Code Example Testing System for Planar Documentation
"""

using Dates

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
        r"SomeHypotheticalFunction"
    ]
    
    for pattern in skip_patterns
        if occursin(pattern, code)
            return true
        end
    end
    
    return false
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
        result = read(`julia $test_file`, String)
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

function generate_code_test_report()
    ensure_directories()
    
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
        return
    end
    
    println("\n🧪 Testing code examples...")
    
    # Test each example
    results = TestResult[]
    passed = 0
    failed = 0
    skipped = 0
    
    for (i, example) in enumerate(all_examples)
        relative_path = replace(example.file_path, DOCS_ROOT => "docs/src")
        println("  Testing example $i/$(length(all_examples)): $relative_path:$(example.line_start)")
        
        result = test_code_example(example)
        push!(results, result)
        
        # Show immediate result and count
        if result.status == "passed"
            println("    ✅ passed")
            passed += 1
        elseif result.status == "failed"
            println("    ❌ failed: $(result.error_message)")
            failed += 1
        else
            println("    ⏭️ skipped")
            skipped += 1
        end
    end
    
    # Generate summary
    success_rate = length(all_examples) > 0 ? round((passed / length(all_examples)) * 100, digits=2) : 100.0
    
    println("\n📊 Test Summary:")
    println("  Total examples: $(length(all_examples))")
    println("  Passed: $passed")
    println("  Failed: $failed")
    println("  Skipped: $skipped")
    println("  Success rate: $success_rate%")
    
    # Save simple report
    report_file = joinpath(REPORT_DIR, "code_examples_test_report.txt")
    open(report_file, "w") do io
        println(io, "Planar Documentation Code Examples Test Report")
        println(io, "Generated: $(now())")
        println(io, "=" ^ 60)
        println(io, "")
        println(io, "Summary:")
        println(io, "  Total examples: $(length(all_examples))")
        println(io, "  Passed: $passed")
        println(io, "  Failed: $failed")
        println(io, "  Skipped: $skipped")
        println(io, "  Success rate: $success_rate%")
        println(io, "")
        
        if failed > 0
            println(io, "Failed Examples:")
            for result in results
                if result.status == "failed"
                    relative_path = replace(result.example.file_path, DOCS_ROOT => "docs/src")
                    println(io, "❌ $relative_path:$(result.example.line_start)")
                    println(io, "   Error: $(result.error_message)")
                end
            end
        end
    end
    
    println("📄 Report saved to: $report_file")
    
    if failed > 0
        println("\n⚠️  $failed code examples failed!")
        exit(1)
    else
        println("\n✅ All code examples passed!")
        exit(0)
    end
end

# Main execution
function main()
    println("🧪 Starting code example testing for Planar documentation...")
    generate_code_test_report()
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
