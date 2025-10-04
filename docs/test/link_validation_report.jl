#!/usr/bin/env julia

"""
Link Validation and Repair Script

This script identifies broken links in the documentation and provides
specific fixes for the most common issues found in the user journey testing.
"""

using Test

# Track issues found
issues_found = String[]
fixes_applied = String[]

function validate_and_fix_links()
    println("🔍 Analyzing Documentation Links...")
    
    # Common broken link patterns and their fixes
    link_fixes = Dict(
        # Fix malformed links with brackets in URLs
        r"\[([^\]]+)\]\(\.\./guides/\[strategy\]\([^)]+\)" => s"[\1](../guides/strategy-development.md)",
        r"\[([^\]]+)\]\(\.\./\[exchanges\]\([^)]+\)" => s"[\1](../exchanges.md)",
        r"\[([^\]]+)\]\(\.\./\[optimization\]\([^)]+\)" => s"[\1](../optimization.md)",
        r"\[([^\]]+)\]\(\.\./\[troubleshooting\]\([^)]+\)" => s"[\1](../troubleshooting/index.md)",
        
        # Fix double relative paths
        r"getting-started/getting-started/" => "getting-started/",
        r"guides/guides/" => "guides/",
        r"troubleshooting/troubleshooting/" => "troubleshooting/",
        
        # Fix malformed anchor links
        r"\[simulation\]\([^)]+\#simulation-mode\)" => "simulation",
        r"\[backtesting\]\([^)]+\#simulation-mode\)" => "backtesting",
        r"\[live trading\]\([^)]+\#live-mode\)" => "live trading",
        
        # Fix nested bracket issues
        r"\[([^\]]+)\]\([^)]*\[([^\]]+)\]\([^)]*\)" => s"[\1](../guides/strategy-development.md)",
    )
    
    # Files to check and fix
    files_to_fix = [
        "docs/src/index.md",
        "docs/src/getting-started/index.md",
        "docs/src/getting-started/installation.md", 
        "docs/src/getting-started/quick-start.md",
        "docs/src/getting-started/first-strategy.md"
    ]
    
    for filepath in files_to_fix
        if !isfile(filepath)
            push!(issues_found, "Missing file: $filepath")
            continue
        end
        
        println("📄 Checking $filepath...")
        content = read(filepath, String)
        original_content = content
        
        # Apply fixes
        for (pattern, replacement) in link_fixes
            if occursin(pattern, content)
                content = replace(content, pattern => replacement)
                push!(fixes_applied, "Fixed pattern in $filepath: $pattern")
            end
        end
        
        # Write back if changes were made
        if content != original_content
            write(filepath, content)
            println("  ✅ Applied fixes to $filepath")
        else
            println("  ℹ️  No fixes needed for $filepath")
        end
    end
    
    # Check for missing referenced files
    missing_files = [
        "docs/src/exchanges.md",
        "docs/src/optimization.md", 
        "docs/src/resources/community.md",
        "docs/src/resources/search.md",
        "docs/src/guides/monitoring.md",
        "docs/src/advanced/risk-management.md"
    ]
    
    for file in missing_files
        if !isfile(file)
            push!(issues_found, "Referenced but missing: $file")
        end
    end
    
    return length(issues_found), length(fixes_applied)
end

function create_missing_files()
    println("\n📝 Creating Missing Referenced Files...")
    
    # Create missing files with basic content
    missing_files_content = Dict(
        "docs/src/exchanges.md" => """---
title: "Exchange Integration"
category: "reference"
difficulty: "intermediate"
topics: [exchanges, configuration]
last_updated: "2025-10-04"
---

# Exchange Integration

Documentation for exchange integration and configuration.

## See Also
- [Getting Started](getting-started/index.md)
- [Configuration](reference/configuration.md)
""",
        
        "docs/src/optimization.md" => """---
title: "Strategy Optimization"
category: "advanced"
difficulty: "advanced"
topics: [optimization, strategy-development]
last_updated: "2025-10-04"
---

# Strategy Optimization

Guide to optimizing trading strategy parameters.

## See Also
- [Strategy Development](guides/strategy-development.md)
- [Performance Analysis](guides/performance-analysis.md)
""",
        
        "docs/src/resources/community.md" => """---
title: "Community Resources"
category: "resources"
difficulty: "beginner"
topics: [community, support]
last_updated: "2025-10-04"
---

# Community Resources

Connect with the Planar community for support and collaboration.

## See Also
- [Getting Started](../getting-started/index.md)
- [Troubleshooting](../troubleshooting/index.md)
""",
        
        "docs/src/resources/search.md" => """---
title: "Search Documentation"
category: "resources"
difficulty: "beginner"
topics: [search, navigation]
last_updated: "2025-10-04"
---

# Search Documentation

Search functionality for finding information quickly.

## See Also
- [Documentation Index](../documentation-index.md)
""",
        
        "docs/src/guides/monitoring.md" => """---
title: "Strategy Monitoring"
category: "guides"
difficulty: "intermediate"
topics: [monitoring, live-trading]
last_updated: "2025-10-04"
---

# Strategy Monitoring

Monitor your trading strategies in real-time.

## See Also
- [Execution Modes](execution-modes.md)
- [Live Trading](../advanced/live-trading.md)
""",
        
        "docs/src/advanced/risk-management.md" => """---
title: "Risk Management"
category: "advanced"
difficulty: "advanced"
topics: [risk-management, trading]
last_updated: "2025-10-04"
---

# Risk Management

Advanced risk management techniques for trading strategies.

## See Also
- [Strategy Development](../guides/strategy-development.md)
- [Live Trading](live-trading.md)
"""
    )
    
    created_count = 0
    for (filepath, content) in missing_files_content
        if !isfile(filepath)
            # Create directory if needed
            mkpath(dirname(filepath))
            write(filepath, content)
            println("  ✅ Created $filepath")
            created_count += 1
        end
    end
    
    return created_count
end

function validate_code_examples()
    println("\n💻 Validating Code Examples...")
    
    # Check for common code issues in documentation
    code_issues = String[]
    
    files_to_check = [
        "docs/src/getting-started/installation.md",
        "docs/src/getting-started/quick-start.md"
    ]
    
    for filepath in files_to_check
        if !isfile(filepath)
            continue
        end
        
        content = read(filepath, String)
        
        # Check for malformed code in markdown
        if occursin(r"\[strategy\]\([^)]+\)", content)
            push!(code_issues, "$filepath: Contains malformed strategy links in code blocks")
        end
        
        if occursin(r"\[exchange\]\([^)]+\)", content)
            push!(code_issues, "$filepath: Contains malformed exchange links in code blocks")
        end
        
        # Check for proper Julia code formatting
        julia_blocks = collect(eachmatch(r"```julia\n(.*?)\n```"s, content))
        for (i, block) in enumerate(julia_blocks)
            code = block.captures[1]
            if occursin("[", code) && occursin("](", code)
                push!(code_issues, "$filepath: Julia code block $i contains markdown links")
            end
        end
    end
    
    return code_issues
end

# Main execution
println("🚀 Starting Link Validation and Repair")
println(repeat("=", 50))

# Step 1: Fix existing links
issues_count, fixes_count = validate_and_fix_links()

# Step 2: Create missing files
created_count = create_missing_files()

# Step 3: Validate code examples
code_issues = validate_code_examples()

# Report results
println("\n📊 VALIDATION RESULTS")
println(repeat("=", 50))
println("Issues Found: $issues_count")
println("Fixes Applied: $fixes_count") 
println("Files Created: $created_count")
println("Code Issues: $(length(code_issues))")

if !isempty(issues_found)
    println("\n❌ ISSUES FOUND:")
    for issue in issues_found
        println("  • $issue")
    end
end

if !isempty(fixes_applied)
    println("\n✅ FIXES APPLIED:")
    for fix in fixes_applied[1:min(5, length(fixes_applied))]  # Show first 5
        println("  • $fix")
    end
    if length(fixes_applied) > 5
        println("  • ... and $(length(fixes_applied) - 5) more")
    end
end

if !isempty(code_issues)
    println("\n⚠️  CODE ISSUES:")
    for issue in code_issues
        println("  • $issue")
    end
end

println("\n🎉 Link validation completed!")