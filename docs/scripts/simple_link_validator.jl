#!/usr/bin/env julia

"""
Simple Link Validation System for Planar Documentation

This script validates internal links in the documentation and generates a basic report.
"""

using Dates

# Configuration
const DOCS_ROOT = joinpath(@__DIR__, "..", "src")
const REPORT_DIR = joinpath(@__DIR__, "..", "reports")

# Simple link validation results
struct SimpleLinkResult
    url::String
    status::String  # "valid", "broken"
    file_path::String
    error_message::Union{String, Nothing}
end

# Utility functions
function ensure_report_dir()
    if !isdir(REPORT_DIR)
        mkpath(REPORT_DIR)
    end
end

function extract_markdown_links(content::String)::Vector{String}
    links = String[]
    
    # Markdown links: [text](url)
    link_pattern = r"\[([^\]]*)\]\(([^)]+)\)"
    for match in eachmatch(link_pattern, content)
        url = match.captures[2]
        # Only process internal links (not starting with http/https or #)
        if !startswith(url, "http://") && !startswith(url, "https://") && !startswith(url, "#")
            push!(links, url)
        end
    end
    
    return unique(links)
end

function validate_internal_link(link::String, base_file::String)::SimpleLinkResult
    # Convert relative path to absolute
    if startswith(link, "/")
        # Absolute path from docs root
        full_path = joinpath(DOCS_ROOT, link[2:end])
    else
        # Relative path from current file
        base_dir = dirname(base_file)
        full_path = normpath(joinpath(base_dir, link))
    end
    
    # Add .md extension if not present and not a directory
    if !endswith(full_path, ".md") && !isdir(full_path)
        full_path = full_path * ".md"
    end
    
    if isfile(full_path) || isdir(full_path)
        return SimpleLinkResult(link, "valid", base_file, nothing)
    else
        return SimpleLinkResult(link, "broken", base_file, "File not found: $full_path")
    end
end

function validate_file_links(file_path::String)::Vector{SimpleLinkResult}
    println("Validating links in: $(replace(file_path, DOCS_ROOT => "docs/src"))")
    
    content = read(file_path, String)
    links = extract_markdown_links(content)
    
    results = SimpleLinkResult[]
    
    for link in links
        result = validate_internal_link(link, file_path)
        push!(results, result)
    end
    
    return results
end

function find_markdown_files(root_dir::String)::Vector{String}
    files = String[]
    for (root, dirs, filenames) in walkdir(root_dir)
        for filename in filenames
            if endswith(filename, ".md")
                push!(files, joinpath(root, filename))
            end
        end
    end
    return files
end

function generate_simple_report()
    ensure_report_dir()
    
    markdown_files = find_markdown_files(DOCS_ROOT)
    all_results = SimpleLinkResult[]
    
    println("🔍 Starting link validation for Planar documentation...")
    println("Found $(length(markdown_files)) markdown files to check")
    
    for file_path in markdown_files
        results = validate_file_links(file_path)
        append!(all_results, results)
    end
    
    # Generate summary
    total_links = length(all_results)
    broken_links = count(r -> r.status == "broken", all_results)
    valid_links = total_links - broken_links
    
    println("\n📊 Validation Summary:")
    println("  Total files: $(length(markdown_files))")
    println("  Total internal links: $total_links")
    println("  Valid links: $valid_links")
    println("  Broken links: $broken_links")
    
    if broken_links > 0
        health_score = round((valid_links / total_links) * 100, digits=2)
        println("  Health score: $health_score%")
        
        println("\n🚨 Broken Links Found:")
        for result in all_results
            if result.status == "broken"
                relative_file = replace(result.file_path, DOCS_ROOT => "docs/src")
                println("  ❌ $relative_file -> $(result.url)")
                if result.error_message !== nothing
                    println("     Error: $(result.error_message)")
                end
            end
        end
        
        # Generate simple text report
        report_file = joinpath(REPORT_DIR, "link_validation_report.txt")
        open(report_file, "w") do io
            println(io, "Planar Documentation Link Validation Report")
            println(io, "Generated: $(now())")
            println(io, "=" ^ 50)
            println(io, "")
            println(io, "Summary:")
            println(io, "  Total files: $(length(markdown_files))")
            println(io, "  Total internal links: $total_links")
            println(io, "  Valid links: $valid_links")
            println(io, "  Broken links: $broken_links")
            println(io, "  Health score: $health_score%")
            println(io, "")
            
            if broken_links > 0
                println(io, "Broken Links:")
                for result in all_results
                    if result.status == "broken"
                        relative_file = replace(result.file_path, DOCS_ROOT => "docs/src")
                        println(io, "  ❌ $relative_file -> $(result.url)")
                        if result.error_message !== nothing
                            println(io, "     Error: $(result.error_message)")
                        end
                    end
                end
            end
        end
        
        println("\n📄 Report saved to: $report_file")
        return false
    else
        println("\n✅ All internal links are healthy!")
        return true
    end
end

# Main execution
function main()
    success = generate_simple_report()
    exit(success ? 0 : 1)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end