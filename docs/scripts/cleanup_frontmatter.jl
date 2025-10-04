#!/usr/bin/env julia

"""
Frontmatter Cleanup Script

This script cleans up duplicate frontmatter entries and consolidates metadata.
"""

using Dates

const DOCS_SRC_DIR = joinpath(@__DIR__, "..", "src")

function cleanup_all_files()
    println("🧹 Cleaning up frontmatter...")
    
    md_files = find_markdown_files(DOCS_SRC_DIR)
    files_fixed = 0
    
    for file_path in md_files
        if cleanup_file(file_path)
            files_fixed += 1
        end
    end
    
    println("✅ Cleaned up $files_fixed files")
end

function find_markdown_files(dir::String)
    files = String[]
    for (root, dirs, filenames) in walkdir(dir)
        for filename in filenames
            if endswith(filename, ".md")
                push!(files, joinpath(root, filename))
            end
        end
    end
    return files
end

function cleanup_file(file_path::String)
    content = read(file_path, String)
    lines = split(content, '\n')
    
    # Find all frontmatter sections
    frontmatter_starts = findall(i -> lines[i] == "---", 1:length(lines))
    
    if length(frontmatter_starts) >= 3  # Multiple frontmatter sections
        # Extract all frontmatter content
        all_frontmatter = Dict{String, String}()
        body_start = 1
        
        # Process all frontmatter sections
        for i in 1:2:length(frontmatter_starts)-1
            start_idx = frontmatter_starts[i]
            end_idx = frontmatter_starts[i + 1]
            
            # Parse this frontmatter section
            fm_lines = lines[start_idx + 1:end_idx - 1]
            for line in fm_lines
                if contains(line, ":") && !isempty(strip(line))
                    parts = split(line, ":", limit=2)
                    if length(parts) == 2
                        key = strip(parts[1])
                        value = strip(parts[2])
                        if !isempty(key) && !isempty(value)
                            all_frontmatter[key] = value
                        end
                    end
                end
            end
        end
        
        # Body starts after the last frontmatter section
        body_start = frontmatter_starts[end] + 1
        
        # Reconstruct with single frontmatter
        new_lines = ["---"]
        
        # Add consolidated frontmatter in logical order
        key_order = ["title", "description", "category", "difficulty", "estimated_time", 
                    "prerequisites", "user_personas", "next_steps", "related_topics", 
                    "topics", "last_updated"]
        
        for key in key_order
            if haskey(all_frontmatter, key)
                push!(new_lines, "$key: $(all_frontmatter[key])")
                delete!(all_frontmatter, key)
            end
        end
        
        # Add any remaining keys
        for (key, value) in all_frontmatter
            push!(new_lines, "$key: $value")
        end
        
        push!(new_lines, "---")
        
        # Add body
        if body_start <= length(lines)
            append!(new_lines, lines[body_start:end])
        end
        
        # Write cleaned content
        new_content = join(new_lines, '\n')
        write(file_path, new_content)
        
        println("  ✅ Fixed: $file_path")
        return true
    end
    
    return false
end

if abspath(PROGRAM_FILE) == @__FILE__
    cleanup_all_files()
end