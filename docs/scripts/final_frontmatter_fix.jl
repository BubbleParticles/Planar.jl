#!/usr/bin/env julia

"""
Final Frontmatter Fix

This script properly consolidates all frontmatter into a single, well-formatted section.
"""

const DOCS_SRC_DIR = joinpath(@__DIR__, "..", "src")

function fix_all_files()
    println("🔧 Final frontmatter fix...")
    
    md_files = find_markdown_files(DOCS_SRC_DIR)
    files_fixed = 0
    
    for file_path in md_files
        if fix_file(file_path)
            files_fixed += 1
        end
    end
    
    println("✅ Fixed $files_fixed files")
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

function fix_file(file_path::String)
    content = read(file_path, String)
    lines = split(content, '\n')
    
    # Check if file starts with frontmatter
    if length(lines) < 2 || lines[1] != "---"
        return false
    end
    
    # Find the end of first frontmatter section
    first_end = findfirst(i -> i > 1 && lines[i] == "---", 2:length(lines))
    if first_end === nothing
        return false
    end
    first_end += 1  # Adjust for 1-based indexing
    
    # Extract all metadata from the entire file
    all_metadata = Dict{String, String}()
    
    # Parse first frontmatter section
    for line in lines[2:first_end-1]
        if contains(line, ":") && !isempty(strip(line))
            parts = split(line, ":", limit=2)
            if length(parts) == 2
                key = strip(parts[1])
                value = strip(parts[2])
                if !isempty(key) && !isempty(value)
                    all_metadata[key] = value
                end
            end
        end
    end
    
    # Look for additional metadata in the rest of the file
    body_lines = String[]
    in_body = false
    
    for i in (first_end + 1):length(lines)
        line = lines[i]
        
        # Check if this looks like metadata
        if contains(line, ":") && !in_body && !startswith(line, "#") && !startswith(line, "-") && !startswith(line, "*")
            parts = split(line, ":", limit=2)
            if length(parts) == 2
                key = strip(parts[1])
                value = strip(parts[2])
                if !isempty(key) && !isempty(value) && !contains(key, " ")
                    all_metadata[key] = value
                    continue
                end
            end
        end
        
        # This is body content
        if !isempty(strip(line)) || in_body
            in_body = true
            push!(body_lines, line)
        end
    end
    
    # Reconstruct file with clean frontmatter
    new_lines = ["---"]
    
    # Add metadata in logical order
    key_order = ["title", "description", "category", "difficulty", "estimated_time", 
                "prerequisites", "user_personas", "next_steps", "related_topics", 
                "topics", "last_updated"]
    
    for key in key_order
        if haskey(all_metadata, key)
            push!(new_lines, "$key: $(all_metadata[key])")
            delete!(all_metadata, key)
        end
    end
    
    # Add any remaining keys
    for (key, value) in sort(collect(all_metadata))
        push!(new_lines, "$key: $value")
    end
    
    push!(new_lines, "---")
    push!(new_lines, "")  # Empty line after frontmatter
    
    # Add body content
    append!(new_lines, body_lines)
    
    # Write the fixed content
    new_content = join(new_lines, '\n')
    write(file_path, new_content)
    
    println("  ✅ Fixed: $file_path")
    return true
end

if abspath(PROGRAM_FILE) == @__FILE__
    fix_all_files()
end