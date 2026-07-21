#!/usr/bin/env julia

"""
Build script for search functionality.

This script:
1. Generates the search index from documentation files
2. Ensures all required assets are in place
3. Validates the search functionality
"""

using Pkg

# Ensure we're in the right directory
cd(dirname(dirname(@__FILE__)))

println("Building Planar documentation search...")

# Generate search index
println("Generating search index...")
include("scripts/generate-search-index.jl")

# Ensure assets directory exists
assets_dir = joinpath("src", "assets")
mkpath(assets_dir)

# Copy search JavaScript if it doesn't exist in assets
search_js_src = joinpath("src", "assets", "search.js")
if !isfile(search_js_src)
    println("Warning: search.js not found in assets directory")
end

# Validate search index
search_index_file = joinpath("src", "assets", "search-index.json")
if isfile(search_index_file)
    println("✓ Search index generated successfully")
    
    # Basic validation
    try
        using JSON3
        index = JSON3.read(read(search_index_file, String))
        doc_count = length(index["documents"])
        category_count = length(index["categories"])
        topic_count = length(index["topics"])
        
        println("✓ Search index validation passed")
        println("  - Documents: $doc_count")
        println("  - Categories: $category_count")
        println("  - Topics: $topic_count")
        
        if doc_count == 0
            println("⚠ Warning: No documents found in search index")
        end
        
    catch e
        println("✗ Search index validation failed: $e")
        exit(1)
    end
else
    println("✗ Search index generation failed")
    exit(1)
end

println("Search build completed successfully!")
println()
println("To use the search functionality:")
println("1. Ensure search.js is loaded on pages that need search")
println("2. Include the search HTML structure from search.md")
println("3. The search index will be automatically loaded from /assets/search-index.json")