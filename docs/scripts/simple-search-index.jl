#!/usr/bin/env julia

"""
Simple search index generator for Planar documentation.
"""

using Pkg
Pkg.activate(".")

try
    using JSON3
catch
    Pkg.add("JSON3")
    using JSON3
end

using Markdown
using Dates

# Configuration
const DOCS_SRC_DIR = joinpath(@__DIR__, "..", "src")
const SEARCH_INDEX_FILE = joinpath(@__DIR__, "..", "src", "assets", "search-index.json")

function simple_parse_frontmatter(content::String)
    """Simple frontmatter parser that handles basic cases."""
    lines = split(content, '\n')
    if length(lines) < 2 || lines[1] != "---"
        return Dict{String,Any}(), content
    end
    
    # Find end of frontmatter
    end_idx = 0
    for i in 2:length(lines)
        if lines[i] == "---"
            end_idx = i
            break
        end
    end
    
    if end_idx == 0
        return Dict{String,Any}(), content
    end
    
    # Simple key-value parsing
    frontmatter = Dict{String,Any}()
    for line in lines[2:end_idx-1]
        if contains(line, ":")
            parts = split(line, ":", limit=2)
            if length(parts) == 2
                key = strip(parts[1])
                value = strip(parts[2])
                # Remove quotes if present
                value = replace(value, r"^\"(.*)\"$" => s"\1")
                frontmatter[key] = value
            end
        end
    end
    
    remaining_content = join(lines[end_idx+1:end], '\n')
    return frontmatter, remaining_content
end

function extract_text_content(markdown_content::String)
    """Extract plain text from markdown."""
    # Remove code blocks
    content = replace(markdown_content, r"```[^`]*```"s => " ")
    content = replace(content, r"`[^`]*`" => " ")
    
    # Remove links but keep text
    content = replace(content, r"\[([^\]]*)\]\([^\)]*\)" => s"\1")
    
    # Remove markdown formatting
    content = replace(content, r"[#*_`]" => "")
    
    # Clean up whitespace
    content = replace(content, r"\s+" => " ")
    content = strip(content)
    
    return content
end

function extract_headings(markdown_content::String)
    """Extract headings from markdown."""
    headings = String[]
    for line in split(markdown_content, '\n')
        if startswith(line, "#")
            heading = replace(line, r"^#+\s*" => "")
            heading = strip(heading)
            if !isempty(heading)
                push!(headings, heading)
            end
        end
    end
    return headings
end

function create_excerpt(text::String, max_length::Int = 200)
    """Create excerpt from text."""
    # Ensure text is a string
    text = string(text)
    
    if length(text) <= max_length
        return text
    end
    
    truncated = text[1:max_length]
    last_space = findlast(' ', truncated)
    
    if last_space !== nothing && last_space > max_length * 0.8
        return text[1:last_space] * "..."
    else
        return truncated * "..."
    end
end

function process_markdown_file(filepath::String, base_path::String)
    """Process a markdown file."""
    try
        content = read(filepath, String)
        frontmatter, markdown_content = simple_parse_frontmatter(content)
        
        # Extract metadata with defaults
        title = get(frontmatter, "title", splitext(basename(filepath))[1])
        description = get(frontmatter, "description", "")
        category = get(frontmatter, "category", "reference")
        difficulty = get(frontmatter, "difficulty", "intermediate")
        
        # Convert relative path to URL
        rel_path = relpath(filepath, base_path)
        url = "/" * replace(rel_path, ".md" => ".html")
        
        # Extract content
        text_content = extract_text_content(markdown_content)
        headings = extract_headings(markdown_content)
        excerpt = create_excerpt(string(text_content))
        
        return Dict(
            "title" => title,
            "description" => description,
            "category" => category,
            "difficulty" => difficulty,
            "path" => rel_path,
            "url" => url,
            "excerpt" => excerpt,
            "headings" => headings,
            "content_length" => length(text_content)
        )
        
    catch e
        @warn "Skip $(basename(filepath))"
        return nothing
    end
end

function scan_documentation(docs_dir::String)
    """Scan all markdown files."""
    documents = []
    
    for (root, dirs, files) in walkdir(docs_dir)
        for file in files
            if endswith(file, ".md")
                filepath = joinpath(root, file)
                doc = process_markdown_file(filepath, docs_dir)
                if doc !== nothing
                    push!(documents, doc)
                end
            end
        end
    end
    
    return documents
end

function create_search_index(documents::Vector)
    """Create search index."""
    categories = Set{String}()
    difficulties = Set{String}()
    
    for doc in documents
        push!(categories, doc["category"])
        push!(difficulties, doc["difficulty"])
    end
    
    return Dict(
        "documents" => documents,
        "categories" => sort(collect(categories)),
        "difficulties" => sort(collect(difficulties)),
        "generated_at" => string(Dates.now())
    )
end

function main()
    println("Generating simple search index...")
    
    # Ensure output directory exists
    mkpath(dirname(SEARCH_INDEX_FILE))
    
    # Scan documentation
    documents = scan_documentation(DOCS_SRC_DIR)
    println("Found $(length(documents)) documents")
    
    # Create search index
    index = create_search_index(documents)
    
    # Write to file
    open(SEARCH_INDEX_FILE, "w") do f
        JSON3.pretty(f, index)
    end
    
    println("Search index generated: $SEARCH_INDEX_FILE")
    println("Categories: $(join(index["categories"], ", "))")
    println("Difficulties: $(join(index["difficulties"], ", "))")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end