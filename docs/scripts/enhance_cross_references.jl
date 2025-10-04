#!/usr/bin/env julia

"""
Cross-Reference Enhancement Script

This script implements comprehensive cross-referencing throughout the Planar documentation
by adding contextual links, "See Also" sections, and topic tags to all documentation files.

Usage:
    julia docs/scripts/enhance_cross_references.jl [--dry-run] [--verbose]
"""

using Markdown
using Dates

# Configuration
const DOCS_SRC_DIR = joinpath(@__DIR__, "..", "src")
const CROSS_REF_CONFIG = joinpath(@__DIR__, "cross_reference_config.yml")

# Link patterns and mappings
const CONCEPT_LINKS = Dict(
    # Core concepts
    "strategy" => "[strategy](../guides/strategy-development.md)",
    "strategies" => "[strategies](../guides/strategy-development.md)",
    "backtest" => "[backtest](../guides/execution-modes.md#simulation-mode)",
    "backtesting" => "[backtesting](../guides/execution-modes.md#simulation-mode)",
    "paper trading" => "[paper trading](../guides/execution-modes.md#paper-mode)",
    "live trading" => "[live trading](../guides/execution-modes.md#live-mode)",
    "simulation" => "[simulation](../guides/execution-modes.md#simulation-mode)",
    "optimization" => "[optimization](../optimization.md)",
    "parameter optimization" => "[parameter optimization](../optimization.md)",
    
    # Technical concepts
    "OHLCV" => "[OHLCV](../guides/data-management.md#ohlcv-data)",
    "OHLCV data" => "[OHLCV data](../guides/data-management.md#ohlcv-data)",
    "market data" => "[market data](../guides/data-management.md)",
    "data management" => "[data management](../guides/data-management.md)",
    "timeframe" => "[timeframe](../guides/data-management.md#timeframes)",
    "timeframes" => "[timeframes](../guides/data-management.md#timeframes)",
    
    # Exchange concepts
    "exchange" => "[exchange](../exchanges.md)",
    "exchanges" => "[exchanges](../exchanges.md)",
    "CCXT" => "[CCXT](../exchanges.md#ccxt-integration)",
    "API keys" => "[API keys](../getting-started/installation.md#api-configuration)",
    
    # Margin trading
    "margin trading" => "[margin trading](../guides/strategy-development.md#margin-trading-concepts)",
    "leverage" => "[leverage](../guides/strategy-development.md#margin-modes)",
    "isolated margin" => "[isolated margin](../guides/strategy-development.md#margin-modes)",
    "cross margin" => "[cross margin](../guides/strategy-development.md#margin-modes)",
    
    # Technical indicators
    "RSI" => "[RSI](../guides/strategy-development.md#technical-indicators)",
    "moving average" => "[moving average](../guides/strategy-development.md#technical-indicators)",
    "technical indicators" => "[technical indicators](../guides/strategy-development.md#technical-indicators)",
    
    # Configuration
    "configuration" => "[configuration](../config.md)",
    "planar.toml" => "[planar.toml](../config.md#configuration-file)",
    "secrets.toml" => "[secrets.toml](../config.md#secrets-management)",
    
    # Troubleshooting
    "troubleshooting" => "[troubleshooting](../troubleshooting/)",
    "installation issues" => "[installation issues](../troubleshooting/installation-issues.md)",
    "performance issues" => "[performance issues](../troubleshooting/performance-issues.md)",
    
    # Julia concepts
    "Julia" => "[Julia](https://julialang.org/)",
    "dispatch system" => "[dispatch system](../guides/strategy-development.md#dispatch-system)",
    "multiple dispatch" => "[multiple dispatch](../guides/strategy-development.md#dispatch-system)",
)

# Topic categories for tagging
const TOPIC_CATEGORIES = Dict(
    "getting-started" => ["installation", "quick-start", "first-strategy", "tutorial"],
    "strategy-development" => ["strategy", "trading-logic", "indicators", "signals"],
    "data-management" => ["ohlcv", "market-data", "timeframes", "storage"],
    "execution-modes" => ["simulation", "paper-trading", "live-trading", "backtesting"],
    "exchanges" => ["ccxt", "api", "binance", "bybit", "kucoin"],
    "optimization" => ["parameters", "grid-search", "bayesian", "performance"],
    "margin-trading" => ["leverage", "isolated", "cross", "positions"],
    "troubleshooting" => ["errors", "debugging", "performance", "installation"],
    "configuration" => ["settings", "toml", "secrets", "environment"],
    "visualization" => ["plotting", "charts", "analysis", "metrics"]
)

# Related content mappings
const RELATED_CONTENT = Dict(
    "getting-started/installation.md" => [
        "getting-started/quick-start.md",
        "getting-started/first-strategy.md",
        "troubleshooting/installation-issues.md"
    ],
    "getting-started/quick-start.md" => [
        "getting-started/installation.md",
        "getting-started/first-strategy.md",
        "guides/strategy-development.md"
    ],
    "getting-started/first-strategy.md" => [
        "getting-started/quick-start.md",
        "guides/strategy-development.md",
        "guides/data-management.md"
    ],
    "guides/strategy-development.md" => [
        "guides/data-management.md",
        "guides/execution-modes.md",
        "optimization.md",
        "reference/api/"
    ],
    "guides/data-management.md" => [
        "guides/strategy-development.md",
        "exchanges.md",
        "troubleshooting/performance-issues.md"
    ],
    "guides/execution-modes.md" => [
        "guides/strategy-development.md",
        "engine/",
        "troubleshooting/strategy-problems.md"
    ]
)

struct DocumentProcessor
    dry_run::Bool
    verbose::Bool
    stats::Dict{String, Int}
    
    function DocumentProcessor(; dry_run=false, verbose=false)
        new(dry_run, verbose, Dict("files_processed" => 0, "links_added" => 0, "see_also_added" => 0))
    end
end

function process_all_documents(processor::DocumentProcessor)
    println("🔗 Enhancing cross-references in Planar documentation...")
    
    # Find all markdown files
    md_files = find_markdown_files(DOCS_SRC_DIR)
    
    for file_path in md_files
        process_document(processor, file_path)
    end
    
    print_summary(processor)
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

function process_document(processor::DocumentProcessor, file_path::String)
    processor.verbose && println("Processing: $file_path")
    
    # Read the file
    content = read(file_path, String)
    original_content = content
    
    # Extract frontmatter if present
    frontmatter, body = extract_frontmatter(content)
    
    # Add contextual links
    body = add_contextual_links(body, file_path)
    
    # Add "See Also" section
    body = add_see_also_section(body, file_path)
    
    # Add topic tags to frontmatter
    frontmatter = add_topic_tags(frontmatter, file_path, body)
    
    # Reconstruct content
    new_content = reconstruct_content(frontmatter, body)
    
    # Update statistics
    if new_content != original_content
        processor.stats["files_processed"] += 1
        processor.stats["links_added"] += count_new_links(original_content, new_content)
        
        # Write file if not dry run
        if !processor.dry_run
            write(file_path, new_content)
            processor.verbose && println("  ✅ Updated: $file_path")
        else
            processor.verbose && println("  🔍 Would update: $file_path")
        end
    end
end

function extract_frontmatter(content::String)
    lines = split(content, '\n')
    
    if length(lines) >= 3 && lines[1] == "---"
        # Find closing ---
        end_idx = findfirst(i -> i > 1 && lines[i] == "---", 2:length(lines))
        if end_idx !== nothing
            end_idx += 1  # Adjust for 1-based indexing
            frontmatter_lines = lines[2:end_idx-1]
            body_lines = lines[end_idx+1:end]
            
            frontmatter = join(frontmatter_lines, '\n')
            body = join(body_lines, '\n')
            
            return frontmatter, body
        end
    end
    
    return "", content
end

function add_contextual_links(body::String, file_path::String)
    # Add contextual links for key concepts
    for (concept, link) in CONCEPT_LINKS
        # Create regex pattern that matches the concept but not if it's already a link
        pattern = Regex("(?<!\\[)\\b$(escape_regex(concept))\\b(?!\\])")
        
        # Replace only if not already linked
        body = replace(body, pattern => link; count=3)  # Limit to 3 replacements per concept
    end
    
    return body
end

function add_see_also_section(body::String, file_path::String)
    # Get relative path for lookup
    rel_path = relpath(file_path, DOCS_SRC_DIR)
    
    # Check if "See Also" section already exists
    if contains(body, "## See Also") || contains(body, "## Related Topics")
        return body
    end
    
    # Get related content
    related = get(RELATED_CONTENT, rel_path, String[])
    
    if !isempty(related)
        see_also_section = generate_see_also_section(related, rel_path)
        
        # Add before the last section (usually "Next Steps" or similar)
        lines = String.(split(body, '\n'))
        insert_idx = find_see_also_insertion_point(lines)
        
        if insert_idx > 0
            insert!(lines, insert_idx, "")
            insert!(lines, insert_idx + 1, see_also_section)
            body = join(lines, '\n')
        else
            # Append at the end
            body = body * "\n\n" * see_also_section
        end
    end
    
    return body
end

function generate_see_also_section(related::Vector{String}, current_file::String)
    section = "## See Also\n\n"
    
    for rel_file in related
        # Convert to proper link
        if endswith(rel_file, "/")
            # Directory link
            title = titlecase(replace(basename(rel_file), "-" => " "))
            section *= "- **[$title]($rel_file)** - Comprehensive guide\n"
        else
            # File link
            title = get_file_title(rel_file)
            section *= "- **[$title]($rel_file)** - $(get_file_description(rel_file))\n"
        end
    end
    
    return section
end

function get_file_title(file_path::String)
    # Extract title from filename or use a mapping
    basename_no_ext = replace(basename(file_path), ".md" => "")
    return titlecase(replace(basename_no_ext, "-" => " "))
end

function get_file_description(file_path::String)
    # Provide brief descriptions for common files
    descriptions = Dict(
        "installation.md" => "Setup and installation guide",
        "quick-start.md" => "15-minute getting started tutorial",
        "first-strategy.md" => "Build your first trading strategy",
        "strategy-development.md" => "Complete strategy development guide",
        "data-management.md" => "Working with market data",
        "execution-modes.md" => "Simulation, paper, and live trading",
        "optimization.md" => "Parameter optimization techniques"
    )
    
    return get(descriptions, basename(file_path), "Related information")
end

function add_topic_tags(frontmatter::String, file_path::String, body::String)
    # Determine topics based on file path and content
    topics = determine_topics(file_path, body)
    
    if !isempty(topics) && !isempty(frontmatter)
        # Add topics to existing frontmatter
        lines = split(frontmatter, '\n')
        
        # Check if topics already exist
        has_topics = any(line -> startswith(line, "topics:"), lines)
        
        if !has_topics
            push!(lines, "topics: [$(join(topics, ", "))]")
            push!(lines, "last_updated: \"$(today())\"")
            frontmatter = join(lines, '\n')
        end
    elseif !isempty(topics) && isempty(frontmatter)
        # Create new frontmatter
        frontmatter = "topics: [$(join(topics, ", "))]\nlast_updated: \"$(today())\""
    end
    
    return frontmatter
end

function determine_topics(file_path::String, body::String)
    topics = Set{String}()
    
    # Add topics based on file path
    rel_path = relpath(file_path, DOCS_SRC_DIR)
    
    for (category, keywords) in TOPIC_CATEGORIES
        if contains(rel_path, category) || any(kw -> contains(lowercase(body), kw), keywords)
            push!(topics, category)
        end
    end
    
    return collect(topics)
end

function reconstruct_content(frontmatter::String, body::String)
    if isempty(frontmatter)
        return body
    else
        return "---\n$frontmatter---\n$body"
    end
end

function find_see_also_insertion_point(lines::Vector{String})
    # Look for common end sections to insert before
    end_sections = ["## Next Steps", "## What's Next", "## Additional Resources", "## Getting Help"]
    
    for (i, line) in enumerate(lines)
        if any(section -> startswith(line, section), end_sections)
            return i
        end
    end
    
    return 0  # Insert at end
end

function count_new_links(original::String, new::String)
    original_links = length(collect(eachmatch(r"\[.*?\]\(.*?\)", original)))
    new_links = length(collect(eachmatch(r"\[.*?\]\(.*?\)", new)))
    return new_links - original_links
end

function escape_regex(s::String)
    # Escape special regex characters
    return replace(s, r"[.*+?^${}()|[\]\\]" => s"\\\0")
end

function print_summary(processor::DocumentProcessor)
    println("\n📊 Cross-Reference Enhancement Summary:")
    println("Files processed: $(processor.stats["files_processed"])")
    println("Links added: $(processor.stats["links_added"])")
    println("See Also sections added: $(processor.stats["see_also_added"])")
    
    if processor.dry_run
        println("\n🔍 This was a dry run. Use --apply to make changes.")
    else
        println("\n✅ Cross-reference enhancement complete!")
    end
end

# Main execution
function main()
    dry_run = "--dry-run" in ARGS
    verbose = "--verbose" in ARGS
    
    processor = DocumentProcessor(dry_run=dry_run, verbose=verbose)
    process_all_documents(processor)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end