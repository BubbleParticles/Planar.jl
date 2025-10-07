#!/usr/bin/env julia

"""
Simple code block scanner for Planar documentation.
Scans all markdown files in docs/src/ and counts Julia code blocks.
"""

using Pkg
Pkg.activate(".")

function find_markdown_files(root_dir)
    """Find all markdown files in the documentation directory."""
    markdown_files = String[]
    
    for (root, dirs, files) in walkdir(root_dir)
        for file in files
            if endswith(file, ".md")
                push!(markdown_files, joinpath(root, file))
            end
        end
    end
    
    return markdown_files
end

function count_julia_code_blocks(file_path)
    """Count Julia code blocks in a markdown file."""
    if !isfile(file_path)
        return 0, String[]
    end
    
    content = read(file_path, String)
    lines = split(content, '\n')
    
    julia_blocks = String[]
    in_julia_block = false
    current_block = String[]
    
    for line in lines
        if startswith(line, "```julia")
            in_julia_block = true
            current_block = [line]
        elseif startswith(line, "```") && in_julia_block
            push!(current_block, line)
            push!(julia_blocks, join(current_block, '\n'))
            in_julia_block = false
            current_block = String[]
        elseif in_julia_block
            push!(current_block, line)
        end
    end
    
    return length(julia_blocks), julia_blocks
end

function categorize_code_block(block_content)
    """Simple categorization based on content patterns."""
    content_lower = lowercase(block_content)
    
    # Tier 1 - Essential patterns
    if contains(content_lower, "using planar") || 
       contains(content_lower, "@environment!") ||
       contains(content_lower, "using planarinteractive")
        return "Essential - Module Loading"
    elseif contains(content_lower, "strategy") && contains(content_lower, "create")
        return "Essential - Strategy Creation"
    elseif contains(content_lower, "exchange") && contains(content_lower, "config")
        return "Essential - Exchange Config"
    elseif contains(content_lower, "try") && contains(content_lower, "catch")
        return "Essential - Error Handling"
    
    # Tier 2 - Potentially redundant patterns
    elseif contains(content_lower, "println") || contains(content_lower, "display")
        return "Redundant - Simple Output"
    elseif length(split(block_content, '\n')) <= 3
        return "Reference - Simple Syntax"
    
    # Default
    else
        return "Review Needed"
    end
end

function main()
    docs_dir = "docs/src"
    
    if !isdir(docs_dir)
        println("Error: Documentation directory '$docs_dir' not found")
        return
    end
    
    println("Scanning Julia code blocks in Planar documentation...")
    println("=" ^ 60)
    
    markdown_files = find_markdown_files(docs_dir)
    total_blocks = 0
    total_files_with_blocks = 0
    
    # Summary data
    file_summary = []
    category_counts = Dict{String, Int}()
    
    for file_path in markdown_files
        block_count, blocks = count_julia_code_blocks(file_path)
        
        if block_count > 0
            total_blocks += block_count
            total_files_with_blocks += 1
            
            # Relative path for cleaner output
            rel_path = replace(file_path, "docs/src/" => "")
            
            println("\n📄 $rel_path")
            println("   Code blocks: $block_count")
            
            push!(file_summary, (rel_path, block_count))
            
            # Categorize blocks
            for (i, block) in enumerate(blocks)
                category = categorize_code_block(block)
                category_counts[category] = get(category_counts, category, 0) + 1
                
                # Show first few lines of each block for review
                block_lines = split(block, '\n')
                preview = join(block_lines[1:min(3, length(block_lines))], " | ")
                println("     [$i] $category: $(preview[1:min(80, length(preview))])...")
            end
        end
    end
    
    # Summary report
    println("\n" * "=" ^ 60)
    println("SUMMARY REPORT")
    println("=" ^ 60)
    println("Total markdown files scanned: $(length(markdown_files))")
    println("Files with Julia code blocks: $total_files_with_blocks")
    println("Total Julia code blocks found: $total_blocks")
    
    println("\n📊 CODE BLOCK CATEGORIES:")
    for (category, count) in sort(collect(category_counts), by=x->x[2], rev=true)
        percentage = round(count / total_blocks * 100, digits=1)
        println("   $category: $count ($percentage%)")
    end
    
    println("\n📁 FILES WITH MOST CODE BLOCKS:")
    sorted_files = sort(file_summary, by=x->x[2], rev=true)
    for (file, count) in sorted_files[1:min(10, length(sorted_files))]
        println("   $file: $count blocks")
    end
    
    println("\n🎯 REDUCTION TARGET:")
    println("   Current: $total_blocks blocks")
    println("   Target: ~50 blocks")
    println("   Reduction needed: $(total_blocks - 50) blocks ($(round((total_blocks - 50) / total_blocks * 100, digits=1))%)")
    
    if total_blocks > 50
        println("\n💡 RECOMMENDATIONS:")
        println("   - Focus on removing 'Redundant - Simple Output' blocks")
        println("   - Convert 'Reference - Simple Syntax' to inline code")
        println("   - Review files with highest block counts first")
        println("   - Consolidate similar examples in the same file")
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end