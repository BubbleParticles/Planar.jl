"""
Documentation Testing Framework

This module provides functionality to extract, validate, and test code examples
from documentation files. It supports:
- Extracting Julia code blocks from markdown files
- Running code examples in isolated environments
- Validating expected outputs
- Integration with CI systems
- Multi-version Julia testing
- Output validation with flexible matching
"""
module DocTestFramework

using Test
using Markdown
using Pkg
using Suppressor
using TOML

export extract_code_blocks, test_code_block, test_documentation_file, 
       run_all_doc_tests, CodeBlock, TestResult, load_config, 
       validate_output, normalize_output

"""
    CodeBlock

Represents a code block extracted from documentation.

# Fields
- `code::String`: The Julia code to execute
- `file::String`: Source file path
- `line::Int`: Line number in source file
- `expected_output::Union{String, Nothing}`: Expected output (if specified)
- `requirements::Vector{String}`: Required packages/modules
- `skip_test::Bool`: Whether to skip testing this block
- `timeout::Int`: Maximum execution time in seconds
"""
struct CodeBlock
    code::String
    file::String
    line::Int
    expected_output::Union{String, Nothing}
    requirements::Vector{String}
    skip_test::Bool
    timeout::Int
    
    function CodeBlock(code, file, line; 
                      expected_output=nothing, 
                      requirements=String[], 
                      skip_test=false, 
                      timeout=30)
        new(code, file, line, expected_output, requirements, skip_test, timeout)
    end
end

"""
    TestResult

Result of testing a code block.

# Fields
- `success::Bool`: Whether the test passed
- `output::String`: Actual output from execution
- `error::Union{Exception, Nothing}`: Error if execution failed
- `execution_time::Float64`: Time taken to execute
"""
struct TestResult
    success::Bool
    output::String
    error::Union{Exception, Nothing}
    execution_time::Float64
end

"""
    load_config(config_path::String="docs/test/config.toml") -> Dict

Load testing configuration from TOML file.
"""
function load_config(config_path::String="docs/test/config.toml")
    if isfile(config_path)
        return TOML.parsefile(config_path)
    else
        # Return default configuration
        return Dict(
            "general" => Dict(
                "project_path" => "Planar",
                "docs_path" => "docs/src",
                "default_timeout" => 30,
                "parallel" => false
            ),
            "code_examples" => Dict(
                "enabled" => true,
                "skip_files" => String[],
                "skip_patterns" => String[],
                "global_requirements" => ["Planar", "Test"]
            ),
            "output_validation" => Dict(
                "enabled" => true,
                "on_mismatch" => "warn",
                "normalize_whitespace" => true,
                "ignore_patterns" => [r"\d+\.\d+s", r"@ \w+"]
            )
        )
    end
end

"""
    normalize_output(output::String, config::Dict) -> String

Normalize output string according to configuration rules.
"""
function normalize_output(output::String, config::Dict)
    normalized = output
    
    # Get output validation config
    output_config = get(config, "output_validation", Dict())
    
    # Normalize whitespace if enabled
    if get(output_config, "normalize_whitespace", true)
        normalized = strip(replace(normalized, r"\s+" => " "))
    end
    
    # Apply ignore patterns
    ignore_patterns = get(output_config, "ignore_patterns", [])
    for pattern in ignore_patterns
        if pattern isa String
            pattern = Regex(pattern)
        end
        normalized = replace(normalized, pattern => "")
    end
    
    return strip(normalized)
end

"""
    validate_output(actual::String, expected::String, config::Dict) -> Bool

Validate actual output against expected output using configuration rules.
"""
function validate_output(actual::String, expected::String, config::Dict)
    actual_normalized = normalize_output(actual, config)
    expected_normalized = normalize_output(expected, config)
    return actual_normalized == expected_normalized
end

"""
    extract_code_blocks(file_path::String; config::Dict=load_config()) -> Vector{CodeBlock}

Extract all Julia code blocks from a markdown file.

Supports special comments for test configuration:
- `# DOCTEST_SKIP` - Skip this code block
- `# DOCTEST_REQUIRES: Package1, Package2` - Required packages
- `# DOCTEST_TIMEOUT: 60` - Custom timeout in seconds
- `# DOCTEST_OUTPUT:` followed by expected output

The function also respects configuration settings for skipping files and patterns.
"""
function extract_code_blocks(file_path::String; config::Dict=load_config())
    # Check if file should be skipped based on configuration
    code_config = get(config, "code_examples", Dict())
    skip_files = get(code_config, "skip_files", String[])
    
    for skip_pattern in skip_files
        if occursin(skip_pattern, file_path)
            @debug "Skipping file $file_path (matches pattern: $skip_pattern)"
            return CodeBlock[]
        end
    end
    
    content = read(file_path, String)
    blocks = CodeBlock[]
    
    # Get global requirements and default timeout from config
    global_requirements = get(code_config, "global_requirements", String[])
    default_timeout = get(get(config, "general", Dict()), "default_timeout", 30)
    skip_patterns = get(code_config, "skip_patterns", String[])
    
    # Split content into lines for line tracking
    lines = split(content, '\n')
    current_line = 1
    
    for line in lines
        current_line += 1
        
        # Look for Julia code block start
        if startswith(strip(line), "```julia")
            code_lines = String[]
            block_start_line = current_line
            skip_test = false
            requirements = copy(global_requirements)
            timeout = default_timeout
            expected_output = nothing
            
            # Continue reading until end of code block
            while current_line < length(lines)
                current_line += 1
                line = lines[current_line]
                
                if startswith(strip(line), "```")
                    break
                end
                
                # Check for skip patterns from config
                for skip_pattern in skip_patterns
                    if occursin(skip_pattern, line)
                        skip_test = true
                        break
                    end
                end
                
                # Check for special comments
                if contains(line, "# DOCTEST_SKIP")
                    skip_test = true
                elseif contains(line, "# DOCTEST_REQUIRES:")
                    req_match = match(r"# DOCTEST_REQUIRES:\s*(.+)", line)
                    if req_match !== nothing
                        additional_reqs = [strip(r) for r in split(req_match.captures[1], ",")]
                        requirements = vcat(requirements, additional_reqs)
                    end
                elseif contains(line, "# DOCTEST_TIMEOUT:")
                    timeout_match = match(r"# DOCTEST_TIMEOUT:\s*(\d+)", line)
                    if timeout_match !== nothing
                        timeout = parse(Int, timeout_match.captures[1])
                    end
                elseif contains(line, "# DOCTEST_OUTPUT:")
                    # Start collecting expected output
                    output_lines = String[]
                    while current_line < length(lines)
                        current_line += 1
                        next_line = lines[current_line]
                        if startswith(strip(next_line), "```") || 
                           startswith(strip(next_line), "#") && !startswith(strip(next_line), "# ")
                            current_line -= 1  # Back up one line
                            break
                        end
                        if startswith(next_line, "# ")
                            push!(output_lines, next_line[3:end])
                        end
                    end
                    expected_output = join(output_lines, "\n")
                else
                    push!(code_lines, line)
                end
            end
            
            if !isempty(code_lines)
                code = join(code_lines, "\n")
                push!(blocks, CodeBlock(code, file_path, block_start_line;
                                      expected_output=expected_output,
                                      requirements=requirements,
                                      skip_test=skip_test,
                                      timeout=timeout))
            end
        end
    end
    
    return blocks
end

"""
    test_code_block(block::CodeBlock; project_path="Planar", config::Dict=load_config()) -> TestResult

Test a single code block by executing it in an isolated environment.
"""
function test_code_block(block::CodeBlock; project_path="Planar", config::Dict=load_config())
    if block.skip_test
        return TestResult(true, "SKIPPED", nothing, 0.0)
    end
    
    start_time = time()
    
    try
        # Create temporary test environment
        temp_env = mktempdir()
        
        # Set up test environment with required packages
        test_code = """
        using Pkg
        Pkg.activate("$project_path")
        
        # Load required packages
        $(join(["using " * req for req in block.requirements], "\n"))
        
        # Execute the code block
        $(block.code)
        """
        
        # Execute with timeout and capture output
        output = ""
        error = nothing
        
        try
            # Use @capture to get output
            output = @capture_out begin
                # Create a temporary file with the test code
                temp_file = joinpath(temp_env, "test_block.jl")
                write(temp_file, test_code)
                
                # Execute with timeout
                task = @async include(temp_file)
                
                # Wait for completion or timeout
                if !istaskdone(task)
                    Timer(block.timeout) do timer
                        if !istaskdone(task)
                            Base.throwto(task, InterruptException())
                        end
                    end
                end
                
                fetch(task)
            end
        catch e
            error = e
            output = string(e)
        finally
            # Clean up temporary environment
            rm(temp_env, recursive=true, force=true)
        end
        
        execution_time = time() - start_time
        
        # Check if output matches expected (if specified)
        success = error === nothing
        if success && block.expected_output !== nothing
            # Use enhanced output validation
            success = validate_output(output, block.expected_output, config)
            
            if !success
                output_config = get(config, "output_validation", Dict())
                on_mismatch = get(output_config, "on_mismatch", "warn")
                
                if on_mismatch == "warn"
                    @warn "Output mismatch in $(block.file):$(block.line)" expected=block.expected_output actual=output
                    success = true  # Don't fail the test, just warn
                elseif on_mismatch == "error"
                    success = false
                end
            end
        end
        
        return TestResult(success, output, error, execution_time)
        
    catch e
        execution_time = time() - start_time
        return TestResult(false, "", e, execution_time)
    end
end

"""
    test_documentation_file(file_path::String; project_path="Planar", config::Dict=load_config()) -> Dict{Int, TestResult}

Test all code blocks in a documentation file.
Returns a dictionary mapping line numbers to test results.
"""
function test_documentation_file(file_path::String; project_path="Planar", config::Dict=load_config())
    blocks = extract_code_blocks(file_path; config=config)
    results = Dict{Int, TestResult}()
    
    @info "Testing $(length(blocks)) code blocks in $file_path"
    
    for block in blocks
        @debug "Testing code block at line $(block.line)"
        result = test_code_block(block; project_path=project_path, config=config)
        results[block.line] = result
        
        if !result.success && result.error !== nothing
            @warn "Code block at line $(block.line) failed: $(result.error)"
        end
    end
    
    return results
end

"""
    run_all_doc_tests(docs_dir::String="docs/src"; project_path="Planar", config::Dict=load_config()) -> Bool

Run tests on all documentation files in the specified directory.
Returns true if all tests pass, false otherwise.
"""
function run_all_doc_tests(docs_dir::String="docs/src"; project_path="Planar", config::Dict=load_config())
    all_passed = true
    total_blocks = 0
    total_passed = 0
    total_failed = 0
    total_skipped = 0
    
    @info "Starting documentation tests in $docs_dir"
    
    # Find all markdown files
    md_files = String[]
    for (root, dirs, files) in walkdir(docs_dir)
        for file in files
            if endswith(file, ".md")
                push!(md_files, joinpath(root, file))
            end
        end
    end
    
    @info "Found $(length(md_files)) markdown files to test"
    
    for file_path in md_files
        @info "Testing file: $file_path"
        
        try
            results = test_documentation_file(file_path; project_path=project_path, config=config)
            
            for (line, result) in results
                total_blocks += 1
                
                if result.output == "SKIPPED"
                    total_skipped += 1
                elseif result.success
                    total_passed += 1
                else
                    total_failed += 1
                    all_passed = false
                    @error "Failed code block in $file_path at line $line: $(result.error)"
                end
            end
            
        catch e
            @error "Error processing file $file_path: $e"
            all_passed = false
        end
    end
    
    @info """
    Documentation test summary:
    - Total code blocks: $total_blocks
    - Passed: $total_passed
    - Failed: $total_failed
    - Skipped: $total_skipped
    """
    
    return all_passed
end

end # module DocTestFramework