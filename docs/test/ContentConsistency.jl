"""
Content Consistency Checker

This module provides functionality to check consistency across documentation files.
It supports:
- Terminology consistency checking
- Format validation (headings, code blocks, etc.)
- Cross-reference validation
- Style guide compliance
- Duplicate content detection
"""
module ContentConsistency

using TOML
using Markdown

export check_terminology_consistency, check_format_consistency, 
       check_cross_references, ConsistencyResult, validate_content_consistency

"""
    ConsistencyResult

Result of a consistency check.

# Fields
- `check_type::Symbol`: Type of check (:terminology, :format, :cross_reference)
- `file::String`: File where issue was found
- `line::Int`: Line number of the issue
- `issue::String`: Description of the consistency issue
- `severity::Symbol`: :error, :warning, or :info
- `suggestion::Union{String, Nothing}`: Suggested fix
"""
struct ConsistencyResult
    check_type::Symbol
    file::String
    line::Int
    issue::String
    severity::Symbol
    suggestion::Union{String, Nothing}
end

"""
    load_terminology_rules(config::Dict) -> Dict{String, Vector{String}}

Load terminology rules from configuration.
Returns a dictionary mapping preferred terms to lists of discouraged alternatives.
"""
function load_terminology_rules(config::Dict)
    consistency_config = get(config, "content_consistency", Dict())
    terminology_config = get(consistency_config, "terminology", Dict())
    
    # Default terminology rules
    default_rules = Dict(
        "Planar" => ["planar", "PLANAR"],
        "Julia" => ["julia", "JULIA"],
        "CCXT" => ["ccxt", "Ccxt"],
        "API" => ["api", "Api"],
        "OHLCV" => ["ohlcv", "Ohlcv"],
        "JSON" => ["json", "Json"],
        "HTTP" => ["http", "Http"],
        "URL" => ["url", "Url"],
        "CSV" => ["csv", "Csv"],
        "DataFrame" => ["dataframe", "Dataframe", "data frame"],
        "backtesting" => ["back-testing", "back testing"],
        "live trading" => ["livetrading", "live-trading"],
        "paper trading" => ["papertrading", "paper-trading"]
    )
    
    # Merge with user-defined rules
    user_rules = get(terminology_config, "rules", Dict())
    return merge(default_rules, user_rules)
end

"""
    check_terminology_consistency(file_path::String, config::Dict) -> Vector{ConsistencyResult}

Check terminology consistency in a single file.
"""
function check_terminology_consistency(file_path::String, config::Dict)
    if !isfile(file_path)
        return ConsistencyResult[]
    end
    
    content = read(file_path, String)
    lines = split(content, '\n')
    results = ConsistencyResult[]
    
    terminology_rules = load_terminology_rules(config)
    
    for (line_num, line) in enumerate(lines)
        # Skip code blocks (basic detection)
        if startswith(strip(line), "```") || startswith(strip(line), "    ")
            continue
        end
        
        for (preferred_term, discouraged_terms) in terminology_rules
            for discouraged in discouraged_terms
                # Use word boundaries to avoid partial matches
                # Escape special regex characters in the discouraged term
                escaped_term = replace(discouraged, r"[.*+?^${}()|[\]\\]" => s"\\\0")
                pattern = Regex("\\b" * escaped_term * "\\b")
                if occursin(pattern, line)
                    issue = "Use '$preferred_term' instead of '$discouraged'"
                    suggestion = replace(line, pattern => preferred_term)
                    
                    result = ConsistencyResult(
                        :terminology, file_path, line_num, issue, :warning, suggestion
                    )
                    push!(results, result)
                end
            end
        end
    end
    
    return results
end

"""
    check_format_consistency(file_path::String, config::Dict) -> Vector{ConsistencyResult}

Check format consistency in a single file.
"""
function check_format_consistency(file_path::String, config::Dict)
    if !isfile(file_path)
        return ConsistencyResult[]
    end
    
    content = read(file_path, String)
    lines = split(content, '\n')
    results = ConsistencyResult[]
    
    consistency_config = get(config, "content_consistency", Dict())
    format_config = get(consistency_config, "format", Dict())
    
    # Check heading consistency
    check_headings = get(format_config, "check_headings", true)
    if check_headings
        heading_results = check_heading_format(lines, file_path)
        append!(results, heading_results)
    end
    
    # Check code block consistency
    check_code_blocks = get(format_config, "check_code_blocks", true)
    if check_code_blocks
        code_block_results = check_code_block_format(lines, file_path)
        append!(results, code_block_results)
    end
    
    # Check list formatting
    check_lists = get(format_config, "check_lists", true)
    if check_lists
        list_results = check_list_format(lines, file_path)
        append!(results, list_results)
    end
    
    return results
end

"""
    check_heading_format(lines::Vector{String}, file_path::String) -> Vector{ConsistencyResult}

Check heading format consistency.
"""
function check_heading_format(lines::Vector{String}, file_path::String)
    results = ConsistencyResult[]
    
    for (line_num, line) in enumerate(lines)
        stripped = strip(line)
        
        # Check for ATX-style headings (# ## ###)
        if startswith(stripped, "#")
            # Check for space after #
            if !occursin(r"^#+\s", stripped)
                issue = "Heading should have space after #"
                suggestion = replace(stripped, r"^(#+)" => s"\1 ")
                result = ConsistencyResult(
                    :format, file_path, line_num, issue, :warning, suggestion
                )
                push!(results, result)
            end
            
            # Check for trailing #
            if endswith(stripped, "#") && !endswith(stripped, " #")
                issue = "Avoid trailing # in headings"
                suggestion = replace(stripped, r"\s*#+\s*$" => "")
                result = ConsistencyResult(
                    :format, file_path, line_num, issue, :info, suggestion
                )
                push!(results, result)
            end
        end
        
        # Check for setext-style headings (underlined with = or -)
        if line_num < length(lines)
            next_line = strip(lines[line_num + 1])
            if !isempty(next_line) && all(c -> c == '=' || c == '-', next_line)
                issue = "Consider using ATX-style headings (# ##) for consistency"
                level = all(c -> c == '=', next_line) ? 1 : 2
                suggestion = "#"^level * " " * stripped
                result = ConsistencyResult(
                    :format, file_path, line_num, issue, :info, suggestion
                )
                push!(results, result)
            end
        end
    end
    
    return results
end

"""
    check_code_block_format(lines::Vector{String}, file_path::String) -> Vector{ConsistencyResult}

Check code block format consistency.
"""
function check_code_block_format(lines::Vector{String}, file_path::String)
    results = ConsistencyResult[]
    in_code_block = false
    code_block_start = 0
    
    for (line_num, line) in enumerate(lines)
        stripped = strip(line)
        
        # Check for code block delimiters
        if startswith(stripped, "```")
            if !in_code_block
                # Starting a code block
                in_code_block = true
                code_block_start = line_num
                
                # Check for language specification
                if stripped == "```"
                    issue = "Code block should specify language (e.g., ```julia)"
                    suggestion = "```julia"
                    result = ConsistencyResult(
                        :format, file_path, line_num, issue, :info, suggestion
                    )
                    push!(results, result)
                end
            else
                # Ending a code block
                in_code_block = false
                
                # Check for proper closing
                if stripped != "```"
                    issue = "Code block should end with just ```"
                    suggestion = "```"
                    result = ConsistencyResult(
                        :format, file_path, line_num, issue, :warning, suggestion
                    )
                    push!(results, result)
                end
            end
        end
        
        # Check for indented code blocks (4 spaces)
        if !in_code_block && startswith(line, "    ") && !isempty(stripped)
            issue = "Consider using fenced code blocks (```) instead of indented code blocks"
            result = ConsistencyResult(
                :format, file_path, line_num, issue, :info, nothing
            )
            push!(results, result)
        end
    end
    
    # Check for unclosed code blocks
    if in_code_block
        issue = "Unclosed code block starting at line $code_block_start"
        result = ConsistencyResult(
            :format, file_path, code_block_start, issue, :error, "Add closing ```"
        )
        push!(results, result)
    end
    
    return results
end

"""
    check_list_format(lines::Vector{String}, file_path::String) -> Vector{ConsistencyResult}

Check list format consistency.
"""
function check_list_format(lines::Vector{String}, file_path::String)
    results = ConsistencyResult[]
    
    for (line_num, line) in enumerate(lines)
        stripped = strip(line)
        
        # Check for inconsistent list markers
        if occursin(r"^\s*[*+-]\s", line)
            # This is a list item, check for consistency
            # For now, we'll just suggest using - for consistency
            if occursin(r"^\s*[*+]\s", line)
                issue = "Consider using '-' for list items for consistency"
                suggestion = replace(line, r"^(\s*)[*+](\s)" => s"\1-\2")
                result = ConsistencyResult(
                    :format, file_path, line_num, issue, :info, suggestion
                )
                push!(results, result)
            end
        end
        
        # Check for numbered list format
        if occursin(r"^\s*\d+\.\s", line)
            # Check for proper spacing
            if !occursin(r"^\s*\d+\.\s+", line)
                issue = "Numbered list items should have space after period"
                suggestion = replace(line, r"^(\s*\d+\.)(\S)" => s"\1 \2")
                result = ConsistencyResult(
                    :format, file_path, line_num, issue, :warning, suggestion
                )
                push!(results, result)
            end
        end
    end
    
    return results
end

"""
    check_cross_references(file_path::String, docs_dir::String, config::Dict) -> Vector{ConsistencyResult}

Check cross-reference consistency in a single file.
"""
function check_cross_references(file_path::String, docs_dir::String, config::Dict)
    if !isfile(file_path)
        return ConsistencyResult[]
    end
    
    content = read(file_path, String)
    lines = split(content, '\n')
    results = ConsistencyResult[]
    
    # Check for broken internal references
    for (line_num, line) in enumerate(lines)
        # Look for reference-style links [text][ref]
        for m in eachmatch(r"\[([^\]]+)\]\[([^\]]+)\]", line)
            ref_id = m.captures[2]
            
            # Check if reference is defined in the file
            ref_pattern = Regex("^\\s*\\[$ref_id\\]:\\s*")
            ref_found = any(l -> occursin(ref_pattern, l), lines)
            
            if !ref_found
                issue = "Undefined reference: [$ref_id]"
                result = ConsistencyResult(
                    :cross_reference, file_path, line_num, issue, :error, nothing
                )
                push!(results, result)
            end
        end
    end
    
    return results
end

"""
    validate_content_consistency(docs_dir::String; config::Dict=Dict()) -> Vector{ConsistencyResult}

Validate content consistency across all documentation files.
"""
function validate_content_consistency(docs_dir::String; config::Dict=Dict())
    all_results = ConsistencyResult[]
    
    # Find all markdown files
    md_files = String[]
    for (root, dirs, files) in walkdir(docs_dir)
        for file in files
            if endswith(file, ".md")
                push!(md_files, joinpath(root, file))
            end
        end
    end
    
    @info "Checking content consistency in $(length(md_files)) files"
    
    for file_path in md_files
        @debug "Checking consistency in $file_path"
        
        # Run all consistency checks
        terminology_results = check_terminology_consistency(file_path, config)
        format_results = check_format_consistency(file_path, config)
        cross_ref_results = check_cross_references(file_path, docs_dir, config)
        
        append!(all_results, terminology_results)
        append!(all_results, format_results)
        append!(all_results, cross_ref_results)
    end
    
    return all_results
end

end # module ContentConsistency