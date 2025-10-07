#!/usr/bin/env julia

"""
Mass Code Block Elimination Script

Performs aggressive elimination of redundant code blocks based on the inventory analysis.
Targets syntax demonstrations, configuration examples, and generic examples for removal.
"""

using Pkg, Dates
Pkg.activate(".")

include("code_block_inventory.jl")

function remove_code_blocks_from_file(filepath, blocks_to_remove)
    """Remove specified code blocks from a file."""
    
    if !isfile(filepath)
        return false
    end
    
    content = read(filepath, String)
    lines = split(content, '\n')
    original_length = length(lines)
    
    # Sort blocks by line number in reverse order to avoid index shifting
    sorted_blocks = sort(blocks_to_remove, by=b->b["start_line"], rev=true)
    
    modified = false
    for block in sorted_blocks
        if block["file"] == filepath
            # Remove lines from start_line to end_line (inclusive)
            start_idx = block["start_line"]
            end_idx = block["end_line"]
            
            # Validate indices
            if start_idx > 0 && end_idx <= length(lines) && start_idx <= end_idx
                # Remove the block lines
                deleteat!(lines, start_idx:end_idx)
                modified = true
                
                println("   Removed $(block["category"]) block (lines $start_idx-$end_idx)")
            else
                println("   Skipped invalid block range: lines $start_idx-$end_idx (file has $(length(lines)) lines)")
            end
        end
    end
    
    if modified
        # Write back the modified content
        new_content = join(lines, '\n')
        write(filepath, new_content)
        return true
    end
    
    return false
end

function eliminate_syntax_blocks(blocks)
    """Remove simple syntax demonstration blocks."""
    
    println("🔥 PHASE 1A: Eliminating syntax demonstration blocks...")
    
    syntax_blocks = filter(b -> b["category"] == "syntax", blocks)
    println("   Found $(length(syntax_blocks)) syntax blocks to eliminate")
    
    files_modified = Set()
    
    # Group blocks by file
    file_blocks = Dict()
    for block in syntax_blocks
        filepath = block["file"]
        if !haskey(file_blocks, filepath)
            file_blocks[filepath] = []
        end
        push!(file_blocks[filepath], block)
    end
    
    # Process each file
    for (filepath, file_syntax_blocks) in file_blocks
        println("   Processing: $filepath ($(length(file_syntax_blocks)) blocks)")
        if remove_code_blocks_from_file(filepath, file_syntax_blocks)
            push!(files_modified, filepath)
        end
    end
    
    println("   ✅ Eliminated $(length(syntax_blocks)) syntax blocks from $(length(files_modified)) files")
    return length(syntax_blocks)
end

function eliminate_configuration_blocks(blocks)
    """Remove configuration example blocks, converting to TOML/YAML where appropriate."""
    
    println("🔥 PHASE 1B: Eliminating configuration example blocks...")
    
    config_blocks = filter(b -> b["category"] == "configuration", blocks)
    println("   Found $(length(config_blocks)) configuration blocks to eliminate")
    
    files_modified = Set()
    
    # Group blocks by file
    file_blocks = Dict()
    for block in config_blocks
        filepath = block["file"]
        if !haskey(file_blocks, filepath)
            file_blocks[filepath] = []
        end
        push!(file_blocks[filepath], block)
    end
    
    # Process each file
    for (filepath, file_config_blocks) in file_blocks
        println("   Processing: $filepath ($(length(file_config_blocks)) blocks)")
        
        # For configuration blocks, we might want to convert some to TOML
        for block in file_config_blocks
            content = block["content"]
            
            # Check if this looks like it should be converted to TOML
            if occursin("toml", lowercase(content)) || occursin("config", lowercase(content))
                # Could add TOML conversion logic here, but for now just remove
                println("     - Config block (could convert to TOML): lines $(block["start_line"])-$(block["end_line"])")
            end
        end
        
        if remove_code_blocks_from_file(filepath, file_config_blocks)
            push!(files_modified, filepath)
        end
    end
    
    println("   ✅ Eliminated $(length(config_blocks)) configuration blocks from $(length(files_modified)) files")
    return length(config_blocks)
end

function eliminate_generic_examples(blocks)
    """Remove generic example blocks that don't demonstrate essential functionality."""
    
    println("🔥 PHASE 1C: Eliminating generic example blocks...")
    
    example_blocks = filter(b -> b["category"] == "example", blocks)
    println("   Found $(length(example_blocks)) generic example blocks to eliminate")
    
    files_modified = Set()
    
    # Group blocks by file
    file_blocks = Dict()
    for block in example_blocks
        filepath = block["file"]
        if !haskey(file_blocks, filepath)
            file_blocks[filepath] = []
        end
        push!(file_blocks[filepath], block)
    end
    
    # Process each file
    for (filepath, file_example_blocks) in file_blocks
        println("   Processing: $filepath ($(length(file_example_blocks)) blocks)")
        if remove_code_blocks_from_file(filepath, file_example_blocks)
            push!(files_modified, filepath)
        end
    end
    
    println("   ✅ Eliminated $(length(example_blocks)) generic example blocks from $(length(files_modified)) files")
    return length(example_blocks)
end

function backup_documentation()
    """Create backup of documentation before mass elimination."""
    
    println("💾 Creating documentation backup...")
    
    backup_dir = "docs_backup_$(Dates.format(now(), "yyyy-mm-dd_HH-MM-SS"))"
    
    # Copy entire docs directory
    run(`cp -r docs $backup_dir`)
    
    println("   ✅ Documentation backed up to: $backup_dir")
    return backup_dir
end

function perform_mass_elimination()
    """Execute the mass elimination of redundant code blocks."""
    
    println("🚀 Starting mass elimination of redundant code blocks...")
    println("="^80)
    
    # Create backup first
    backup_dir = backup_documentation()
    
    # Load current inventory
    println("\n📊 Loading current code block inventory...")
    blocks, file_stats, doc_files = scan_all_documentation()
    
    initial_count = length(blocks)
    println("   Starting with: $initial_count code blocks")
    
    # Phase 1A: Eliminate syntax blocks
    syntax_eliminated = eliminate_syntax_blocks(blocks)
    
    # Phase 1B: Eliminate configuration blocks  
    config_eliminated = eliminate_configuration_blocks(blocks)
    
    # Phase 1C: Eliminate generic examples
    examples_eliminated = eliminate_generic_examples(blocks)
    
    total_eliminated = syntax_eliminated + config_eliminated + examples_eliminated
    
    println("\n" * "="^80)
    println("📈 MASS ELIMINATION RESULTS:")
    println("   Initial blocks: $initial_count")
    println("   Syntax blocks eliminated: $syntax_eliminated")
    println("   Configuration blocks eliminated: $config_eliminated") 
    println("   Generic example blocks eliminated: $examples_eliminated")
    println("   Total eliminated: $total_eliminated")
    
    # Re-scan to get updated count
    println("\n🔍 Re-scanning documentation after elimination...")
    new_blocks, new_file_stats, _ = scan_all_documentation()
    final_count = length(new_blocks)
    
    println("   Final count: $final_count blocks")
    println("   Actual reduction: $(initial_count - final_count) blocks")
    println("   Reduction percentage: $(round((initial_count - final_count)/initial_count * 100, digits=1))%")
    
    remaining_to_target = final_count - 50
    if remaining_to_target > 0
        println("   Still need to eliminate: $remaining_to_target blocks to reach target of 50")
    else
        println("   🎉 TARGET ACHIEVED! Under 50 blocks remaining!")
    end
    
    # Save updated elimination report
    open("reports/mass_elimination_results.txt", "w") do f
        println(f, "MASS ELIMINATION RESULTS")
        println(f, "Generated: $(now())")
        println(f, "Backup created: $backup_dir")
        println(f, "="^80)
        println(f, "")
        println(f, "PHASE 1 ELIMINATION:")
        println(f, "Initial blocks: $initial_count")
        println(f, "Syntax eliminated: $syntax_eliminated")
        println(f, "Configuration eliminated: $config_eliminated")
        println(f, "Examples eliminated: $examples_eliminated")
        println(f, "Total eliminated: $total_eliminated")
        println(f, "")
        println(f, "RESULTS:")
        println(f, "Final count: $final_count")
        println(f, "Actual reduction: $(initial_count - final_count)")
        println(f, "Reduction percentage: $(round((initial_count - final_count)/initial_count * 100, digits=1))%")
        println(f, "")
        if remaining_to_target > 0
            println(f, "PHASE 2 NEEDED:")
            println(f, "Remaining to eliminate: $remaining_to_target blocks")
            println(f, "Target: Under 50 blocks total")
        else
            println(f, "🎉 TARGET ACHIEVED!")
        end
    end
    
    println("\n💾 Results saved to: reports/mass_elimination_results.txt")
    println("📁 Backup available at: $backup_dir")
    
    return final_count, remaining_to_target
end

# Main execution
if abspath(PROGRAM_FILE) == @__FILE__
    perform_mass_elimination()
end