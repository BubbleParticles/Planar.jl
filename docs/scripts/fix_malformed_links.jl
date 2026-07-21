#!/usr/bin/env julia

"""
Fix Malformed Markdown Links

This script fixes the most common malformed markdown link patterns.
"""

function fix_malformed_links_in_file(file_path::String)
    if !isfile(file_path)
        println("File not found: $file_path")
        return false
    end
    
    content = read(file_path, String)
    original_content = content
    changes_made = false
    
    # Pattern 1: Fix ../[text](../file.md -> [text](../file.md)
    pattern1 = r"\.\.\/\[([^\]]+)\]\(\.\.\/([^)]+)\)"
    if occursin(pattern1, content)
        content = replace(content, pattern1 => s"[\1](../\2)")
        changes_made = true
        println("Fixed pattern '../[text](../file.md' in $file_path")
    end
    
    # Pattern 2: Fix [text](../file.md#[section](../file.md#section -> [text](../file.md#section)
    pattern2 = r"\[([^\]]+)\]\(([^)]+)#\[([^\]]+)\]\([^)]+\)"
    if occursin(pattern2, content)
        content = replace(content, pattern2 => s"[\1](\2#\3)")
        changes_made = true
        println("Fixed pattern '[text](file.md#[section](file.md#section' in $file_path")
    end
    
    # Pattern 3: Fix ../config.md#[configuration](../config.md -> [configuration](../config.md)
    pattern3 = r"\.\.\/([^#]+)#\[([^\]]+)\]\(\.\.\/\1"
    if occursin(pattern3, content)
        content = replace(content, pattern3 => s"[\2](../\1)")
        changes_made = true
        println("Fixed pattern '../file.md#[text](../file.md' in $file_path")
    end
    
    # Pattern 4: Fix malformed links like "ats))" 
    pattern4 = r"\bats\)\)"
    if occursin(pattern4, content)
        content = replace(content, pattern4 => "assets")
        changes_made = true
        println("Fixed 'ats))' pattern in $file_path")
    end
    
    # Pattern 5: Fix links that have text that looks like a file path
    pattern5 = r"Default path might be a scratchspace \(from Scratch\.jl\) in the future"
    if occursin(pattern5, content)
        # This appears to be a comment that got treated as a link, let's wrap it properly
        content = replace(content, pattern5 => "`Default path might be a scratchspace (from Scratch.jl) in the future`")
        changes_made = true
        println("Fixed scratchspace comment in $file_path")
    end
    
    # Pattern 6: Fix "It is possible that in the future..." comment
    pattern6 = r"It is possible that in the future the bot will work with the hummingbot gateway for DEX support, and at least another exchange type natively implemented \(from psydyllic\)\."
    if occursin(pattern6, content)
        content = replace(content, pattern6 => "> **Note**: It is possible that in the future the bot will work with the hummingbot gateway for DEX support, and at least another exchange type natively implemented (from psydyllic).")
        changes_made = true
        println("Fixed hummingbot comment in $file_path")
    end
    
    # Pattern 7: Fix :ProcessorCount - 2 
    pattern7 = r":ProcessorCount - 2"
    if occursin(pattern7, content)
        content = replace(content, pattern7 => "`ProcessorCount - 2`")
        changes_made = true
        println("Fixed ProcessorCount pattern in $file_path")
    end
    
    # Pattern 8: Fix USDT appearing as a link
    pattern8 = r"\bUSDT\b"
    # Only replace if it appears to be treated as a link (this is tricky, let's be conservative)
    
    if changes_made
        write(file_path, content)
        println("✅ Updated $file_path")
        return true
    else
        println("No changes needed in $file_path")
        return false
    end
end

# Files to fix based on our analysis
files_to_fix = [
    "docs/src/config.md",
    "docs/src/data.md",
    "docs/src/strategy.md", 
    "docs/src/optimization.md",
    "docs/src/exchanges.md",
    "docs/src/devdocs.md",
    "docs/src/disambiguation.md",
    "docs/src/documentation-index.md",
    "docs/src/plotting.md",
    "docs/src/troubleshooting.md",
    "docs/src/types.md",
    "docs/src/engine/paper.md",
    "docs/src/getting-started/installation.md",
    "docs/src/guides/strategy-development.md"
]

println("=== FIXING MALFORMED MARKDOWN LINKS ===")

global total_fixed = 0
for file_path in files_to_fix
    if fix_malformed_links_in_file(file_path)
        global total_fixed += 1
    end
end

println("\n=== SUMMARY ===")
println("Fixed malformed links in $total_fixed files")
println("Run the link validator again to see the improvement!")