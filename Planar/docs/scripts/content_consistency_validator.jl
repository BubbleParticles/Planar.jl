#!/usr/bin/env julia

"""
Content Consistency Validation System for Planar Documentation

This script validates template compliance, style consistency, and formatting
across all documentation files.
"""

using Dates

# Configuration
const DOCS_ROOT = joinpath(@__DIR__, "..", "src")
const REPORT_DIR = joinpath(@__DIR__, "..", "reports")

# Validation results
struct ValidationIssue
    file_path::String
    line_number::Union{Int, Nothing}
    issue_type::String
    severity::String  # "error", "warning", "info"
    message::String
    suggestion::Union{String, Nothing}
end

struct FileValidation
    file_path::String
    issues::Vector{ValidationIssue}
    has_frontmatter::Bool
    word_count::Int
    heading_structure::Vector{String}
    last_checked::DateTime
end

struct ConsistencyReport
    timestamp::DateTime
    total_files::Int
    files_with_issues::Int
    total_issues::Int
    error_count::Int
    warning_count::Int
    info_count::Int
    files::Vector{FileValidation}
    summary::Dict{String, Any}
end

# Utility functions
function ensure_report_dir()
    if !isdir(REPORT_DIR)
        mkpath(REPORT_DIR)
    end
end

function extract_frontmatter(content::String)::Tuple{Bool, Dict{String, Any}}
    lines = split(content, '\n')
    
    if length(lines) >= 3 && strip(lines[1]) == "---"
        # Look for closing ---
        for i in 2:length(lines)
            if strip(lines[i]) == "---"
                # Found frontmatter
                frontmatter_lines = lines[2:i-1]
                frontmatter = Dict{String, Any}()
                
                for line in frontmatter_lines
                    if occursin(":", line)
                        key, value = split(line, ":", limit=2)
                        frontmatter[strip(key)] = strip(value)
                    end
                end
                
                return (true, frontmatter)
            end
        end
    end
    
    return (false, Dict{String, Any}())
end

function extract_headings(content::String)::Vector{String}
    headings = String[]
    
    for line in split(content, '\n')
        stripped = strip(line)
        if startswith(stripped, "#")
            # Extract heading level and text
            level_match = match(r"^(#+)\s*(.*)", stripped)
            if level_match !== nothing
                level = length(level_match.captures[1])
                text = level_match.captures[2]
                push!(headings, "H$level: $text")
            end
        end
    end
    
    return headings
end

function validate_heading_structure(headings::Vector{String})::Vector{ValidationIssue}
    issues = ValidationIssue[]
    
    if isempty(headings)
        push!(issues, ValidationIssue(
            "",
            nothing,
            "structure",
            "warning",
            "No headings found in document",
            "Add at least one main heading (# Title)"
        ))
        return issues
    end
    
    # Check if first heading is H1
    first_heading = headings[1]
    if !startswith(first_heading, "H1:")
        push!(issues, ValidationIssue(
            "",
            nothing,
            "structure",
            "warning",
            "Document should start with H1 heading",
            "Use # for the main title"
        ))
    end
    
    # Check for heading level jumps
    prev_level = 0
    for (i, heading) in enumerate(headings)
        level_match = match(r"H(\d+):", heading)
        if level_match !== nothing
            level = parse(Int, level_match.captures[1])
            
            if level > prev_level + 1 && prev_level > 0
                push!(issues, ValidationIssue(
                    "",
                    nothing,
                    "structure",
                    "warning",
                    "Heading level jump detected (H$prev_level to H$level)",
                    "Use sequential heading levels (H1, H2, H3, etc.)"
                ))
            end
            
            prev_level = level
        end
    end
    
    return issues
end

function validate_markdown_syntax(content::String, file_path::String)::Vector{ValidationIssue}
    issues = ValidationIssue[]
    lines = split(content, '\n')
    
    for (line_num, line) in enumerate(lines)
        # Check for common markdown issues
        
        # Unmatched code blocks
        if count(c -> c == '`', line) % 2 != 0 && !startswith(strip(line), "```")
            push!(issues, ValidationIssue(
                file_path,
                line_num,
                "syntax",
                "error",
                "Unmatched backticks in line",
                "Ensure all inline code uses paired backticks"
            ))
        end
        
        # Malformed links
        if occursin(r"\[([^\]]*)\]\([^)]*$", line)
            push!(issues, ValidationIssue(
                file_path,
                line_num,
                "syntax",
                "error",
                "Malformed link (missing closing parenthesis)",
                "Complete the link syntax: [text](url)"
            ))
        end
        
        # Missing space after heading hash
        if occursin(r"^#+[^#\s]", strip(line))
            push!(issues, ValidationIssue(
                file_path,
                line_num,
                "style",
                "warning",
                "Missing space after heading hash",
                "Add space: # Heading instead of #Heading"
            ))
        end
        
        # Trailing whitespace
        if endswith(line, " ") || endswith(line, "\t")
            push!(issues, ValidationIssue(
                file_path,
                line_num,
                "style",
                "info",
                "Trailing whitespace detected",
                "Remove trailing spaces and tabs"
            ))
        end
        
        # Very long lines (over 120 characters)
        if length(line) > 120
            push!(issues, ValidationIssue(
                file_path,
                line_num,
                "style",
                "info",
                "Line exceeds 120 characters ($(length(line)) chars)",
                "Consider breaking long lines for better readability"
            ))
        end
    end
    
    return issues
end

function validate_content_standards(content::String, file_path::String)::Vector{ValidationIssue}
    issues = ValidationIssue[]
    
    # Check for required sections in getting-started files
    if occursin("getting-started", file_path)
        required_sections = ["Prerequisites", "Steps", "Next"]
        
        for section in required_sections
            if !occursin(section, content)
                push!(issues, ValidationIssue(
                    file_path,
                    nothing,
                    "content",
                    "warning",
                    "Missing recommended section: $section",
                    "Consider adding a $section section for better user guidance"
                ))
            end
        end
    end
    
    # Check for code examples without language specification
    code_blocks = eachmatch(r"```(\w*)\n", content)
    for match in code_blocks
        if isempty(match.captures[1])
            push!(issues, ValidationIssue(
                file_path,
                nothing,
                "content",
                "warning",
                "Code block without language specification",
                "Specify language: ```julia instead of ```"
            ))
        end
    end
    
    # Check for broken internal references
    internal_links = eachmatch(r"\[([^\]]+)\]\(([^)]+)\)", content)
    for match in internal_links
        url = match.captures[2]
        if !startswith(url, "http") && !startswith(url, "#") && !isfile(joinpath(dirname(file_path), url))
            push!(issues, ValidationIssue(
                file_path,
                nothing,
                "content",
                "error",
                "Broken internal link: $url",
                "Verify the file path exists or update the link"
            ))
        end
    end
    
    return issues
end

function validate_template_compliance(content::String, file_path::String, frontmatter::Dict{String, Any})::Vector{ValidationIssue}
    issues = ValidationIssue[]
    
    # Check for required frontmatter fields
    required_fields = ["title", "description"]
    
    for field in required_fields
        if !haskey(frontmatter, field) || isempty(strip(get(frontmatter, field, "")))
            push!(issues, ValidationIssue(
                file_path,
                nothing,
                "template",
                "warning",
                "Missing or empty frontmatter field: $field",
                "Add $field to the frontmatter section"
            ))
        end
    end
    
    # Check title consistency
    if haskey(frontmatter, "title")
        title = frontmatter["title"]
        # Remove quotes if present
        title = strip(title, ['"', '\''])
        
        # Check if first H1 matches title
        first_h1_match = match(r"^#\s+(.+)$", content, 1)
        if first_h1_match !== nothing
            h1_title = strip(first_h1_match.captures[1])
            if h1_title != title
                push!(issues, ValidationIssue(
                    file_path,
                    nothing,
                    "template",
                    "warning",
                    "H1 title doesn't match frontmatter title",
                    "Ensure consistency between frontmatter title and H1 heading"
                ))
            end
        end
    end
    
    return issues
end

function validate_file(file_path::String)::FileValidation
    println("Validating: $(replace(file_path, DOCS_ROOT => "docs/src"))")
    
    content = read(file_path, String)
    has_frontmatter, frontmatter = extract_frontmatter(content)
    headings = extract_headings(content)
    word_count = length(split(content))
    
    all_issues = ValidationIssue[]
    
    # Run all validation checks
    append!(all_issues, validate_heading_structure(headings))
    append!(all_issues, validate_markdown_syntax(content, file_path))
    append!(all_issues, validate_content_standards(content, file_path))
    append!(all_issues, validate_template_compliance(content, file_path, frontmatter))
    
    # Update file path in issues
    for issue in all_issues
        if isempty(issue.file_path)
            issue = ValidationIssue(
                file_path,
                issue.line_number,
                issue.issue_type,
                issue.severity,
                issue.message,
                issue.suggestion
            )
        end
    end
    
    return FileValidation(
        file_path,
        all_issues,
        has_frontmatter,
        word_count,
        headings,
        now()
    )
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

function generate_consistency_report()::ConsistencyReport
    ensure_report_dir()
    
    markdown_files = find_markdown_files(DOCS_ROOT)
    file_validations = FileValidation[]
    
    println("🔍 Validating content consistency across documentation...")
    println("Found $(length(markdown_files)) markdown files to validate")
    
    for file_path in markdown_files
        validation = validate_file(file_path)
        push!(file_validations, validation)
    end
    
    # Calculate summary statistics
    total_issues = sum(length(fv.issues) for fv in file_validations)
    files_with_issues = count(fv -> !isempty(fv.issues), file_validations)
    
    error_count = sum(count(issue -> issue.severity == "error", fv.issues) for fv in file_validations)
    warning_count = sum(count(issue -> issue.severity == "warning", fv.issues) for fv in file_validations)
    info_count = sum(count(issue -> issue.severity == "info", fv.issues) for fv in file_validations)
    
    consistency_score = length(markdown_files) > 0 ? round(((length(markdown_files) - files_with_issues) / length(markdown_files)) * 100, digits=2) : 100.0
    avg_word_count = length(file_validations) > 0 ? round(sum(fv.word_count for fv in file_validations) / length(file_validations)) : 0
    
    summary = Dict(
        "consistency_score" => consistency_score,
        "avg_word_count" => avg_word_count,
        "files_with_frontmatter" => count(fv -> fv.has_frontmatter, file_validations),
        "frontmatter_percentage" => length(file_validations) > 0 ? round((count(fv -> fv.has_frontmatter, file_validations) / length(file_validations)) * 100, digits=2) : 0.0
    )
    
    return ConsistencyReport(
        now(),
        length(markdown_files),
        files_with_issues,
        total_issues,
        error_count,
        warning_count,
        info_count,
        file_validations,
        summary
    )
end

function save_consistency_report(report::ConsistencyReport)
    ensure_report_dir()
    
    report_file = joinpath(REPORT_DIR, "content_consistency_report.txt")
    
    open(report_file, "w") do io
        println(io, "Planar Documentation Content Consistency Report")
        println(io, "Generated: $(report.timestamp)")
        println(io, "=" ^ 60)
        println(io, "")
        println(io, "Summary:")
        println(io, "  Total files: $(report.total_files)")
        println(io, "  Files with issues: $(report.files_with_issues)")
        println(io, "  Total issues: $(report.total_issues)")
        println(io, "  Errors: $(report.error_count)")
        println(io, "  Warnings: $(report.warning_count)")
        println(io, "  Info: $(report.info_count)")
        println(io, "  Consistency score: $(report.summary["consistency_score"])%")
        println(io, "  Files with frontmatter: $(report.summary["files_with_frontmatter"]) ($(report.summary["frontmatter_percentage"])%)")
        println(io, "  Average word count: $(report.summary["avg_word_count"])")
        println(io, "")
        
        if report.total_issues > 0
            println(io, "Issues by File:")
            println(io, "-" ^ 40)
            
            for file_validation in report.files
                if !isempty(file_validation.issues)
                    relative_path = replace(file_validation.file_path, DOCS_ROOT => "docs/src")
                    println(io, "")
                    println(io, "📄 $relative_path")
                    println(io, "   Word count: $(file_validation.word_count)")
                    println(io, "   Frontmatter: $(file_validation.has_frontmatter ? "✅" : "❌")")
                    println(io, "   Headings: $(length(file_validation.heading_structure))")
                    println(io, "   Issues: $(length(file_validation.issues))")
                    
                    for issue in file_validation.issues
                        severity_icon = issue.severity == "error" ? "❌" : issue.severity == "warning" ? "⚠️" : "ℹ️"
                        line_info = issue.line_number !== nothing ? ":$(issue.line_number)" : ""
                        println(io, "     $severity_icon [$(uppercase(issue.severity))] $(issue.issue_type)$line_info: $(issue.message)")
                        if issue.suggestion !== nothing
                            println(io, "        💡 $(issue.suggestion)")
                        end
                    end
                end
            end
        end
    end
    
    println("📄 Consistency report saved to: $report_file")
end

# Main execution
function main()
    println("🔍 Starting content consistency validation for Planar documentation...")
    
    report = generate_consistency_report()
    
    println("\n📊 Validation Summary:")
    println("  Total files: $(report.total_files)")
    println("  Files with issues: $(report.files_with_issues)")
    println("  Total issues: $(report.total_issues)")
    println("  Errors: $(report.error_count)")
    println("  Warnings: $(report.warning_count)")
    println("  Info: $(report.info_count)")
    println("  Consistency score: $(report.summary["consistency_score"])%")
    
    save_consistency_report(report)
    
    if report.error_count > 0
        println("\n❌ Found $(report.error_count) errors that need to be fixed!")
        exit(1)
    elseif report.warning_count > 0
        println("\n⚠️  Found $(report.warning_count) warnings to consider addressing")
        exit(0)
    else
        println("\n✅ All content passes consistency validation!")
        exit(0)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
