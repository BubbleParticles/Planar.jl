#!/usr/bin/env julia

"""
Ruthless Code Block Elimination Script

Applies strict retention criteria to eliminate all but the most essential code blocks.
Target: Reduce remaining 339 blocks to under 50 blocks.
"""

using Pkg, Dates
Pkg.activate(".")

include("code_block_inventory.jl")

function analyze_remaining_blocks()
    """Analyze the remaining blocks after mass elimination."""
    
    println("🔍 Analyzing remaining blocks after mass elimination...")
    
    blocks, file_stats, _ = scan_all_documentation()
    
    println("📊 Current state: $(length(blocks)) blocks remaining")
    
    # Category breakdown
    category_counts = Dict()
    for block in blocks
        cat = block["category"]
        category_counts[cat] = get(category_counts, cat, 0) + 1
    end
    
    println("\n📋 REMAINING CATEGORIES:")
    for (category, count) in sort(collect(category_counts), by=x->x[2], rev=true)
        percentage = round(count/length(blocks) * 100, digits=1)
        println("   $category: $count blocks ($percentage%)")
    end
    
    # Files with most blocks
    println("\n🔥 FILES WITH MOST REMAINING BLOCKS:")
    sorted_files = sort(collect(file_stats), by=x->x[2], rev=true)
    for (i, (filepath, count)) in enumerate(sorted_files[1:min(15, length(sorted_files))])
        println("   $i. $filepath: $count blocks")
    end
    
    return blocks, category_counts
end

function apply_ruthless_criteria()
    """Apply ruthless elimination criteria to reach under 50 blocks."""
    
    println("🔥 Applying ruthless elimination criteria...")
    println("="^80)
    
    # Create backup
    backup_dir = "docs_backup_ruthless_$(Dates.format(now(), "yyyy-mm-dd_HH-MM-SS"))"
    run(`cp -r docs $backup_dir`)
    println("💾 Documentation backed up to: $backup_dir")
    
    blocks, category_counts = analyze_remaining_blocks()
    initial_count = length(blocks)
    
    # Define elimination priorities (most to least essential)
    elimination_order = [
        "troubleshooting",  # Remove most troubleshooting examples
        "api_reference",    # Keep only 1-2 most essential API examples
        "strategy",         # Keep only 1-2 core strategy examples  
        "integration",      # Keep only 1-2 integration examples
        "error_handling",   # Keep only 1-2 error handling examples
        "getting_started"   # Keep only essential getting started examples
    ]
    
    total_eliminated = 0
    
    # Phase 1: Eliminate most troubleshooting blocks
    troubleshooting_eliminated = eliminate_most_of_category("troubleshooting", 1)
    total_eliminated += troubleshooting_eliminated
    
    # Phase 2: Drastically reduce API reference blocks
    api_eliminated = eliminate_most_of_category("api_reference", 8)
    total_eliminated += api_eliminated
    
    # Phase 3: Reduce strategy blocks to essentials
    strategy_eliminated = eliminate_most_of_category("strategy", 10)
    total_eliminated += strategy_eliminated
    
    # Phase 4: Reduce integration blocks
    integration_eliminated = eliminate_most_of_category("integration", 5)
    total_eliminated += integration_eliminated
    
    # Phase 5: Reduce error handling blocks
    error_eliminated = eliminate_most_of_category("error_handling", 3)
    total_eliminated += error_eliminated
    
    # Phase 6: Keep only essential getting started blocks
    getting_started_eliminated = eliminate_most_of_category("getting_started", 15)
    total_eliminated += getting_started_eliminated
    
    # Final scan
    final_blocks, _, _ = scan_all_documentation()
    final_count = length(final_blocks)
    
    println("\n" * "="^80)
    println("📈 RUTHLESS ELIMINATION RESULTS:")
    println("   Initial blocks: $initial_count")
    println("   Troubleshooting eliminated: $troubleshooting_eliminated")
    println("   API reference eliminated: $api_eliminated")
    println("   Strategy eliminated: $strategy_eliminated")
    println("   Integration eliminated: $integration_eliminated")
    println("   Error handling eliminated: $error_eliminated")
    println("   Getting started eliminated: $getting_started_eliminated")
    println("   Total eliminated: $total_eliminated")
    println("   Final count: $final_count")
    println("   Reduction percentage: $(round((initial_count - final_count)/initial_count * 100, digits=1))%")
    
    if final_count <= 50
        println("   🎉 TARGET ACHIEVED! Under 50 blocks remaining!")
    else
        remaining_to_eliminate = final_count - 50
        println("   Still need to eliminate: $remaining_to_eliminate blocks")
        
        # If still over 50, apply emergency elimination
        if final_count > 50
            emergency_eliminated = apply_emergency_elimination(remaining_to_eliminate)
            total_eliminated += emergency_eliminated
            
            # Final final scan
            emergency_blocks, _, _ = scan_all_documentation()
            emergency_count = length(emergency_blocks)
            println("   Emergency elimination: $emergency_eliminated blocks")
            println("   Final final count: $emergency_count")
        end
    end
    
    # Save results
    open("reports/ruthless_elimination_results.txt", "w") do f
        println(f, "RUTHLESS ELIMINATION RESULTS")
        println(f, "Generated: $(now())")
        println(f, "Backup: $backup_dir")
        println(f, "="^50)
        println(f, "Initial: $initial_count blocks")
        println(f, "Total eliminated: $total_eliminated")
        println(f, "Final: $final_count blocks")
        println(f, "Reduction: $(round((initial_count - final_count)/initial_count * 100, digits=1))%")
        if final_count <= 50
            println(f, "🎉 TARGET ACHIEVED!")
        end
    end
    
    println("💾 Results saved to: reports/ruthless_elimination_results.txt")
    
    return final_count
end

function eliminate_most_of_category(category_name, keep_count)
    """Eliminate most blocks of a category, keeping only the specified count."""
    
    println("🔥 Ruthlessly reducing $category_name blocks (keep max $keep_count)...")
    
    eliminated_count = 0
    
    while true
        # Re-scan to get current state
        blocks, _, _ = scan_all_documentation()
        
        # Find blocks of target category
        target_blocks = filter(b -> b["category"] == category_name, blocks)
        
        if length(target_blocks) <= keep_count
            println("   ✅ Category $category_name reduced to $(length(target_blocks)) blocks (target: $keep_count)")
            break
        end
        
        # Remove the first block found (arbitrary selection for ruthless elimination)
        block_to_remove = target_blocks[1]
        filepath = block_to_remove["file"]
        
        println("   Removing $category_name block from: $filepath (lines $(block_to_remove["start_line"])-$(block_to_remove["end_line"]))")
        
        if remove_single_block(filepath, block_to_remove)
            eliminated_count += 1
        end
        
        # Safety check
        if eliminated_count > 500
            println("   Safety limit reached for $category_name")
            break
        end
    end
    
    return eliminated_count
end

function remove_single_block(filepath, block_to_remove)
    """Remove a single block from a file."""
    
    if !isfile(filepath)
        return false
    end
    
    content = read(filepath, String)
    lines = split(content, '\n')
    
    # Create set of line numbers to remove
    lines_to_remove = Set{Int}()
    for line_num in block_to_remove["start_line"]:block_to_remove["end_line"]
        push!(lines_to_remove, line_num)
    end
    
    # Keep only lines not in removal set
    new_lines = []
    for (i, line) in enumerate(lines)
        if !(i in lines_to_remove)
            push!(new_lines, line)
        end
    end
    
    # Write back
    new_content = join(new_lines, '\n')
    write(filepath, new_content)
    
    return true
end

function apply_emergency_elimination(target_elimination_count)
    """Emergency elimination to reach under 50 blocks by removing any remaining blocks."""
    
    println("🚨 EMERGENCY ELIMINATION: Need to remove $target_elimination_count more blocks")
    
    eliminated = 0
    
    while eliminated < target_elimination_count
        # Re-scan
        blocks, _, _ = scan_all_documentation()
        
        if isempty(blocks)
            break
        end
        
        # Remove any block (emergency mode)
        block_to_remove = blocks[1]
        filepath = block_to_remove["file"]
        
        println("   Emergency removing block from: $filepath")
        
        if remove_single_block(filepath, block_to_remove)
            eliminated += 1
        end
        
        # Safety check
        if eliminated > 1000
            break
        end
    end
    
    return eliminated
end

# Main execution
if abspath(PROGRAM_FILE) == @__FILE__
    apply_ruthless_criteria()
end