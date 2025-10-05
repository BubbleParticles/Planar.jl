#!/usr/bin/env julia

"""
Fix Link Patterns Script

This script analyzes and fixes the most common link pattern issues.
"""

using Pkg
Pkg.activate("docs")

# First, let's analyze the most common broken link patterns
function analyze_broken_links()
    println("=== ANALYZING BROKEN LINK PATTERNS ===")
    
    # Read a few key files to understand the link patterns
    files_to_check = [
        "docs/src/config.md",
        "docs/src/data.md", 
        "docs/src/strategy.md",
        "docs/src/optimization.md"
    ]
    
    link_patterns = Dict{String, Int}()
    
    for file_path in files_to_check
        if isfile(file_path)
            content = read(file_path, String)
            lines = split(content, '\n')
            
            for (i, line) in enumerate(lines)
                # Find markdown links
                for m in eachmatch(r"\[([^\]]*)\]\(([^)]+)\)", line)
                    link_text = m.captures[1]
                    link_url = m.captures[2]
                    
                    # Skip external links
                    if !startswith(link_url, "http")
                        pattern = link_url
                        link_patterns[pattern] = get(link_patterns, pattern, 0) + 1
                        
                        # Check if target exists
                        if startswith(link_url, "../")
                            # Try different resolution strategies
                            target1 = normpath(joinpath(dirname(file_path), link_url))
                            target2 = normpath(joinpath("docs/src", link_url[4:end])) # Remove ../
                            target3 = normpath(joinpath("docs", link_url[4:end])) # Remove ../
                            
                            exists1 = isfile(target1) || isdir(target1)
                            exists2 = isfile(target2) || isdir(target2)  
                            exists3 = isfile(target3) || isdir(target3)
                            
                            if !exists1 && !exists2 && !exists3
                                println("BROKEN: $file_path:$i -> $link_url")
                                println("  Tried: $target1 ($(exists1))")
                                println("  Tried: $target2 ($(exists2))")
                                println("  Tried: $target3 ($(exists3))")
                            elseif !exists1 && (exists2 || exists3)
                                correct_target = exists2 ? target2 : target3
                                println("FIXABLE: $file_path:$i -> $link_url should point to $correct_target")
                            end
                        end
                    end
                end
            end
        end
    end
    
    println("\nMost common link patterns:")
    sorted_patterns = sort(collect(link_patterns), by=x->x[2], rev=true)
    for (pattern, count) in sorted_patterns[1:min(20, end)]
        println("  $count times: $pattern")
    end
end

# Run the analysis
analyze_broken_links()

println("\n=== CHECKING FILE EXISTENCE ===")
# Check what files actually exist
key_files = [
    "docs/src/config.md",
    "docs/src/exchanges.md", 
    "docs/src/optimization.md",
    "docs/src/guides/strategy-development.md",
    "docs/src/guides/data-management.md",
    "docs/src/guides/execution-modes.md",
    "docs/troubleshooting/index.md",
    "docs/troubleshooting/exchange-issues.md",
    "docs/troubleshooting/performance-issues.md",
    "docs/troubleshooting/installation-issues.md",
    "docs/getting-started/installation.md"
]

for file in key_files
    exists = isfile(file)
    println("$file: $(exists ? "✅ EXISTS" : "❌ MISSING")")
end