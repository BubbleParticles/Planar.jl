"""
Link Validation Module

This module provides functionality to validate internal and external links
in documentation files. It supports:
- Internal link validation (relative paths, anchors)
- External link validation with HTTP requests
- Broken link detection and reporting
- Configuration-based link checking rules
- Batch processing for performance
"""
module LinkValidator

using HTTP
using URIs
using Markdown
using TOML

export validate_links_in_file, validate_all_links, LinkValidationResult,
       extract_links, check_internal_link, check_external_link

"""
    LinkValidationResult

Result of validating a link.

# Fields
- `url::String`: The URL that was validated
- `valid::Bool`: Whether the link is valid
- `status_code::Union{Int, Nothing}`: HTTP status code (for external links)
- `error::Union{String, Nothing}`: Error message if validation failed
- `link_type::Symbol`: :internal or :external
- `source_file::String`: File containing the link
- `line_number::Int`: Line number where link appears
"""
struct LinkValidationResult
    url::String
    valid::Bool
    status_code::Union{Int, Nothing}
    error::Union{String, Nothing}
    link_type::Symbol
    source_file::String
    line_number::Int
end

"""
    extract_links(content::String, file_path::String) -> Vector{Tuple{String, Int}}

Extract all links from markdown content.
Returns tuples of (url, line_number).
"""
function extract_links(content::String, file_path::String)
    links = Tuple{String, Int}[]
    lines = split(content, '\n')
    
    for (line_num, line) in enumerate(lines)
        # Match markdown links [text](url)
        for m in eachmatch(r"\[([^\]]*)\]\(([^)]+)\)", line)
            url = m.captures[2]
            # Skip nested links or Documenter references that don't represent actual URLs
            if occursin('[', url) || occursin(']', url) || startswith(url, "@ref")
                continue
            end
            push!(links, (url, line_num))
        end
        
        # Match reference-style links [text][ref] and [ref]: url
        for m in eachmatch(r"\[([^\]]+)\]:\s*(.+)", line)
            url = strip(m.captures[2])
            push!(links, (url, line_num))
        end
        
        # Match HTML links <a href="url">
        for m in eachmatch(r"<a\s+[^>]*href\s*=\s*[\"']([^\"']+)[\"']", line)
            url = m.captures[1]
            push!(links, (url, line_num))
        end
        
        # Match bare URLs (http/https)
        for m in eachmatch(r"https?://[^\s\)]+", line)
            url = m.match
            push!(links, (url, line_num))
        end
    end
    
    return links
end

"""
    check_internal_link(url::String, source_file::String, docs_root::String) -> LinkValidationResult

Check if an internal link (relative path or anchor) is valid.
"""
function check_internal_link(url::String, source_file::String, docs_root::String, line_number::Int)
    # Handle anchors within the same file
    if startswith(url, "#")
        # For now, we'll assume anchor links are valid
        # A more sophisticated implementation would parse the file for headers
        return LinkValidationResult(url, true, nothing, nothing, :internal, source_file, line_number)
    end
    
    # Handle relative paths
    if !startswith(url, "http") && !startswith(url, "mailto:")
        # Remove anchor part if present
        path_part = split(url, '#')[1]
        
        # Resolve relative path
        source_dir = dirname(source_file)
        target_path = normpath(joinpath(source_dir, path_part))
        
        # Check if file exists
        if isfile(target_path) || isdir(target_path)
            return LinkValidationResult(url, true, nothing, nothing, :internal, source_file, line_number)
        else
            # Try relative to docs root
            target_path_from_root = normpath(joinpath(docs_root, path_part))
            if isfile(target_path_from_root) || isdir(target_path_from_root)
                return LinkValidationResult(url, true, nothing, nothing, :internal, source_file, line_number)
            else
                error_msg = "File not found: $target_path"
                return LinkValidationResult(url, false, nothing, error_msg, :internal, source_file, line_number)
            end
        end
    end
    
    # If we get here, it's not an internal link
    return LinkValidationResult(url, false, nothing, "Not an internal link", :internal, source_file, line_number)
end

"""
    check_external_link(url::String, source_file::String, line_number::Int; timeout::Int=10) -> LinkValidationResult

Check if an external link is accessible via HTTP request.
"""
function check_external_link(url::String, source_file::String, line_number::Int; timeout::Int=10)
    # Skip mailto links
    if startswith(url, "mailto:")
        return LinkValidationResult(url, true, nothing, nothing, :external, source_file, line_number)
    end
    
    # Skip non-HTTP links
    if !startswith(url, "http")
        return LinkValidationResult(url, false, nothing, "Not an HTTP URL", :external, source_file, line_number)
    end
    
    try
        # Make HEAD request to check if URL is accessible
        response = HTTP.head(url; timeout=timeout, redirect=true)
        status_code = response.status
        
        # Consider 2xx and 3xx status codes as valid
        valid = 200 <= status_code < 400
        error_msg = valid ? nothing : "HTTP $status_code"
        
        return LinkValidationResult(url, valid, status_code, error_msg, :external, source_file, line_number)
        
    catch e
        error_msg = string(e)
        return LinkValidationResult(url, false, nothing, error_msg, :external, source_file, line_number)
    end
end

"""
    validate_links_in_file(file_path::String, docs_root::String; config::Dict=Dict()) -> Vector{LinkValidationResult}

Validate all links in a single documentation file.
"""
function validate_links_in_file(file_path::String, docs_root::String; config::Dict=Dict())
    if !isfile(file_path)
        return LinkValidationResult[]
    end
    
    content = read(file_path, String)
    links = extract_links(content, file_path)
    results = LinkValidationResult[]
    
    # Get configuration
    link_config = get(config, "link_validation", Dict())
    check_external = get(link_config, "check_external", true)
    external_timeout = get(link_config, "external_timeout", 10)
    skip_patterns = get(link_config, "skip_patterns", String[])
    
    for (url, line_number) in links
        # Skip URLs matching skip patterns
        skip_url = false
        for pattern in skip_patterns
            if occursin(pattern, url)
                skip_url = true
                break
            end
        end
        
        if skip_url
            continue
        end
        
        # Determine if it's internal or external and validate accordingly
        if startswith(url, "http") || startswith(url, "mailto:")
            if check_external
                result = check_external_link(url, file_path, line_number; timeout=external_timeout)
                push!(results, result)
            end
        else
            result = check_internal_link(url, file_path, docs_root, line_number)
            push!(results, result)
        end
    end
    
    return results
end

"""
    validate_all_links(docs_dir::String; config::Dict=Dict()) -> Vector{LinkValidationResult}

Validate links in all documentation files in the specified directory.
"""
function validate_all_links(docs_dir::String; config::Dict=Dict())
    all_results = LinkValidationResult[]
    
    # Find all markdown files
    md_files = String[]
    for (root, dirs, files) in walkdir(docs_dir)
        for file in files
            if endswith(file, ".md")
                push!(md_files, joinpath(root, file))
            end
        end
    end
    
    @info "Validating links in $(length(md_files)) files"
    
    for file_path in md_files
        @debug "Validating links in $file_path"
        results = validate_links_in_file(file_path, docs_dir; config=config)
        append!(all_results, results)
    end
    
    return all_results
end

end # module LinkValidator