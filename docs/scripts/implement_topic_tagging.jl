#!/usr/bin/env julia

"""
Topic Tagging and Categorization System

This script implements comprehensive topic tagging and categorization for all
documentation pages, enabling topic-based content browsing and recommendations.

Usage:
    julia docs/scripts/implement_topic_tagging.jl [--dry-run] [--verbose]
"""

using Markdown
using Dates

# Configuration
const DOCS_SRC_DIR = joinpath(@__DIR__, "..", "src")

# Comprehensive topic taxonomy
const TOPIC_TAXONOMY = Dict(
    # Primary categories
    "getting-started" => Dict(
        "description" => "New user onboarding and basic concepts",
        "keywords" => ["installation", "quick-start", "first-strategy", "tutorial", "beginner", "setup", "introduction"],
        "icon" => "🚀",
        "difficulty" => "beginner"
    ),
    
    "strategy-development" => Dict(
        "description" => "Building and implementing trading strategies",
        "keywords" => ["strategy", "trading-logic", "indicators", "signals", "call!", "dispatch", "backtest", "algorithm"],
        "icon" => "🏗️",
        "difficulty" => "intermediate"
    ),
    
    "data-management" => Dict(
        "description" => "Working with market data and timeframes",
        "keywords" => ["ohlcv", "market-data", "timeframes", "storage", "zarr", "fetch", "historical", "candles"],
        "icon" => "📊",
        "difficulty" => "intermediate"
    ),
    
    "execution-modes" => Dict(
        "description" => "Simulation, paper, and live trading environments",
        "keywords" => ["simulation", "paper-trading", "live-trading", "backtesting", "sim-mode", "paper-mode", "live-mode"],
        "icon" => "🔄",
        "difficulty" => "intermediate"
    ),
    
    "exchanges" => Dict(
        "description" => "Exchange integration and connectivity",
        "keywords" => ["ccxt", "api", "binance", "bybit", "kucoin", "exchange", "connectivity", "markets"],
        "icon" => "🏦",
        "difficulty" => "intermediate"
    ),
    
    "optimization" => Dict(
        "description" => "Parameter optimization and performance tuning",
        "keywords" => ["parameters", "grid-search", "bayesian", "performance", "optim", "tuning", "hyperparameters"],
        "icon" => "⚡",
        "difficulty" => "advanced"
    ),
    
    "margin-trading" => Dict(
        "description" => "Leverage and margin trading features",
        "keywords" => ["leverage", "isolated", "cross", "positions", "margin", "futures", "derivatives"],
        "icon" => "📈",
        "difficulty" => "advanced"
    ),
    
    "troubleshooting" => Dict(
        "description" => "Problem resolution and debugging",
        "keywords" => ["errors", "debugging", "performance", "installation", "problems", "issues", "fixes"],
        "icon" => "🔧",
        "difficulty" => "any"
    ),
    
    "configuration" => Dict(
        "description" => "Settings and environment configuration",
        "keywords" => ["settings", "toml", "secrets", "environment", "config", "setup", "parameters"],
        "icon" => "⚙️",
        "difficulty" => "beginner"
    ),
    
    "visualization" => Dict(
        "description" => "Charts, plotting, and analysis tools",
        "keywords" => ["plotting", "charts", "analysis", "metrics", "balloons", "visualization", "graphs"],
        "icon" => "📈",
        "difficulty" => "intermediate"
    ),
    
    "api-reference" => Dict(
        "description" => "Function and API documentation",
        "keywords" => ["api", "functions", "reference", "documentation", "methods", "parameters"],
        "icon" => "📚",
        "difficulty" => "advanced"
    ),
    
    "customization" => Dict(
        "description" => "Extending and customizing Planar",
        "keywords" => ["customization", "extensions", "plugins", "hooks", "custom", "extend"],
        "icon" => "🔧",
        "difficulty" => "advanced"
    )
)

# File path to topic mappings (explicit assignments)
const PATH_TOPIC_MAPPINGS = Dict(
    # Getting Started
    r"getting-started/" => ["getting-started"],
    r"getting-started/installation\.md" => ["getting-started", "configuration"],
    r"getting-started/quick-start\.md" => ["getting-started", "strategy-development"],
    r"getting-started/first-strategy\.md" => ["getting-started", "strategy-development"],
    
    # Guides
    r"guides/strategy-development\.md" => ["strategy-development", "optimization"],
    r"guides/data-management\.md" => ["data-management", "exchanges"],
    r"guides/execution-modes\.md" => ["execution-modes", "strategy-development"],
    
    # Core topics
    r"optimization\.md" => ["optimization", "strategy-development"],
    r"exchanges\.md" => ["exchanges", "configuration"],
    r"config\.md" => ["configuration"],
    r"plotting\.md" => ["visualization"],
    r"strategy\.md" => ["strategy-development"],
    r"data\.md" => ["data-management"],
    
    # Engine
    r"engine/" => ["execution-modes"],
    r"engine/backtesting\.md" => ["execution-modes", "strategy-development"],
    r"engine/paper\.md" => ["execution-modes"],
    r"engine/live\.md" => ["execution-modes", "configuration"],
    
    # API
    r"API/" => ["api-reference"],
    r"reference/" => ["api-reference"],
    
    # Troubleshooting
    r"troubleshooting/" => ["troubleshooting"],
    
    # Customizations
    r"customizations/" => ["customization", "api-reference"],
    
    # Advanced
    r"advanced/" => ["optimization", "customization"],
    
    # Watchers
    r"watchers/" => ["visualization", "configuration"]
)

struct TopicTagger
    dry_run::Bool
    verbose::Bool
    stats::Dict{String, Int}
    topic_index::Dict{String, Vector{String}}  # topic -> files
    
    function TopicTagger(; dry_run=false, verbose=false)
        new(dry_run, verbose, 
            Dict("files_processed" => 0, "tags_added" => 0, "frontmatter_created" => 0),
            Dict{String, Vector{String}}())
    end
end

function process_all_documents(tagger::TopicTagger)
    println("🏷️  Implementing topic tagging and categorization...")
    
    # Find all markdown files
    md_files = find_markdown_files(DOCS_SRC_DIR)
    
    for file_path in md_files
        process_document(tagger, file_path)
    end
    
    # Generate topic index and browsing interface
    generate_topic_index(tagger)
    generate_topic_browser(tagger)
    
    print_summary(tagger)
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

function process_document(tagger::TopicTagger, file_path::String)
    tagger.verbose && println("Processing: $file_path")
    
    # Read the file
    content = read(file_path, String)
    original_content = content
    
    # Extract frontmatter and body
    frontmatter, body = extract_frontmatter(content)
    
    # Determine topics for this file
    topics = determine_topics(file_path, body)
    
    if !isempty(topics)
        # Update topic index
        rel_path = relpath(file_path, DOCS_SRC_DIR)
        for topic in topics
            if !haskey(tagger.topic_index, topic)
                tagger.topic_index[topic] = String[]
            end
            push!(tagger.topic_index[topic], rel_path)
        end
        
        # Add topics to frontmatter
        new_frontmatter = add_topics_to_frontmatter(frontmatter, topics, file_path)
        
        # Reconstruct content
        new_content = reconstruct_content(new_frontmatter, body)
        
        # Update statistics and write file
        if new_content != original_content
            tagger.stats["files_processed"] += 1
            tagger.stats["tags_added"] += length(topics)
            if isempty(frontmatter)
                tagger.stats["frontmatter_created"] += 1
            end
            
            if !tagger.dry_run
                write(file_path, new_content)
                tagger.verbose && println("  ✅ Added topics: $(join(topics, ", "))")
            else
                tagger.verbose && println("  🔍 Would add topics: $(join(topics, ", "))")
            end
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

function determine_topics(file_path::String, content::String)
    topics = Set{String}()
    rel_path = relpath(file_path, DOCS_SRC_DIR)
    content_lower = lowercase(content)
    
    # 1. Path-based topic assignment (explicit mappings)
    for (pattern, path_topics) in PATH_TOPIC_MAPPINGS
        if occursin(pattern, rel_path)
            union!(topics, path_topics)
        end
    end
    
    # 2. Content-based topic detection
    for (topic, info) in TOPIC_TAXONOMY
        keywords = info["keywords"]
        keyword_matches = sum(contains(content_lower, kw) for kw in keywords)
        
        # Add topic if sufficient keyword density
        if keyword_matches >= 2 || (keyword_matches >= 1 && length(keywords) <= 3)
            push!(topics, topic)
        end
    end
    
    # 3. Special rules for specific content patterns
    
    # API documentation
    if contains(content_lower, "function") && contains(content_lower, "arguments")
        push!(topics, "api-reference")
    end
    
    # Tutorial content
    if contains(content_lower, "step") && contains(content_lower, "tutorial")
        push!(topics, "getting-started")
    end
    
    # Advanced topics
    if contains(content_lower, "advanced") || contains(content_lower, "expert")
        push!(topics, "optimization")
    end
    
    # Margin trading
    if contains(content_lower, "margin") || contains(content_lower, "leverage")
        push!(topics, "margin-trading")
    end
    
    # Ensure at least one topic is assigned
    if isempty(topics)
        # Default topic based on directory
        if contains(rel_path, "API/")
            push!(topics, "api-reference")
        elseif contains(rel_path, "troubleshooting/")
            push!(topics, "troubleshooting")
        elseif contains(rel_path, "guides/")
            push!(topics, "strategy-development")
        else
            push!(topics, "configuration")  # Default fallback
        end
    end
    
    return collect(topics)
end

function add_topics_to_frontmatter(frontmatter::String, topics::Vector{String}, file_path::String)
    lines = isempty(frontmatter) ? String[] : split(frontmatter, '\n')
    
    # Remove existing topics line if present
    filter!(line -> !startswith(line, "topics:"), lines)
    
    # Add new topics
    push!(lines, "topics: [$(join(topics, ", "))]")
    
    # Add metadata
    push!(lines, "last_updated: \"$(today())\"")
    
    # Add difficulty level based on topics
    difficulty = determine_difficulty(topics)
    push!(lines, "difficulty: \"$difficulty\"")
    
    # Add category (primary topic)
    primary_topic = determine_primary_topic(topics, file_path)
    push!(lines, "category: \"$primary_topic\"")
    
    return join(lines, '\n')
end

function determine_difficulty(topics::Vector{String})
    # Determine difficulty based on topic complexity
    difficulty_scores = Dict(
        "getting-started" => 1,
        "configuration" => 1,
        "strategy-development" => 2,
        "data-management" => 2,
        "execution-modes" => 2,
        "exchanges" => 2,
        "visualization" => 2,
        "troubleshooting" => 2,
        "optimization" => 3,
        "margin-trading" => 3,
        "api-reference" => 3,
        "customization" => 3
    )
    
    max_score = maximum(get(difficulty_scores, topic, 2) for topic in topics)
    
    if max_score <= 1
        return "beginner"
    elseif max_score <= 2
        return "intermediate"
    else
        return "advanced"
    end
end

function determine_primary_topic(topics::Vector{String}, file_path::String)
    # Determine the primary topic based on file path and topic priority
    priority_order = [
        "getting-started",
        "strategy-development", 
        "data-management",
        "execution-modes",
        "optimization",
        "exchanges",
        "margin-trading",
        "visualization",
        "api-reference",
        "customization",
        "troubleshooting",
        "configuration"
    ]
    
    for topic in priority_order
        if topic in topics
            return topic
        end
    end
    
    return first(topics)  # Fallback to first topic
end

function reconstruct_content(frontmatter::String, body::String)
    if isempty(frontmatter)
        return body
    else
        return "---\n$frontmatter\n---\n$body"
    end
end

function generate_topic_index(tagger::TopicTagger)
    if tagger.dry_run
        return
    end
    
    # Create topic index file
    index_content = generate_topic_index_content(tagger.topic_index)
    index_path = joinpath(DOCS_SRC_DIR, "resources", "topic-index.md")
    
    # Ensure resources directory exists
    mkpath(dirname(index_path))
    
    write(index_path, index_content)
    tagger.verbose && println("  ✅ Generated topic index: $index_path")
end

function generate_topic_index_content(topic_index::Dict{String, Vector{String}})
    content = """
    # Topic Index
    
    Browse documentation by topic and category.
    
    """
    
    for (topic, info) in TOPIC_TAXONOMY
        if haskey(topic_index, topic)
            files = topic_index[topic]
            icon = info["icon"]
            description = info["description"]
            difficulty = info["difficulty"]
            
            content *= """
            ## $icon $(titlecase(replace(topic, "-" => " ")))
            
            **Difficulty**: $(titlecase(difficulty)) | **Description**: $description
            
            """
            
            for file in sort(files)
                title = get_file_title(file)
                content *= "- [$title]($file)\n"
            end
            
            content *= "\n"
        end
    end
    
    content *= """
    ## Browse by Difficulty
    
    - **[Beginner Topics](#beginner)** - New to Planar? Start here
    - **[Intermediate Topics](#intermediate)** - Ready to build strategies
    - **[Advanced Topics](#advanced)** - Expert-level customization
    
    """
    
    return content
end

function generate_topic_browser(tagger::TopicTagger)
    if tagger.dry_run
        return
    end
    
    # Create topic browser interface
    browser_content = generate_topic_browser_content(tagger.topic_index)
    browser_path = joinpath(DOCS_SRC_DIR, "resources", "browse-by-topic.md")
    
    write(browser_path, browser_content)
    tagger.verbose && println("  ✅ Generated topic browser: $browser_path")
end

function generate_topic_browser_content(topic_index::Dict{String, Vector{String}})
    content = """
    # Browse Documentation by Topic
    
    Find exactly what you're looking for by browsing our comprehensive topic categories.
    
    ## Quick Navigation
    
    """
    
    # Generate quick navigation grid
    for (topic, info) in TOPIC_TAXONOMY
        if haskey(topic_index, topic)
            icon = info["icon"]
            description = info["description"]
            file_count = length(topic_index[topic])
            
            content *= """
            ### $icon [$(titlecase(replace(topic, "-" => " ")))](#{topic})
            $description  
            *$file_count articles*
            
            """
        end
    end
    
    content *= "\n---\n\n"
    
    # Generate detailed sections
    for (topic, info) in TOPIC_TAXONOMY
        if haskey(topic_index, topic)
            files = topic_index[topic]
            icon = info["icon"]
            description = info["description"]
            difficulty = info["difficulty"]
            
            content *= """
            ## $icon $(titlecase(replace(topic, "-" => " "))) {#$topic}
            
            **Difficulty**: $(titlecase(difficulty))  
            **Description**: $description
            
            """
            
            # Group files by type
            getting_started_files = filter(f -> contains(f, "getting-started/"), files)
            guide_files = filter(f -> contains(f, "guides/"), files)
            api_files = filter(f -> contains(f, "API/") || contains(f, "reference/"), files)
            other_files = filter(f -> !contains(f, "getting-started/") && !contains(f, "guides/") && !contains(f, "API/") && !contains(f, "reference/"), files)
            
            if !isempty(getting_started_files)
                content *= "### Getting Started\n"
                for file in sort(getting_started_files)
                    title = get_file_title(file)
                    content *= "- [$title]($file)\n"
                end
                content *= "\n"
            end
            
            if !isempty(guide_files)
                content *= "### Guides\n"
                for file in sort(guide_files)
                    title = get_file_title(file)
                    content *= "- [$title]($file)\n"
                end
                content *= "\n"
            end
            
            if !isempty(api_files)
                content *= "### API Reference\n"
                for file in sort(api_files)
                    title = get_file_title(file)
                    content *= "- [$title]($file)\n"
                end
                content *= "\n"
            end
            
            if !isempty(other_files)
                content *= "### Additional Resources\n"
                for file in sort(other_files)
                    title = get_file_title(file)
                    content *= "- [$title]($file)\n"
                end
                content *= "\n"
            end
            
            content *= "---\n\n"
        end
    end
    
    return content
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

function print_summary(tagger::TopicTagger)
    println("\n📊 Topic Tagging Summary:")
    println("Files processed: $(tagger.stats["files_processed"])")
    println("Tags added: $(tagger.stats["tags_added"])")
    println("Frontmatter created: $(tagger.stats["frontmatter_created"])")
    println("Topics discovered: $(length(tagger.topic_index))")
    
    if !tagger.dry_run
        println("\nTopic distribution:")
        for (topic, files) in sort(collect(tagger.topic_index))
            println("  $topic: $(length(files)) files")
        end
    end
    
    if tagger.dry_run
        println("\n🔍 This was a dry run. Run without --dry-run to apply changes.")
    else
        println("\n✅ Topic tagging and categorization complete!")
    end
end

# Main execution
function main()
    dry_run = "--dry-run" in ARGS
    verbose = "--verbose" in ARGS
    
    tagger = TopicTagger(dry_run=dry_run, verbose=verbose)
    process_all_documents(tagger)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end