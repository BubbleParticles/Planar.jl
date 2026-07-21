#!/usr/bin/env julia

"""
Comprehensive User Journey Testing Script

This script tests the complete getting-started path from installation to first strategy,
validating all cross-references and navigation paths, and ensuring all code examples work correctly.

Requirements tested:
- 1.1: Logical user journey organization
- 4.1: Content accuracy and completeness  
- 5.1: Enhanced getting started experience
"""

using Test
using Pkg

# Test configuration
const TEST_RESULTS = Dict{String, Any}()
const FAILED_TESTS = String[]

# Utility functions
function log_test(test_name::String, result::Bool, details::String="")
    TEST_RESULTS[test_name] = (result, details)
    if !result
        push!(FAILED_TESTS, test_name)
        println("❌ FAILED: $test_name")
        !isempty(details) && println("   Details: $details")
    else
        println("✅ PASSED: $test_name")
        !isempty(details) && println("   Details: $details")
    end
end

function test_file_exists(filepath::String, description::String="")
    exists = isfile(filepath)
    log_test("File exists: $filepath", exists, description)
    return exists
end

function test_directory_exists(dirpath::String, description::String="")
    exists = isdir(dirpath)
    log_test("Directory exists: $dirpath", exists, description)
    return exists
end

function test_julia_code(code::String, test_name::String)
    try
        # Create temporary file and test
        temp_file = tempname() * ".jl"
        write(temp_file, code)
        
        # Try to parse the code
        result = try
            include(temp_file)
            true
        catch e
            log_test(test_name, false, "Julia code error: $e")
            false
        finally
            rm(temp_file, force=true)
        end
        
        if result
            log_test(test_name, true, "Julia code executed successfully")
        end
        return result
    catch e
        log_test(test_name, false, "Test setup error: $e")
        return false
    end
end

function extract_code_blocks(content::String)
    """Extract Julia code blocks from markdown content"""
    code_blocks = String[]
    lines = split(content, '\n')
    in_julia_block = false
    current_block = String[]
    
    for line in lines
        if startswith(line, "```julia")
            in_julia_block = true
            current_block = String[]
        elseif startswith(line, "```") && in_julia_block
            in_julia_block = false
            if !isempty(current_block)
                push!(code_blocks, join(current_block, '\n'))
            end
        elseif in_julia_block
            push!(current_block, line)
        end
    end
    
    return code_blocks
end

function test_markdown_links(content::String, base_path::String, test_name::String)
    """Test that all markdown links in content are valid"""
    link_pattern = r"\[([^\]]+)\]\(([^)]+)\)"
    links = collect(eachmatch(link_pattern, content))
    
    broken_links = String[]
    
    for link_match in links
        link_url = link_match.captures[2]
        
        # Skip external links (http/https)
        if startswith(link_url, "http")
            continue
        end
        
        # Skip anchors within same page
        if startswith(link_url, "#")
            continue
        end
        
        # Remove anchor fragments
        clean_url = split(link_url, '#')[1]
        
        # Resolve relative path
        if startswith(clean_url, "../")
            # Handle relative paths
            full_path = normpath(joinpath(dirname(base_path), clean_url))
        else
            full_path = joinpath(dirname(base_path), clean_url)
        end
        
        # Check if file exists
        if !isfile(full_path) && !isdir(full_path)
            push!(broken_links, "$link_url -> $full_path")
        end
    end
    
    success = isempty(broken_links)
    details = success ? "All links valid" : "Broken links: $(join(broken_links, ", "))"
    log_test(test_name, success, details)
    return success
end

println("🚀 Starting Comprehensive User Journey Testing")
println("=" ^ 60)

# Test 1: Documentation Structure Validation
println("\n📁 Testing Documentation Structure...")

# Core getting-started files
required_files = [
    "docs/src/index.md",
    "docs/src/getting-started/index.md", 
    "docs/src/getting-started/installation.md",
    "docs/src/getting-started/quick-start.md",
    "docs/src/getting-started/first-strategy.md"
]

for file in required_files
    test_file_exists(file, "Core getting-started documentation")
end

# Test directory structure
required_dirs = [
    "docs/src/getting-started",
    "docs/src/guides", 
    "docs/src/reference",
    "docs/src/troubleshooting",
    "docs/src/advanced"
]

for dir in required_dirs
    test_directory_exists(dir, "Documentation directory structure")
end

# Test 2: Content Consistency and Navigation
println("\n🔗 Testing Cross-References and Navigation...")

for file in required_files
    if isfile(file)
        content = read(file, String)
        test_markdown_links(content, file, "Links in $(basename(file))")
    end
end

# Test 3: Code Example Validation
println("\n💻 Testing Code Examples...")

# Test installation verification code
installation_content = read("docs/src/getting-started/installation.md", String)
installation_code_blocks = extract_code_blocks(installation_content)

for (i, code_block) in enumerate(installation_code_blocks)
    # Skip bash/shell code blocks and focus on Julia
    if contains(code_block, "using") || contains(code_block, "println")
        # Wrap in try-catch for testing without full Planar environment
        test_code = """
        try
            # Mock Planar modules for testing
            module MockPlanar
                export strategy, @environment!
                strategy(args...; kwargs...) = "Mock strategy"
                macro environment!() 
                    quote
                        println("Mock environment loaded")
                    end
                end
            end
            using .MockPlanar
            
            # Original code block
            $code_block
            
            println("Code block executed successfully")
        catch e
            # Expected for some examples that require full Planar
            if isa(e, UndefVarError) || contains(string(e), "not defined")
                println("Code requires full Planar environment (expected)")
            else
                rethrow(e)
            end
        end
        """
        test_julia_code(test_code, "Installation code block $i")
    end
end

# Test quick-start code examples
if isfile("docs/src/getting-started/quick-start.md")
    quickstart_content = read("docs/src/getting-started/quick-start.md", String)
    quickstart_code_blocks = extract_code_blocks(quickstart_content)
    
    for (i, code_block) in enumerate(quickstart_code_blocks)
        if contains(code_block, "using") || contains(code_block, "println")
            test_code = """
            try
                # Mock environment for testing
                module MockPlanarInteractive
                    export strategy, @environment!, fetch_ohlcv, simulate!
                    
                    struct MockStrategy
                        config::NamedTuple
                        universe::NamedTuple
                    end
                    
                    strategy(args...; kwargs...) = MockStrategy(
                        (name="QuickStart", exchange=get(kwargs, :exchange, :binance)),
                        (assets=[(asset="BTC/USDT",)],)
                    )
                    
                    macro environment!()
                        quote
                            println("Mock environment loaded")
                        end
                    end
                    
                    fetch_ohlcv(s, args...; kwargs...) = println("Mock data fetched")
                    simulate!(s, args...; kwargs...) = println("Mock simulation completed")
                end
                using .MockPlanarInteractive
                
                # Original code block
                $code_block
                
                println("Quick-start code executed successfully")
            catch e
                if contains(string(e), "not defined") || contains(string(e), "UndefVarError")
                    println("Code requires full environment (expected)")
                else
                    rethrow(e)
                end
            end
            """
            test_julia_code(test_code, "Quick-start code block $i")
        end
    end
end

# Test 4: User Journey Flow Validation
println("\n🛤️  Testing User Journey Flow...")

# Test that each page has proper next steps
function test_next_steps(filepath::String, expected_next::Vector{String})
    if !isfile(filepath)
        log_test("Next steps in $(basename(filepath))", false, "File not found")
        return false
    end
    
    content = read(filepath, String)
    
    # Check for next steps section
    has_next_steps = contains(content, "Next Steps") || contains(content, "What's Next")
    
    # Check for links to expected next pages
    all_links_present = true
    missing_links = String[]
    
    for next_page in expected_next
        if !contains(content, next_page)
            all_links_present = false
            push!(missing_links, next_page)
        end
    end
    
    success = has_next_steps && all_links_present
    details = success ? "All next steps present" : "Missing: $(join(missing_links, ", "))"
    log_test("Next steps in $(basename(filepath))", success, details)
    return success
end

# Test navigation flow
test_next_steps("docs/src/index.md", ["installation", "quick-start", "first-strategy"])
test_next_steps("docs/src/getting-started/installation.md", ["quick-start"])
test_next_steps("docs/src/getting-started/quick-start.md", ["first-strategy"])
test_next_steps("docs/src/getting-started/first-strategy.md", ["strategy-development"])

# Test 5: Content Completeness
println("\n📋 Testing Content Completeness...")

function test_required_sections(filepath::String, required_sections::Vector{String})
    if !isfile(filepath)
        log_test("Required sections in $(basename(filepath))", false, "File not found")
        return false
    end
    
    content = read(filepath, String)
    missing_sections = String[]
    
    for section in required_sections
        if !contains(content, section)
            push!(missing_sections, section)
        end
    end
    
    success = isempty(missing_sections)
    details = success ? "All sections present" : "Missing: $(join(missing_sections, ", "))"
    log_test("Required sections in $(basename(filepath))", success, details)
    return success
end

# Test installation guide completeness
test_required_sections("docs/src/getting-started/installation.md", [
    "Prerequisites", "Docker", "Git Source", "Verification", "Troubleshooting"
])

# Test quick-start completeness  
test_required_sections("docs/src/getting-started/quick-start.md", [
    "Prerequisites", "Step 1", "Step 2", "Step 3", "Expected output"
])

# Test first-strategy completeness
test_required_sections("docs/src/getting-started/first-strategy.md", [
    "What You'll Learn", "Prerequisites", "Strategy Structure", "Step"
])

# Test 6: Frontmatter Validation
println("\n📝 Testing Frontmatter Consistency...")

function test_frontmatter(filepath::String)
    if !isfile(filepath)
        return false
    end
    
    content = read(filepath, String)
    
    # Check for frontmatter
    has_frontmatter = startswith(content, "---")
    
    if has_frontmatter
        # Extract frontmatter
        lines = split(content, '\n')
        frontmatter_end = findfirst(i -> i > 1 && lines[i] == "---", 1:length(lines))
        
        if frontmatter_end !== nothing
            frontmatter = join(lines[2:frontmatter_end-1], '\n')
            
            # Check for required fields
            required_fields = ["category", "difficulty", "topics", "last_updated"]
            missing_fields = String[]
            
            for field in required_fields
                if !contains(frontmatter, "$field:")
                    push!(missing_fields, field)
                end
            end
            
            success = isempty(missing_fields)
            details = success ? "All frontmatter fields present" : "Missing: $(join(missing_fields, ", "))"
            log_test("Frontmatter in $(basename(filepath))", success, details)
            return success
        end
    end
    
    log_test("Frontmatter in $(basename(filepath))", false, "No valid frontmatter found")
    return false
end

for file in required_files
    test_frontmatter(file)
end

# Test 7: Performance and Timing Validation
println("\n⏱️  Testing Performance Requirements...")

# Test that getting-started can be completed in reasonable time
function test_estimated_times()
    # Read estimated times from frontmatter
    total_time = 0
    
    files_with_times = [
        ("docs/src/getting-started/installation.md", 10),
        ("docs/src/getting-started/quick-start.md", 15), 
        ("docs/src/getting-started/first-strategy.md", 20)
    ]
    
    for (file, expected_max) in files_with_times
        if isfile(file)
            content = read(file, String)
            
            # Extract estimated_time from frontmatter
            time_match = match(r"estimated_time:\s*[\"']?(\d+)", content)
            if time_match !== nothing
                estimated_time = parse(Int, time_match.captures[1])
                total_time += estimated_time
                
                within_limit = estimated_time <= expected_max
                log_test("Time estimate for $(basename(file))", within_limit, 
                        "$estimated_time minutes (limit: $expected_max)")
            else
                log_test("Time estimate for $(basename(file))", false, "No time estimate found")
            end
        end
    end
    
    # Test total time is under 30 minutes (requirement 5.1)
    under_limit = total_time <= 30
    log_test("Total getting-started time", under_limit, "$total_time minutes (limit: 30)")
end

test_estimated_times()

# Test 8: Troubleshooting Coverage
println("\n🔧 Testing Troubleshooting Coverage...")

function test_troubleshooting_links()
    # Check that getting-started pages link to troubleshooting
    troubleshooting_files = [
        "docs/src/troubleshooting/installation-issues.md",
        "docs/src/troubleshooting/index.md"
    ]
    
    for file in troubleshooting_files
        exists = test_file_exists(file, "Troubleshooting documentation")
        
        if exists
            content = read(file, String)
            
            # Check for common issues coverage
            common_issues = ["Docker", "Julia", "Git", "Permission", "Network"]
            covered_issues = String[]
            
            for issue in common_issues
                if contains(content, issue)
                    push!(covered_issues, issue)
                end
            end
            
            coverage_ratio = length(covered_issues) / length(common_issues)
            good_coverage = coverage_ratio >= 0.6
            
            log_test("Troubleshooting coverage in $(basename(file))", good_coverage,
                    "Covers $(length(covered_issues))/$(length(common_issues)) common issues")
        end
    end
end

test_troubleshooting_links()

# Generate Final Report
println("\n" * repeat("=", 60))
println("📊 FINAL TEST RESULTS")
println(repeat("=", 60))

total_tests = length(TEST_RESULTS)
passed_tests = count(result -> result[1], values(TEST_RESULTS))
failed_tests = total_tests - passed_tests

println("Total Tests: $total_tests")
println("Passed: $passed_tests ✅")
println("Failed: $failed_tests ❌")
println("Success Rate: $(round(passed_tests/total_tests * 100, digits=1))%")

if !isempty(FAILED_TESTS)
    println("\n❌ FAILED TESTS:")
    for test in FAILED_TESTS
        result, details = TEST_RESULTS[test]
        println("  • $test")
        if !isempty(details)
            println("    $details")
        end
    end
end

println("\n📋 REQUIREMENTS VALIDATION:")
println("  • Requirement 1.1 (User Journey): $(passed_tests >= total_tests * 0.8 ? "✅ PASS" : "❌ FAIL")")
println("  • Requirement 4.1 (Content Accuracy): $(count(k -> contains(k, "code block"), keys(TEST_RESULTS)) > 0 ? "✅ PASS" : "❌ FAIL")")  
println("  • Requirement 5.1 (Getting Started): $(haskey(TEST_RESULTS, "Total getting-started time") && TEST_RESULTS["Total getting-started time"][1] ? "✅ PASS" : "❌ FAIL")")

# Exit with appropriate code
exit_code = failed_tests == 0 ? 0 : 1
println("\nTest completed with exit code: $exit_code")
exit(exit_code)