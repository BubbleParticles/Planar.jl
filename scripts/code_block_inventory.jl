#!/usr/bin/env julia

"""
Comprehensive Code Block Inventory Script

Scans all documentation files to create a detailed inventory of Julia code blocks,
categorizing them by type and generating metrics for the aggressive elimination process.
"""

using Pkg, Dates
Pkg.activate(".")

function scan_file_for_code_blocks(filepath)
    """Scan a single file for Julia code blocks and categorize them."""
    
    if !isfile(filepath)
        return []
    end
    
    content = read(filepath, String)
    lines = split(content, '\n')
    
    blocks = []
    in_julia_block = false
    current_block = []
    block_start_line = 0
    
    for (i, line) in enumerate(lines)
        if occursin(r"```julia", line)
            in_julia_block = true
            block_start_line = i
            current_block = []
        elseif occursin(r"```", line) && in_julia_block
            in_julia_block = false
            
            # Categorize the block
            block_content = join(current_block, "\n")
            category = categorize_code_block(block_content)
            
            push!(blocks, Dict(
                "file" => filepath,
                "start_line" => block_start_line,
                "end_line" => i,
                "content" => block_content,
                "category" => category,
                "line_count" => length(current_block)
            ))
        elseif in_julia_block
            push!(current_block, line)
        end
    end
    
    return blocks
end

function categorize_code_block(content)
    """Categorize code blocks by their content patterns."""
    
    content_lower = lowercase(content)
    
    # Simple syntax demonstrations
    if occursin(r"^#.*simple|^#.*basic|^#.*example", content_lower) ||
       (occursin("using", content_lower) && length(split(content, '\n')) <= 3)
        return "syntax"
    end
    
    # Configuration examples
    if occursin("toml", content_lower) || occursin("config", content_lower) ||
       occursin("settings", content_lower) || occursin("parameters", content_lower)
        return "configuration"
    end
    
    # Getting started / tutorial
    if occursin("getting started", content_lower) || occursin("tutorial", content_lower) ||
       occursin("@environment!", content_lower) || occursin("first", content_lower)
        return "getting_started"
    end
    
    # API reference examples
    if occursin("function", content_lower) && (occursin("return", content_lower) || 
       occursin("param", content_lower))
        return "api_reference"
    end
    
    # Error handling
    if occursin("try", content_lower) || occursin("catch", content_lower) ||
       occursin("error", content_lower) || occursin("exception", content_lower)
        return "error_handling"
    end
    
    # Strategy examples
    if occursin("strategy", content_lower) || occursin("trading", content_lower) ||
       occursin("backtest", content_lower)
        return "strategy"
    end
    
    # Integration examples
    if occursin("exchange", content_lower) || occursin("ccxt", content_lower) ||
       occursin("integration", content_lower)
        return "integration"
    end
    
    # Troubleshooting
    if occursin("troubleshoot", content_lower) || occursin("debug", content_lower) ||
       occursin("fix", content_lower) || occursin("problem", content_lower)
        return "troubleshooting"
    end
    
    # Default to example if unclear
    return "example"
end

function scan_all_documentation()
    """Scan all documentation files and return comprehensive inventory."""
    
    println("🔍 Scanning documentation for Julia code blocks...")
    
    # Find all markdown files in docs directory
    doc_files = []
    for (root, dirs, files) in walkdir("docs")
        for file in files
            if endswith(file, ".md")
                push!(doc_files, joinpath(root, file))
            end
        end
    end
    
    println("📁 Found $(length(doc_files)) documentation files")
    
    all_blocks = []
    file_stats = Dict()
    
    for filepath in doc_files
        blocks = scan_file_for_code_blocks(filepath)
        append!(all_blocks, blocks)
        
        if length(blocks) > 0
            file_stats[filepath] = length(blocks)
        end
    end
    
    return all_blocks, file_stats, doc_files
end

function generate_inventory_report(blocks, file_stats, doc_files)
    """Generate comprehensive inventory report."""
    
    println("\n" * "="^80)
    println("📊 COMPREHENSIVE CODE BLOCK INVENTORY REPORT")
    println("="^80)
    
    # Overall statistics
    total_blocks = length(blocks)
    total_files = length(doc_files)
    files_with_blocks = length(file_stats)
    
    println("\n📈 OVERALL STATISTICS:")
    println("   Total documentation files: $total_files")
    println("   Files with code blocks: $files_with_blocks")
    println("   Total Julia code blocks: $total_blocks")
    println("   Average blocks per file with blocks: $(round(total_blocks/max(files_with_blocks,1), digits=1))")
    
    # Category breakdown
    category_counts = Dict()
    for block in blocks
        cat = block["category"]
        category_counts[cat] = get(category_counts, cat, 0) + 1
    end
    
    println("\n📋 CATEGORY BREAKDOWN:")
    for (category, count) in sort(collect(category_counts), by=x->x[2], rev=true)
        percentage = round(count/total_blocks * 100, digits=1)
        println("   $category: $count blocks ($percentage%)")
    end
    
    # Files with most blocks
    println("\n🔥 FILES WITH MOST CODE BLOCKS:")
    sorted_files = sort(collect(file_stats), by=x->x[2], rev=true)
    for (i, (filepath, count)) in enumerate(sorted_files[1:min(15, length(sorted_files))])
        println("   $i. $filepath: $count blocks")
    end
    
    # Elimination targets
    println("\n🎯 ELIMINATION ANALYSIS:")
    
    # Count elimination candidates
    syntax_blocks = get(category_counts, "syntax", 0)
    config_blocks = get(category_counts, "configuration", 0)
    example_blocks = get(category_counts, "example", 0)
    
    immediate_elimination = syntax_blocks + config_blocks + example_blocks
    println("   Immediate elimination candidates: $immediate_elimination blocks")
    println("   - Syntax demonstrations: $syntax_blocks")
    println("   - Configuration examples: $config_blocks") 
    println("   - Generic examples: $example_blocks")
    
    remaining_after_phase1 = total_blocks - immediate_elimination
    println("   Remaining after Phase 1: $remaining_after_phase1 blocks")
    
    target_reduction = total_blocks - 50
    println("   Target reduction needed: $target_reduction blocks ($(round(target_reduction/total_blocks*100, digits=1))%)")
    
    if remaining_after_phase1 > 50
        phase2_elimination = remaining_after_phase1 - 50
        println("   Phase 2 elimination needed: $phase2_elimination blocks")
    end
    
    return blocks, category_counts
end

function save_detailed_inventory(blocks, category_counts)
    """Save detailed inventory to files for analysis."""
    
    # Create reports directory if it doesn't exist
    mkpath("reports")
    
    # Save detailed block inventory
    open("reports/code_block_inventory.txt", "w") do f
        println(f, "DETAILED CODE BLOCK INVENTORY")
        println(f, "Generated: $(now())")
        println(f, "="^80)
        
        for (i, block) in enumerate(blocks)
            println(f, "\nBlock #$i:")
            println(f, "  File: $(block["file"])")
            println(f, "  Lines: $(block["start_line"])-$(block["end_line"])")
            println(f, "  Category: $(block["category"])")
            println(f, "  Size: $(block["line_count"]) lines")
            println(f, "  Content preview:")
            
            # Show first few lines of content
            content_lines = split(block["content"], '\n')
            for (j, line) in enumerate(content_lines[1:min(3, length(content_lines))])
                println(f, "    $line")
            end
            if length(content_lines) > 3
                println(f, "    ... ($(length(content_lines)-3) more lines)")
            end
        end
    end
    
    # Save elimination plan
    open("reports/elimination_plan.txt", "w") do f
        println(f, "AGGRESSIVE CODE BLOCK ELIMINATION PLAN")
        println(f, "Generated: $(now())")
        println(f, "="^80)
        
        println(f, "\nCURRENT STATE:")
        println(f, "Total blocks: $(length(blocks))")
        
        println(f, "\nPHASE 1 - MASS ELIMINATION:")
        syntax_count = get(category_counts, "syntax", 0)
        config_count = get(category_counts, "configuration", 0)
        example_count = get(category_counts, "example", 0)
        
        println(f, "- Remove syntax blocks: $syntax_count")
        println(f, "- Remove configuration blocks: $config_count")
        println(f, "- Remove generic examples: $example_count")
        
        phase1_total = syntax_count + config_count + example_count
        println(f, "Phase 1 elimination: $phase1_total blocks")
        
        remaining = length(blocks) - phase1_total
        println(f, "Remaining after Phase 1: $remaining blocks")
        
        println(f, "\nPHASE 2 - RUTHLESS SELECTION:")
        if remaining > 50
            phase2_elimination = remaining - 50
            println(f, "Additional elimination needed: $phase2_elimination blocks")
            println(f, "Apply strict criteria: keep only absolutely essential examples")
        end
        
        println(f, "\nTARGET: Under 50 blocks total")
        println(f, "REDUCTION: $(round((length(blocks)-50)/length(blocks)*100, digits=1))%")
    end
    
    println("\n💾 Detailed reports saved:")
    println("   - reports/code_block_inventory.txt")
    println("   - reports/elimination_plan.txt")
end

# Main execution
function main()
    println("🚀 Starting comprehensive code block inventory...")
    
    # Scan all documentation
    blocks, file_stats, doc_files = scan_all_documentation()
    
    # Generate report
    blocks, category_counts = generate_inventory_report(blocks, file_stats, doc_files)
    
    # Save detailed analysis
    save_detailed_inventory(blocks, category_counts)
    
    println("\n✅ Code block inventory complete!")
    println("📊 Total blocks found: $(length(blocks))")
    println("🎯 Target reduction: $(length(blocks) - 50) blocks ($(round((length(blocks)-50)/length(blocks)*100, digits=1))%)")
    
    return blocks, category_counts
end

# Run if called directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end