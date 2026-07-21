#!/usr/bin/env julia

"""
Code Example Validator for Planar Documentation

This script extracts and validates all Julia code examples from the documentation
to ensure they work with the current version of Planar.
"""

using Pkg
using Markdown
using Test

const DOCS_DIR = "docs/src"
const REPORT_FILE = "docs/maintenance/code-validation-report.md"

struct CodeExample
    file::String
    line_start::Int
    line_end::Int
    code::String
    language::String
end

"""
Extract code blocks from a markdown file
"""
function extract_code_blocks(filepath::String)::Vector{CodeExample}
    examples = CodeExample[]
    
    if !isfile(filepath)
        return examples
    end
    
    content = read(filepath, String)
    lines = split(content, '\n')
    
    in_code_block = false
    code_language = ""
    code_lines = String[]
    start_line = 0
    
    for (i, line) in enumerate(lines)
        if startswith(line, "```")
            if in_code_block
                # End of code block
                if code_language == "julia" && !isempty(code_lines)
                    code = join(code_lines, '\n')
                    push!(examples, CodeExample(filepath, start_line, i, code, code_language))
                end
                in_code_block = false
                code_language = ""
                code_lines = String[]
            else
                # Start of code block
                in_code_block = true
                start_line = i
                # Extract language from ```language
                lang_match = match(r"```(\w+)", line)
                code_language = lang_match !== nothing ? lang_match.captures[1] : ""
            end
        elseif in_code_block
            push!(code_lines, line)
        end
    end
    
    return examples
end

"""
Test a Julia code example
"""
function test_code_example(example::CodeExample)::Tuple{Bool, String}
    try
        # Create a temporary module to isolate the code
        temp_module = Module()
        
        # Add common imports that are typically available
        Core.eval(temp_module, :(using Planar))
        
        # Try to evaluate the code
        result = Core.eval(temp_module, Meta.parse(example.code))
        
        return true, "Success"
    catch e
        return false, string(e)
    end
end

"""
Generate validation report
"""
function generate_report(results::Vector{Tuple{CodeExample, Bool, String}})
    open(REPORT_FILE, "w") do io
        println(io, "# Code Example Validation Report - $(now())")
        println(io)
        
        total_examples = length(results)
        passed_examples = count(r -> r[2], results)
        failed_examples = total_examples - passed_examples
        
        println(io, "## Summary")
        println(io)
        println(io, "- **Total Examples**: $total_examples")
        println(io, "- **Passed**: $passed_examples")
        println(io, "- **Failed**: $failed_examples")
        println(io, "- **Success Rate**: $(round(passed_examples/total_examples*100, digits=1))%")
        println(io)
        
        if failed_examples > 0
            println(io, "## Failed Examples")
            println(io)
            
            for (example, success, message) in results
                if !success
                    println(io, "### $(example.file):$(example.line_start)-$(example.line_end)")
                    println(io)
                    println(io, "**Error**: $message")
                    println(io)
                    println(io, "```julia")
                    println(io, example.code)
                    println(io, "```")
                    println(io)
                end
            end
        end
        
        println(io, "## All Results")
        println(io)
        println(io, "| File | Lines | Status | Message |")
        println(io, "|------|-------|--------|---------|")
        
        for (example, success, message) in results
            status = success ? "✅ Pass" : "❌ Fail"
            # Escape pipe characters in message
            safe_message = replace(message, "|" => "\\|")
            println(io, "| $(example.file) | $(example.line_start)-$(example.line_end) | $status | $safe_message |")
        end
    end
end

"""
Main validation function
"""
function validate_documentation()
    println("Starting code example validation...")
    
    # Ensure we're in the right project environment
    if !isfile("Project.toml")
        error("Please run this script from the Planar.jl root directory")
    end
    
    # Activate the project
    Pkg.activate(".")
    
    # Find all markdown files
    markdown_files = String[]
    for (root, dirs, files) in walkdir(DOCS_DIR)
        for file in files
            if endswith(file, ".md")
                push!(markdown_files, joinpath(root, file))
            end
        end
    end
    
    println("Found $(length(markdown_files)) markdown files")
    
    # Extract all code examples
    all_examples = CodeExample[]
    for file in markdown_files
        examples = extract_code_blocks(file)
        append!(all_examples, examples)
        if !isempty(examples)
            println("  $(file): $(length(examples)) Julia code examples")
        end
    end
    
    println("Found $(length(all_examples)) Julia code examples total")
    
    # Test each example
    results = Tuple{CodeExample, Bool, String}[]
    for (i, example) in enumerate(all_examples)
        print("Testing example $i/$(length(all_examples))... ")
        success, message = test_code_example(example)
        push!(results, (example, success, message))
        println(success ? "✅" : "❌")
    end
    
    # Create maintenance directory if needed
    mkpath(dirname(REPORT_FILE))
    
    # Generate report
    generate_report(results)
    
    # Print summary
    total = length(results)
    passed = count(r -> r[2], results)
    failed = total - passed
    
    println("\n" * "="^50)
    println("VALIDATION COMPLETE")
    println("="^50)
    println("Total examples: $total")
    println("Passed: $passed")
    println("Failed: $failed")
    println("Success rate: $(round(passed/total*100, digits=1))%")
    println("\nDetailed report saved to: $REPORT_FILE")
    
    # Exit with error code if any examples failed
    if failed > 0
        println("\n⚠️  Some code examples failed validation!")
        exit(1)
    else
        println("\n✅ All code examples passed validation!")
        exit(0)
    end
end

# Run validation if script is executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    validate_documentation()
end