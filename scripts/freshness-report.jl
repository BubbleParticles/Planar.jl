#!/usr/bin/env julia

"""
Content Freshness Report for Planar Documentation

This script analyzes the documentation to identify content that may be outdated
and generates a report with recommendations for updates.
"""

using Dates
using Pkg

const DOCS_DIR = "docs/src"
const REPORT_FILE = "docs/maintenance/freshness-report.md"

struct ContentInfo
    file::String
    last_modified::DateTime
    frontmatter::Dict{String, Any}
    word_count::Int
    has_code_examples::Bool
    external_links::Vector{String}
end

"""
Parse frontmatter from a markdown file
"""
function parse_frontmatter(content::String)::Dict{String, Any}
    frontmatter = Dict{String, Any}()
    
    lines = split(content, '\n')
    if length(lines) < 3 || lines[1] != "---"
        return frontmatter
    end
    
    in_frontmatter = true
    for i in 2:length(lines)
        if lines[i] == "---"
            break
        end
        
        # Simple YAML parsing for key: value pairs
        if occursin(":", lines[i])
            key, value = split(lines[i], ":", limit=2)
            key = strip(key)
            value = strip(value)
            
            # Remove quotes if present
            if startswith(value, "\"") && endswith(value, "\"")
                value = value[2:end-1]
            elseif startswith(value, "'") && endswith(value, "'")
                value = value[2:end-1]
            end
            
            frontmatter[key] = value
        end
    end
    
    return frontmatter
end

"""
Extract external links from content
"""
function extract_external_links(content::String)::Vector{String}
    links = String[]
    
    # Find markdown links with http/https
    for match in eachmatch(r"\[.*?\]\((https?://[^)]+)\)", content)
        push!(links, match.captures[1])
    end
    
    # Find bare URLs
    for match in eachmatch(r"https?://[^\s\)]+", content)
        if !(match.match in links)
            push!(links, match.match)
        end
    end
    
    return unique(links)
end

"""
Analyze a single documentation file
"""
function analyze_file(filepath::String)::ContentInfo
    content = read(filepath, String)
    
    # Get file modification time
    last_modified = Dates.unix2datetime(stat(filepath).mtime)
    
    # Parse frontmatter
    frontmatter = parse_frontmatter(content)
    
    # Count words (excluding frontmatter and code blocks)
    content_without_frontmatter = replace(content, r"^---.*?^---"ms => "")
    content_without_code = replace(content_without_frontmatter, r"```.*?```"ms => "")
    word_count = length(split(content_without_code))
    
    # Check for code examples
    has_code_examples = occursin("```", content)
    
    # Extract external links
    external_links = extract_external_links(content)
    
    return ContentInfo(
        filepath,
        last_modified,
        frontmatter,
        word_count,
        has_code_examples,
        external_links
    )
end

"""
Calculate freshness score (0-100, higher is fresher)
"""
function calculate_freshness_score(info::ContentInfo)::Int
    now_date = now()
    days_old = Dates.value(now_date - info.last_modified) / (1000 * 60 * 60 * 24)
    
    # Base score based on age
    age_score = max(0, 100 - (days_old / 30) * 10)  # Lose 10 points per month
    
    # Bonus for recent frontmatter last_updated
    if haskey(info.frontmatter, "last_updated")
        try
            last_updated = Date(info.frontmatter["last_updated"])
            update_days_old = Dates.value(Date(now_date) - last_updated)
            if update_days_old < days_old
                age_score += 20  # Bonus for explicit updates
            end
        catch
            # Invalid date format, ignore
        end
    end
    
    # Penalty for code examples (more likely to become outdated)
    if info.has_code_examples
        age_score -= 10
    end
    
    # Penalty for external links (may break over time)
    if length(info.external_links) > 5
        age_score -= 5
    end
    
    return max(0, min(100, round(Int, age_score)))
end

"""
Generate freshness report
"""
function generate_report(content_info::Vector{ContentInfo})
    open(REPORT_FILE, "w") do io
        println(io, "# Content Freshness Report - $(now())")
        println(io)
        
        # Calculate scores
        scored_content = [(info, calculate_freshness_score(info)) for info in content_info]
        sort!(scored_content, by=x -> x[2])  # Sort by score (lowest first)
        
        # Summary statistics
        total_files = length(scored_content)
        avg_score = round(sum(score for (_, score) in scored_content) / total_files, digits=1)
        stale_files = count(score < 50 for (_, score) in scored_content)
        outdated_files = count(score < 30 for (_, score) in scored_content)
        
        println(io, "## Summary")
        println(io)
        println(io, "- **Total Files**: $total_files")
        println(io, "- **Average Freshness Score**: $avg_score/100")
        println(io, "- **Stale Files** (score < 50): $stale_files")
        println(io, "- **Outdated Files** (score < 30): $outdated_files")
        println(io)
        
        # Priority updates needed
        if outdated_files > 0
            println(io, "## 🚨 Priority Updates Needed (Score < 30)")
            println(io)
            
            for (info, score) in scored_content
                if score < 30
                    days_old = round(Dates.value(now() - info.last_modified) / (1000 * 60 * 60 * 24))
                    println(io, "### $(info.file) (Score: $score)")
                    println(io, "- **Last Modified**: $(Date(info.last_modified)) ($days_old days ago)")
                    println(io, "- **Word Count**: $(info.word_count)")
                    println(io, "- **Has Code Examples**: $(info.has_code_examples)")
                    println(io, "- **External Links**: $(length(info.external_links))")
                    
                    if haskey(info.frontmatter, "last_updated")
                        println(io, "- **Last Updated (frontmatter)**: $(info.frontmatter["last_updated"])")
                    end
                    
                    println(io)
                end
            end
        end
        
        # Stale content
        stale_count = count(30 <= score < 50 for (_, score) in scored_content)
        if stale_count > 0
            println(io, "## ⚠️ Stale Content (Score 30-49)")
            println(io)
            
            for (info, score) in scored_content
                if 30 <= score < 50
                    days_old = round(Dates.value(now() - info.last_modified) / (1000 * 60 * 60 * 24))
                    println(io, "- **$(info.file)** (Score: $score) - Last modified $days_old days ago")
                end
            end
            println(io)
        end
        
        # Recommendations by category
        println(io, "## Recommendations by Category")
        println(io)
        
        # Group by category if available
        categories = Dict{String, Vector{Tuple{ContentInfo, Int}}}()
        for (info, score) in scored_content
            category = get(info.frontmatter, "category", "uncategorized")
            if !haskey(categories, category)
                categories[category] = []
            end
            push!(categories[category], (info, score))
        end
        
        for (category, items) in sort(collect(categories))
            avg_cat_score = round(sum(score for (_, score) in items) / length(items), digits=1)
            stale_in_cat = count(score < 50 for (_, score) in items)
            
            println(io, "### $category")
            println(io, "- **Files**: $(length(items))")
            println(io, "- **Average Score**: $avg_cat_score")
            println(io, "- **Stale Files**: $stale_in_cat")
            
            if stale_in_cat > 0
                println(io, "- **Action**: Review and update stale content")
            end
            println(io)
        end
        
        # Full report
        println(io, "## Complete Freshness Report")
        println(io)
        println(io, "| File | Score | Last Modified | Word Count | Code Examples | External Links |")
        println(io, "|------|-------|---------------|------------|---------------|----------------|")
        
        for (info, score) in reverse(scored_content)  # Show freshest first
            last_mod = Date(info.last_modified)
            code_icon = info.has_code_examples ? "✅" : "❌"
            score_icon = score >= 70 ? "🟢" : score >= 50 ? "🟡" : score >= 30 ? "🟠" : "🔴"
            
            println(io, "| $(info.file) | $score_icon $score | $last_mod | $(info.word_count) | $code_icon | $(length(info.external_links)) |")
        end
    end
end

"""
Main analysis function
"""
function analyze_documentation_freshness()
    println("Starting documentation freshness analysis...")
    
    # Find all markdown files
    markdown_files = String[]
    for (root, dirs, files) in walkdir(DOCS_DIR)
        for file in files
            if endswith(file, ".md")
                push!(markdown_files, joinpath(root, file))
            end
        end
    end
    
    println("Found $(length(markdown_files)) markdown files")
    
    # Analyze each file
    content_info = ContentInfo[]
    for (i, file) in enumerate(markdown_files)
        print("Analyzing file $i/$(length(markdown_files)): $(basename(file))... ")
        try
            info = analyze_file(file)
            push!(content_info, info)
            println("✅")
        catch e
            println("❌ Error: $e")
        end
    end
    
    # Create maintenance directory if needed
    mkpath(dirname(REPORT_FILE))
    
    # Generate report
    generate_report(content_info)
    
    # Print summary
    total = length(content_info)
    scores = [calculate_freshness_score(info) for info in content_info]
    avg_score = round(sum(scores) / total, digits=1)
    stale_count = count(score < 50 for score in scores)
    outdated_count = count(score < 30 for score in scores)
    
    println("\n" * "="^50)
    println("FRESHNESS ANALYSIS COMPLETE")
    println("="^50)
    println("Total files analyzed: $total")
    println("Average freshness score: $avg_score/100")
    println("Stale files (score < 50): $stale_count")
    println("Outdated files (score < 30): $outdated_count")
    println("\nDetailed report saved to: $REPORT_FILE")
    
    if outdated_count > 0
        println("\n⚠️  $outdated_count files need priority updates!")
    elseif stale_count > 0
        println("\n📝 $stale_count files could use refreshing")
    else
        println("\n✅ All documentation appears fresh!")
    end
end

# Run analysis if script is executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    analyze_documentation_freshness()
end