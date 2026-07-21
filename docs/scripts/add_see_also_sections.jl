#!/usr/bin/env julia

"""
See Also Sections Generator

This script adds comprehensive "See Also" sections to all documentation pages,
implementing automatic related content suggestions and bidirectional linking.

Usage:
    julia docs/scripts/add_see_also_sections.jl [--dry-run] [--verbose]
"""

using Markdown
using Dates

# Configuration
const DOCS_SRC_DIR = joinpath(@__DIR__, "..", "src")

# Related content mappings with detailed relationships
const RELATED_CONTENT = Dict(
    # Getting Started
    "getting-started/installation.md" => [
        ("getting-started/quick-start.md", "15-minute tutorial to get started immediately"),
        ("getting-started/first-strategy.md", "Build your first trading strategy"),
        ("troubleshooting/installation-issues.md", "Solve common installation problems"),
        ("config.md", "Configure Planar for your environment")
    ],
    
    "getting-started/quick-start.md" => [
        ("getting-started/installation.md", "Complete installation guide"),
        ("getting-started/first-strategy.md", "Learn to build custom strategies"),
        ("guides/strategy-development.md", "Comprehensive strategy development guide"),
        ("guides/data-management.md", "Understanding market data in Planar")
    ],
    
    "getting-started/first-strategy.md" => [
        ("getting-started/quick-start.md", "Quick introduction to Planar"),
        ("guides/strategy-development.md", "Advanced strategy development patterns"),
        ("guides/data-management.md", "Working with market data"),
        ("optimization.md", "Optimize your strategy parameters")
    ],
    
    # Strategy Development
    "guides/strategy-development.md" => [
        ("guides/data-management.md", "Understanding market data and timeframes"),
        ("guides/execution-modes.md", "Simulation, paper, and live trading modes"),
        ("optimization.md", "Parameter optimization and backtesting"),
        ("reference/api/", "Complete API reference"),
        ("troubleshooting/strategy-problems.md", "Debug common strategy issues")
    ],
    
    "guides/data-management.md" => [
        ("guides/strategy-development.md", "Build strategies using market data"),
        ("exchanges.md", "Exchange integration and data sources"),
        ("troubleshooting/performance-issues.md", "Optimize data handling performance"),
        ("config.md", "Configure data storage and fetching")
    ],
    
    "guides/execution-modes.md" => [
        ("guides/strategy-development.md", "Develop strategies for different modes"),
        ("engine/", "Understanding Planar's execution engine"),
        ("troubleshooting/strategy-problems.md", "Troubleshoot execution issues"),
        ("config.md", "Configure execution environments")
    ],
    
    # Core Documentation
    "optimization.md" => [
        ("guides/strategy-development.md", "Build optimizable strategies"),
        ("troubleshooting/performance-issues.md", "Optimize performance"),
        ("reference/api/", "Optimization API reference")
    ],
    
    "exchanges.md" => [
        ("guides/data-management.md", "Fetch data from exchanges"),
        ("config.md", "Configure exchange connections"),
        ("troubleshooting/exchange-issues.md", "Solve exchange connectivity problems")
    ],
    
    "config.md" => [
        ("getting-started/installation.md", "Initial setup and configuration"),
        ("guides/strategy-development.md", "Strategy-specific configuration"),
        ("troubleshooting/", "Configuration troubleshooting")
    ],
    
    # Troubleshooting
    "troubleshooting/index.md" => [
        ("troubleshooting/installation-issues.md", "Installation and setup problems"),
        ("troubleshooting/strategy-problems.md", "Strategy development issues"),
        ("troubleshooting/performance-issues.md", "Performance and optimization"),
        ("troubleshooting/exchange-issues.md", "Exchange connectivity problems")
    ],
    
    "troubleshooting/installation-issues.md" => [
        ("getting-started/installation.md", "Complete installation guide"),
        ("troubleshooting/index.md", "Other troubleshooting topics"),
        ("config.md", "Configuration after installation")
    ],
    
    "troubleshooting/strategy-problems.md" => [
        ("guides/strategy-development.md", "Strategy development guide"),
        ("troubleshooting/index.md", "Other troubleshooting topics"),
        ("reference/api/", "API reference for debugging")
    ],
    
    "troubleshooting/performance-issues.md" => [
        ("optimization.md", "Performance optimization techniques"),
        ("guides/data-management.md", "Efficient data handling"),
        ("troubleshooting/index.md", "Other troubleshooting topics")
    ],
    
    # Reference
    "reference/index.md" => [
        ("reference/api/", "Complete API documentation"),
        ("guides/strategy-development.md", "Learn to use the APIs"),
        ("troubleshooting/", "API troubleshooting")
    ]
)

# Automatic content discovery based on file analysis
const CONTENT_PATTERNS = Dict(
    # If file mentions these concepts, suggest these related pages
    "strategy" => ["guides/strategy-development.md", "optimization.md"],
    "data" => ["guides/data-management.md", "exchanges.md"],
    "backtest" => ["guides/execution-modes.md", "optimization.md"],
    "exchange" => ["exchanges.md", "config.md"],
    "install" => ["getting-started/installation.md", "troubleshooting/installation-issues.md"],
    "optimization" => ["optimization.md", "troubleshooting/performance-issues.md"],
    "error" => ["troubleshooting/index.md"],
    "configuration" => ["config.md"],
    "API" => ["reference/api/"]
)

struct SeeAlsoProcessor
    dry_run::Bool
    verbose::Bool
    stats::Dict{String, Int}
    
    function SeeAlsoProcessor(; dry_run=false, verbose=false)
        new(dry_run, verbose, Dict("files_processed" => 0, "sections_added" => 0, "links_added" => 0))
    end
end

function process_all_documents(processor::SeeAlsoProcessor)
    println("📚 Adding 'See Also' sections to Planar documentation...")
    
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

function process_document(processor::SeeAlsoProcessor, file_path::String)
    processor.verbose && println("Processing: $file_path")
    
    # Read the file
    content = read(file_path, String)
    original_content = content
    
    # Check if "See Also" section already exists
    if contains(content, "## See Also") || contains(content, "## Related Topics")
        processor.verbose && println("  ⏭️  Already has See Also section: $file_path")
        return
    end
    
    # Add "See Also" section
    new_content = add_see_also_section(content, file_path)
    
    # Update statistics and write file
    if new_content != original_content
        processor.stats["files_processed"] += 1
        processor.stats["sections_added"] += 1
        processor.stats["links_added"] += count_links_in_see_also(new_content, original_content)
        
        if !processor.dry_run
            write(file_path, new_content)
            processor.verbose && println("  ✅ Added See Also section: $file_path")
        else
            processor.verbose && println("  🔍 Would add See Also section: $file_path")
        end
    end
end

function add_see_also_section(content::String, file_path::String)
    # Get relative path for lookup
    rel_path = relpath(file_path, DOCS_SRC_DIR)
    
    # Get related content from explicit mappings
    explicit_related = get(RELATED_CONTENT, rel_path, Tuple{String, String}[])
    
    # Get automatic suggestions based on content analysis
    automatic_related = discover_related_content(content, rel_path)
    
    # Combine and deduplicate
    all_related = combine_related_content(explicit_related, automatic_related)
    
    if isempty(all_related)
        return content
    end
    
    # Generate the "See Also" section
    see_also_section = generate_see_also_section(all_related, rel_path)
    
    # Find the best insertion point
    lines = String.(split(content, '\n'))
    insert_idx = find_insertion_point(lines)
    
    if insert_idx > 0
        # Insert before a specific section
        insert!(lines, insert_idx, "")
        insert!(lines, insert_idx + 1, see_also_section)
        return join(lines, '\n')
    else
        # Append at the end
        return content * "\n\n" * see_also_section
    end
end

function discover_related_content(content::String, current_file::String)
    related = Tuple{String, String}[]
    content_lower = lowercase(content)
    
    for (pattern, suggestions) in CONTENT_PATTERNS
        if contains(content_lower, pattern)
            for suggestion in suggestions
                if suggestion != current_file  # Don't suggest self
                    description = get_auto_description(suggestion, pattern)
                    push!(related, (suggestion, description))
                end
            end
        end
    end
    
    return related
end

function combine_related_content(explicit::Vector{Tuple{String, String}}, automatic::Vector{Tuple{String, String}})
    # Start with explicit mappings (higher priority)
    combined = copy(explicit)
    
    # Add automatic suggestions that aren't already included
    explicit_files = Set(first(item) for item in explicit)
    
    for item in automatic
        if first(item) ∉ explicit_files
            push!(combined, item)
        end
    end
    
    # Limit to reasonable number of suggestions
    return length(combined) > 6 ? combined[1:6] : combined
end

function generate_see_also_section(related::Vector{Tuple{String, String}}, current_file::String)
    section = "## See Also\n\n"
    
    for (rel_file, description) in related
        # Convert to proper link with relative path adjustment
        link_path = adjust_relative_path(rel_file, current_file)
        title = get_file_title(rel_file)
        
        section *= "- **[$title]($link_path)** - $description\n"
    end
    
    return section
end

function adjust_relative_path(target_file::String, current_file::String)
    # Calculate relative path from current file to target file
    current_dir = dirname(current_file)
    
    if current_dir == "."
        # Current file is in root, target path is as-is
        return target_file
    else
        # Need to go up directories
        depth = length(split(current_dir, '/'))
        prefix = repeat("../", depth)
        return prefix * target_file
    end
end

function get_file_title(file_path::String)
    # Extract title from filename
    basename_no_ext = replace(basename(file_path), ".md" => "")
    
    # Special cases for better titles
    title_mappings = Dict(
        "index" => "Overview",
        "quick-start" => "Quick Start",
        "first-strategy" => "First Strategy",
        "strategy-development" => "Strategy Development",
        "data-management" => "Data Management",
        "execution-modes" => "Execution Modes",
        "installation-issues" => "Installation Issues",
        "strategy-problems" => "Strategy Problems",
        "performance-issues" => "Performance Issues",
        "exchange-issues" => "Exchange Issues"
    )
    
    return get(title_mappings, basename_no_ext, titlecase(replace(basename_no_ext, "-" => " ")))
end

function get_auto_description(file_path::String, pattern::String)
    # Generate descriptions based on the pattern that triggered the suggestion
    descriptions = Dict(
        "strategy" => "Strategy development and implementation",
        "data" => "Data handling and management",
        "backtest" => "Backtesting and simulation",
        "exchange" => "Exchange integration and configuration",
        "install" => "Installation and setup guidance",
        "optimization" => "Performance optimization techniques",
        "error" => "Troubleshooting and problem resolution",
        "configuration" => "Configuration and settings",
        "API" => "API reference and documentation"
    )
    
    base_desc = get(descriptions, pattern, "Related information")
    
    # Add file-specific context
    if contains(file_path, "troubleshooting")
        return "Troubleshooting: $base_desc"
    elseif contains(file_path, "guides")
        return "Guide: $base_desc"
    elseif contains(file_path, "getting-started")
        return "Getting started: $base_desc"
    elseif contains(file_path, "reference")
        return "Reference: $base_desc"
    else
        return base_desc
    end
end

function find_insertion_point(lines::Vector{String})
    # Look for common end sections to insert before
    end_sections = [
        "## Next Steps",
        "## What's Next", 
        "## Additional Resources",
        "## Getting Help",
        "## Keep Experimenting",
        "## Congratulations",
        "## Summary"
    ]
    
    for (i, line) in enumerate(lines)
        if any(section -> startswith(line, section), end_sections)
            return i
        end
    end
    
    # Look for the last ## section and insert before it
    last_section_idx = 0
    for (i, line) in enumerate(lines)
        if startswith(line, "## ") && !startswith(line, "### ")
            last_section_idx = i
        end
    end
    
    return last_section_idx > 0 ? last_section_idx : 0
end

function count_links_in_see_also(new_content::String, original_content::String)
    # Count links added in the See Also section
    see_also_match = match(r"## See Also.*?(?=\n## |\n# |\z)"s, new_content)
    if see_also_match !== nothing
        see_also_text = see_also_match.match
        return length(collect(eachmatch(r"\[.*?\]\(.*?\)", see_also_text)))
    end
    return 0
end

function print_summary(processor::SeeAlsoProcessor)
    println("\n📊 See Also Enhancement Summary:")
    println("Files processed: $(processor.stats["files_processed"])")
    println("See Also sections added: $(processor.stats["sections_added"])")
    println("Related links added: $(processor.stats["links_added"])")
    
    if processor.dry_run
        println("\n🔍 This was a dry run. Run without --dry-run to apply changes.")
    else
        println("\n✅ See Also enhancement complete!")
    end
end

# Main execution
function main()
    dry_run = "--dry-run" in ARGS
    verbose = "--verbose" in ARGS
    
    processor = SeeAlsoProcessor(dry_run=dry_run, verbose=verbose)
    process_all_documents(processor)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end