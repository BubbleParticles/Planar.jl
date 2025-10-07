#!/usr/bin/env julia

"""
Simple Mass Code Block Elimination Script

A more robust approach that processes files one at a time to avoid indexing issues.
"""

using Pkg, Dates
Pkg.activate(".")

include("code_block_inventory.jl")

function remove_blocks_by_category(category_name, target_count=nothing)
    """Remove all blocks of a specific category."""
    
    println("🔥 Eliminating $category_name blocks...")
    
    eliminated_count = 0
    files_processed = Set()
    
    while true
        # Re-scan to get current state
        blocks, _, _ = scan_all_documentation()
        
        # Find blocks of target category
        target_blocks = filter(b -> b["category"] == category_name, blocks)
        
        if isempty(target_blocks)
            break
        end
        
        if target_count !== nothing && eliminated_count >= target_count
            break
        end
        
        # Process one file at a time
        current_file = target_blocks[1]["file"]
        file_blocks = filter(b -> b["file"] == current_file, target_blocks)
        
        println("   Processing: $current_file ($(length(file_blocks)) blocks)")
        
        # Remove blocks from this file
        if remove_blocks_from_single_file(current_file, file_blocks)
            eliminated_count += length(file_blocks)
            push!(files_processed, current_file)
        end
        
        # Safety check to avoid infinite loops
        if eliminated_count > 1000
            println("   Safety limit reached, stopping")
            break
        end
    end
    
    println("   ✅ Eliminated $eliminated_count $category_name blocks from $(length(files_processed)) files")
    return eliminated_count
end

function remove_blocks_from_single_file(filepath, blocks_to_remove)
    """Remove blocks from a single file by reconstructing content."""
    
    if !isfile(filepath)
        return false
    end
    
    content = read(filepath, String)
    lines = split(content, '\n')
    
    # Create a set of line numbers to remove
    lines_to_remove = Set{Int}()
    
    for block in blocks_to_remove
        for line_num in block["start_line"]:block["end_line"]
            push!(lines_to_remove, line_num)
        end
        println("     - Removing $(block["category"]) block (lines $(block["start_line"])-$(block["end_line"]))")
    end
    
    # Keep only lines not in the removal set
    new_lines = []
    for (i, line) in enumerate(lines)
        if !(i in lines_to_remove)
            push!(new_lines, line)
        end
    end
    
    # Write back the modified content
    new_content = join(new_lines, '\n')
    write(filepath, new_content)
    
    return true
end

function perform_simple_mass_elimination()
    """Execute mass elimination with simple, robust approach."""
    
    println("🚀 Starting simple mass elimination...")
    println("="^80)
    
    # Create backup
    backup_dir = "docs_backup_$(Dates.format(now(), "yyyy-mm-dd_HH-MM-SS"))"
    run(`cp -r docs $backup_dir`)
    println("💾 Documentation backed up to: $backup_dir")
    
    # Get initial count
    initial_blocks, _, _ = scan_all_documentation()
    initial_count = length(initial_blocks)
    println("📊 Starting with: $initial_count code blocks")
    
    # Phase 1: Eliminate target categories
    syntax_eliminated = remove_blocks_by_category("syntax")
    config_eliminated = remove_blocks_by_category("configuration") 
    examples_eliminated = remove_blocks_by_category("example")
    
    total_eliminated = syntax_eliminated + config_eliminated + examples_eliminated
    
    # Get final count
    final_blocks, _, _ = scan_all_documentation()
    final_count = length(final_blocks)
    
    println("\n" * "="^80)
    println("📈 MASS ELIMINATION RESULTS:")
    println("   Initial blocks: $initial_count")
    println("   Syntax eliminated: $syntax_eliminated")
    println("   Configuration eliminated: $config_eliminated")
    println("   Examples eliminated: $examples_eliminated")
    println("   Total eliminated: $total_eliminated")
    println("   Final count: $final_count")
    println("   Actual reduction: $(initial_count - final_count) blocks")
    println("   Reduction percentage: $(round((initial_count - final_count)/initial_count * 100, digits=1))%")
    
    remaining_to_target = final_count - 50
    if remaining_to_target > 0
        println("   Still need to eliminate: $remaining_to_target blocks to reach target of 50")
    else
        println("   🎉 TARGET ACHIEVED! Under 50 blocks remaining!")
    end
    
    # Save results
    open("reports/simple_elimination_results.txt", "w") do f
        println(f, "SIMPLE MASS ELIMINATION RESULTS")
        println(f, "Generated: $(now())")
        println(f, "Backup: $backup_dir")
        println(f, "="^50)
        println(f, "Initial: $initial_count blocks")
        println(f, "Syntax eliminated: $syntax_eliminated")
        println(f, "Config eliminated: $config_eliminated")
        println(f, "Examples eliminated: $examples_eliminated")
        println(f, "Final: $final_count blocks")
        println(f, "Reduction: $(round((initial_count - final_count)/initial_count * 100, digits=1))%")
        if remaining_to_target > 0
            println(f, "Phase 2 needed: $remaining_to_target blocks")
        end
    end
    
    println("💾 Results saved to: reports/simple_elimination_results.txt")
    
    return final_count, remaining_to_target
end

# Run if called directly
if abspath(PROGRAM_FILE) == @__FILE__
    perform_simple_mass_elimination()
end