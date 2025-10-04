#!/usr/bin/env julia

"""
Generate search index for Planar documentation.

This script scans all markdown files in docs/src and creates a searchable index
with metadata, content excerpts, and keyword extraction.
"""

using Pkg
Pkg.activate(".")

# Install required packages if not available
try
    using JSON3
catch
    Pkg.add("JSON3")
    using JSON3
end

try
    using YAML
catch
    Pkg.add("YAML")
    using YAML
end

using Markdown
using Dates

# Configuration
const DOCS_SRC_DIR = joinpath(@__DIR__, "..", "src")
const SEARCH_INDEX_FILE = joinpath(@__DIR__, "..", "src", "assets", "search-index.json")
const MAX_EXCERPT_LENGTH = 200
const MIN_WORD_LENGTH = 3

# Common stop words to exclude from search
const STOP_WORDS = Set([
    "the", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", 
    "by", "from", "up", "about", "into", "through", "during", "before", 
    "after", "above", "below", "between", "among", "this", "that", "these", 
    "those", "is", "are", "was", "were", "be", "been", "being", "have", 
    "has", "had", "do", "does", "did", "will", "would", "could", "should",
    "may", "might", "can", "must", "shall", "a", "an", "as", "if", "then",
    "than", "when", "where", "why", "how", "what", "which", "who", "whom"
])

struct DocumentMetadata
    title::String
    description::String
    category::String
    difficulty::String
    topics::Vector{String}
    last_updated::String
    path::String
    url::String
end

struct SearchDocument
    metadata::DocumentMetadata
    content::String
    excerpt::String
    keywords::Vector{String}
    headings::Vector{String}
end

function parse_frontmatter(content::String)
    """Parse YAML frontmatter from markdown content."""
    lines = split(content, '\n')
    if length(lines) < 2 || lines[1] != "---"
        return Dict(), content
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
        return Dict(), content
    end
    
    # Parse YAML
    frontmatter_text = join(lines[2:end_idx-1], '\n')
    try
        frontmatter = YAML.load(frontmatter_text)
        remaining_content = join(lines[end_idx+1:end], '\n')
        return frontmatter, remaining_content
    catch e
        # If YAML parsing fails, return empty frontmatter and full content
        return Dict(), content
    end
end

function extract_text_content(markdown_content::String)
    """Extract plain text from markdown, removing formatting."""
    # Remove code blocks
    content = replace(markdown_content, r"```[^`]*```"s => " ")
    content = replace(content, r"`[^`]*`" => " ")
    
    # Remove links but keep text
    content = replace(content, r"\[([^\]]*)\]\([^\)]*\)" => s"\1")
    
    # Remove markdown formatting
    content = replace(content, r"[#*_`]" => "")
    content = replace(content, r"^\s*[-*+]\s+" => "", count=typemax(Int))
    content = replace(content, r"^\s*\d+\.\s+" => "", count=typemax(Int))
    
    # Clean up whitespace
    content = replace(content, r"\s+" => " ")
    content = strip(content)
    
    return content
end

function extract_headings(markdown_content::String)
    """Extract all headings from markdown content."""
    headings = String[]
    for line in split(markdown_content, '\n')
        if startswith(line, "#")
            # Remove # symbols and clean up
            heading = replace(line, r"^#+\s*" => "")
            heading = strip(heading)
            if !isempty(heading)
                push!(headings, heading)
            end
        end
    end
    return headings
end

function extract_keywords(text::String, headings::Vector{String})
    """Extract keywords from text content and headings."""
    # Combine text and headings (give headings more weight)
    combined_text = text * " " * join(headings, " ") * " " * join(headings, " ")
    
    # Convert to lowercase and split into words
    words = split(lowercase(combined_text), r"[^\w]+")
    
    # Filter words
    keywords = String[]
    word_counts = Dict{String, Int}()
    
    for word in words
        # Skip short words, stop words, and numbers
        if length(word) >= MIN_WORD_LENGTH && 
           !(word in STOP_WORDS) && 
           !all(isdigit, word)
            
            word_counts[word] = get(word_counts, word, 0) + 1
        end
    end
    
    # Sort by frequency and take top keywords
    sorted_words = sort(collect(word_counts), by=x->x[2], rev=true)
    return [word for (word, count) in sorted_words[1:min(20, length(sorted_words))]]
end



function create_excerpt(text::String, max_length::Int = MAX_EXCERPT_LENGTH)
    """Create a short excerpt from text content."""
    if length(text) <= max_length
        return text
    end
    
    # Find a good breaking point near the max length
    truncated = text[1:max_length]
    last_space = findlast(' ', truncated)
    
    if last_space !== nothing && last_space > max_length * 0.8
        return text[1:last_space] * "..."
    else
        return truncated * "..."
    end
end

function process_markdown_file(filepath::String, base_path::String)
    """Process a single markdown file and extract search data."""
    try
        content = read(filepath, String)
        frontmatter, markdown_content = parse_frontmatter(content)
        
        # Extract metadata with defaults
        title = get(frontmatter, "title", splitext(basename(filepath))[1])
        description = get(frontmatter, "description", "")
        category = get(frontmatter, "category", "reference")
        difficulty = get(frontmatter, "difficulty", "intermediate")
        topics = get(frontmatter, "topics", String[])
        last_updated = get(frontmatter, "last_updated", "")
        
        # Convert relative path to URL
        rel_path = relpath(filepath, base_path)
        url = "/" * replace(rel_path, ".md" => ".html")
        
        # Create metadata
        metadata = DocumentMetadata(
            title, description, category, difficulty, 
            topics, last_updated, rel_path, url
        )
        
        # Extract content
        text_content = extract_text_content(markdown_content)
        headings = extract_headings(markdown_content)
        keywords = extract_keywords(text_content, headings)
        excerpt = create_excerpt(text_content, MAX_EXCERPT_LENGTH)
        
        return SearchDocument(metadata, text_content, excerpt, keywords, headings)
        
    catch e
        @warn "Failed to process file $filepath: $e"
        return nothing
    end
end

function scan_documentation(docs_dir::String)
    """Scan all markdown files in the documentation directory."""
    documents = SearchDocument[]
    
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

function create_search_index(documents::Vector{SearchDocument})
    """Create the final search index structure."""
    index = Dict(
        "documents" => [],
        "categories" => Set{String}(),
        "difficulties" => Set{String}(),
        "topics" => Set{String}(),
        "generated_at" => string(Dates.now())
    )
    
    for doc in documents
        # Add to categories, difficulties, and topics sets
        push!(index["categories"], doc.metadata.category)
        push!(index["difficulties"], doc.metadata.difficulty)
        for topic in doc.metadata.topics
            push!(index["topics"], topic)
        end
        
        # Create document entry
        doc_entry = Dict(
            "title" => doc.metadata.title,
            "description" => doc.metadata.description,
            "category" => doc.metadata.category,
            "difficulty" => doc.metadata.difficulty,
            "topics" => doc.metadata.topics,
            "last_updated" => doc.metadata.last_updated,
            "path" => doc.metadata.path,
            "url" => doc.metadata.url,
            "excerpt" => doc.excerpt,
            "keywords" => doc.keywords,
            "headings" => doc.headings,
            "content_length" => length(doc.content)
        )
        
        push!(index["documents"], doc_entry)
    end
    
    # Convert sets to sorted arrays
    index["categories"] = sort(collect(index["categories"]))
    index["difficulties"] = sort(collect(index["difficulties"]))
    index["topics"] = sort(collect(index["topics"]))
    
    return index
end

function main()
    println("Generating search index for Planar documentation...")
    
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
    println("Topics: $(length(index["topics"])) unique topics")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end