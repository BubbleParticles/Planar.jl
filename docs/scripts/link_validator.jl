#!/usr/bin/env julia

"""
Automated Link Validation System for Planar Documentation

This script validates all internal and external links in the documentation,
generates reports, and provides a monitoring dashboard for link health.
"""

using Pkg
Pkg.activate(".")

using HTTP
using Markdown
using JSON3
using Dates
using Base.Filesystem

# Configuration
const DOCS_ROOT = joinpath(@__DIR__, "..", "src")
const REPORT_DIR = joinpath(@__DIR__, "..", "reports")
const CACHE_FILE = joinpath(REPORT_DIR, "link_cache.json")
const REPORT_FILE = joinpath(REPORT_DIR, "link_validation_report.json")
const HTML_REPORT = joinpath(REPORT_DIR, "link_health_dashboard.html")

# Link validation results structure
struct LinkResult
    url::String
    status::String  # "valid", "broken", "timeout", "error"
    status_code::Union{Int, Nothing}
    error_message::Union{String, Nothing}
    last_checked::DateTime
    response_time::Union{Float64, Nothing}
end

struct FileResult
    file_path::String
    links::Vector{LinkResult}
    internal_links::Vector{String}
    external_links::Vector{String}
    broken_links::Vector{String}
    last_checked::DateTime
end

struct ValidationReport
    timestamp::DateTime
    total_files::Int
    total_links::Int
    broken_links::Int
    external_links::Int
    internal_links::Int
    files::Vector{FileResult}
    summary::Dict{String, Any}
end

# Utility functions
function ensure_report_dir()
    if !isdir(REPORT_DIR)
        mkpath(REPORT_DIR)
    end
end

function load_cache()::Dict{String, LinkResult}
    if isfile(CACHE_FILE)
        try
            cache_data = JSON3.read(read(CACHE_FILE, String))
            return Dict(
                url => LinkResult(
                    url,
                    result.status,
                    result.status_code,
                    result.error_message,
                    DateTime(result.last_checked),
                    result.response_time
                ) for (url, result) in cache_data
            )
        catch e
            @warn "Failed to load cache: $e"
            return Dict{String, LinkResult}()
        end
    end
    return Dict{String, LinkResult}()
end

function save_cache(cache::Dict{String, LinkResult})
    ensure_report_dir()
    cache_json = Dict(
        url => Dict(
            "url" => result.url,
            "status" => result.status,
            "status_code" => result.status_code,
            "error_message" => result.error_message,
            "last_checked" => string(result.last_checked),
            "response_time" => result.response_time
        ) for (url, result) in cache
    )
    write(CACHE_FILE, JSON3.write(cache_json))
end

function extract_links_from_markdown(content::String)::Tuple{Vector{String}, Vector{String}}
    internal_links = String[]
    external_links = String[]
    
    # Parse markdown content
    md = Markdown.parse(content)
    
    # Extract links using regex patterns
    # Markdown links: [text](url)
    link_pattern = r"\[([^\]]*)\]\(([^)]+)\)"
    for match in eachmatch(link_pattern, content)
        url = match.captures[2]
        if startswith(url, "http://") || startswith(url, "https://")
            push!(external_links, url)
        elseif !startswith(url, "#")  # Skip anchors
            push!(internal_links, url)
        end
    end
    
    # HTML links: <a href="url">
    html_link_pattern = r"<a\s+[^>]*href\s*=\s*[\"']([^\"']+)[\"'][^>]*>"i
    for match in eachmatch(html_link_pattern, content)
        url = match.captures[1]
        if startswith(url, "http://") || startswith(url, "https://")
            push!(external_links, url)
        elseif !startswith(url, "#")
            push!(internal_links, url)
        end
    end
    
    return (unique(internal_links), unique(external_links))
end

function validate_internal_link(link::String, base_file::String)::LinkResult
    # Convert relative path to absolute
    if startswith(link, "/")
        # Absolute path from docs root
        full_path = joinpath(DOCS_ROOT, link[2:end])
    else
        # Relative path from current file
        base_dir = dirname(base_file)
        full_path = normpath(joinpath(base_dir, link))
    end
    
    # Add .md extension if not present and not a directory
    if !endswith(full_path, ".md") && !isdir(full_path)
        full_path = full_path * ".md"
    end
    
    if isfile(full_path) || isdir(full_path)
        return LinkResult(link, "valid", 200, nothing, now(), 0.0)
    else
        return LinkResult(link, "broken", 404, "File not found: $full_path", now(), nothing)
    end
end

function validate_external_link(url::String, cache::Dict{String, LinkResult})::LinkResult
    # Check cache first (cache for 1 hour)
    if haskey(cache, url)
        cached = cache[url]
        if now() - cached.last_checked < Hour(1)
            return cached
        end
    end
    
    try
        start_time = time()
        response = HTTP.get(url; timeout=10, retry=false)
        response_time = time() - start_time
        
        result = LinkResult(url, "valid", response.status, nothing, now(), response_time)
        cache[url] = result
        return result
    catch e
        error_msg = string(e)
        status = if isa(e, HTTP.TimeoutError)
            "timeout"
        elseif isa(e, HTTP.StatusError)
            "broken"
        else
            "error"
        end
        
        status_code = if isa(e, HTTP.StatusError)
            e.status
        else
            nothing
        end
        
        result = LinkResult(url, status, status_code, error_msg, now(), nothing)
        cache[url] = result
        return result
    end
end

function validate_file_links(file_path::String, cache::Dict{String, LinkResult})::FileResult
    println("Validating links in: $file_path")
    
    content = read(file_path, String)
    internal_links, external_links = extract_links_from_markdown(content)
    
    all_results = LinkResult[]
    broken_links = String[]
    
    # Validate internal links
    for link in internal_links
        result = validate_internal_link(link, file_path)
        push!(all_results, result)
        if result.status == "broken"
            push!(broken_links, link)
        end
    end
    
    # Validate external links
    for link in external_links
        result = validate_external_link(link, cache)
        push!(all_results, result)
        if result.status in ["broken", "timeout", "error"]
            push!(broken_links, link)
        end
    end
    
    return FileResult(
        file_path,
        all_results,
        internal_links,
        external_links,
        broken_links,
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

function generate_validation_report()::ValidationReport
    ensure_report_dir()
    cache = load_cache()
    
    markdown_files = find_markdown_files(DOCS_ROOT)
    file_results = FileResult[]
    
    total_links = 0
    broken_links = 0
    external_links = 0
    internal_links = 0
    
    for file_path in markdown_files
        result = validate_file_links(file_path, cache)
        push!(file_results, result)
        
        total_links += length(result.links)
        broken_links += length(result.broken_links)
        external_links += length(result.external_links)
        internal_links += length(result.internal_links)
    end
    
    # Save updated cache
    save_cache(cache)
    
    summary = Dict(
        "health_score" => total_links > 0 ? round((total_links - broken_links) / total_links * 100, digits=2) : 100.0,
        "broken_percentage" => total_links > 0 ? round(broken_links / total_links * 100, digits=2) : 0.0,
        "external_percentage" => total_links > 0 ? round(external_links / total_links * 100, digits=2) : 0.0,
        "files_with_broken_links" => count(f -> !isempty(f.broken_links), file_results)
    )
    
    return ValidationReport(
        now(),
        length(markdown_files),
        total_links,
        broken_links,
        external_links,
        internal_links,
        file_results,
        summary
    )
end

function save_json_report(report::ValidationReport)
    ensure_report_dir()
    
    report_data = Dict(
        "timestamp" => string(report.timestamp),
        "total_files" => report.total_files,
        "total_links" => report.total_links,
        "broken_links" => report.broken_links,
        "external_links" => report.external_links,
        "internal_links" => report.internal_links,
        "summary" => report.summary,
        "files" => [
            Dict(
                "file_path" => f.file_path,
                "internal_links" => f.internal_links,
                "external_links" => f.external_links,
                "broken_links" => f.broken_links,
                "last_checked" => string(f.last_checked),
                "links" => [
                    Dict(
                        "url" => l.url,
                        "status" => l.status,
                        "status_code" => l.status_code,
                        "error_message" => l.error_message,
                        "response_time" => l.response_time
                    ) for l in f.links
                ]
            ) for f in report.files
        ]
    )
    
    write(REPORT_FILE, JSON3.write(report_data))
    println("JSON report saved to: $REPORT_FILE")
end

function generate_html_dashboard(report::ValidationReport)
    ensure_report_dir()
    
    html_content = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Planar Documentation Link Health Dashboard</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
            .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
            .header { text-align: center; margin-bottom: 30px; }
            .stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin-bottom: 30px; }
            .stat-card { background: #f8f9fa; padding: 20px; border-radius: 8px; text-align: center; }
            .stat-number { font-size: 2em; font-weight: bold; color: #007bff; }
            .stat-label { color: #666; margin-top: 5px; }
            .health-score { font-size: 3em; font-weight: bold; }
            .health-good { color: #28a745; }
            .health-warning { color: #ffc107; }
            .health-danger { color: #dc3545; }
            .file-list { margin-top: 30px; }
            .file-item { margin-bottom: 20px; padding: 15px; border: 1px solid #ddd; border-radius: 5px; }
            .file-header { font-weight: bold; margin-bottom: 10px; }
            .link-list { margin-left: 20px; }
            .link-item { margin: 5px 0; }
            .link-valid { color: #28a745; }
            .link-broken { color: #dc3545; }
            .link-timeout { color: #ffc107; }
            .link-error { color: #6c757d; }
            .timestamp { text-align: center; color: #666; margin-top: 30px; }
            .filter-buttons { margin-bottom: 20px; text-align: center; }
            .filter-btn { padding: 8px 16px; margin: 0 5px; border: 1px solid #007bff; background: white; color: #007bff; cursor: pointer; border-radius: 4px; }
            .filter-btn.active { background: #007bff; color: white; }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <h1>📊 Planar Documentation Link Health Dashboard</h1>
                <p>Automated link validation report generated on $(report.timestamp)</p>
            </div>
            
            <div class="stats">
                <div class="stat-card">
                    <div class="stat-number health-score $(report.summary["health_score"] >= 95 ? "health-good" : report.summary["health_score"] >= 85 ? "health-warning" : "health-danger")">
                        $(report.summary["health_score"])%
                    </div>
                    <div class="stat-label">Overall Health Score</div>
                </div>
                <div class="stat-card">
                    <div class="stat-number">$(report.total_files)</div>
                    <div class="stat-label">Total Files</div>
                </div>
                <div class="stat-card">
                    <div class="stat-number">$(report.total_links)</div>
                    <div class="stat-label">Total Links</div>
                </div>
                <div class="stat-card">
                    <div class="stat-number $(report.broken_links > 0 ? "health-danger" : "health-good")">$(report.broken_links)</div>
                    <div class="stat-label">Broken Links</div>
                </div>
                <div class="stat-card">
                    <div class="stat-number">$(report.external_links)</div>
                    <div class="stat-label">External Links</div>
                </div>
                <div class="stat-card">
                    <div class="stat-number">$(report.internal_links)</div>
                    <div class="stat-label">Internal Links</div>
                </div>
            </div>
            
            <div class="filter-buttons">
                <button class="filter-btn active" onclick="filterFiles('all')">All Files</button>
                <button class="filter-btn" onclick="filterFiles('broken')">Files with Broken Links</button>
                <button class="filter-btn" onclick="filterFiles('clean')">Clean Files</button>
            </div>
            
            <div class="file-list" id="fileList">
    """
    
    for file_result in report.files
        relative_path = replace(file_result.file_path, DOCS_ROOT => "docs/src")
        has_broken = !isempty(file_result.broken_links)
        
        html_content *= """
                <div class="file-item" data-status="$(has_broken ? "broken" : "clean")">
                    <div class="file-header">📄 $relative_path</div>
                    <div>Internal Links: $(length(file_result.internal_links)) | External Links: $(length(file_result.external_links)) | Broken: $(length(file_result.broken_links))</div>
        """
        
        if !isempty(file_result.broken_links)
            html_content *= """
                    <div class="link-list">
                        <strong>🚨 Broken Links:</strong>
            """
            for broken_link in file_result.broken_links
                html_content *= """<div class="link-item link-broken">❌ $broken_link</div>"""
            end
            html_content *= "</div>"
        end
        
        html_content *= "</div>"
    end
    
    html_content *= """
            </div>
            
            <div class="timestamp">
                Last updated: $(report.timestamp)
            </div>
        </div>
        
        <script>
            function filterFiles(type) {
                const buttons = document.querySelectorAll('.filter-btn');
                const files = document.querySelectorAll('.file-item');
                
                buttons.forEach(btn => btn.classList.remove('active'));
                event.target.classList.add('active');
                
                files.forEach(file => {
                    const status = file.getAttribute('data-status');
                    if (type === 'all' || 
                        (type === 'broken' && status === 'broken') ||
                        (type === 'clean' && status === 'clean')) {
                        file.style.display = 'block';
                    } else {
                        file.style.display = 'none';
                    }
                });
            }
        </script>
    </body>
    </html>
    """
    
    write(HTML_REPORT, html_content)
    println("HTML dashboard saved to: $HTML_REPORT")
end

# Main execution
function main()
    println("🔍 Starting link validation for Planar documentation...")
    
    report = generate_validation_report()
    
    println("\n📊 Validation Summary:")
    println("  Total files: $(report.total_files)")
    println("  Total links: $(report.total_links)")
    println("  Broken links: $(report.broken_links)")
    println("  Health score: $(report.summary["health_score"])%")
    
    save_json_report(report)
    generate_html_dashboard(report)
    
    if report.broken_links > 0
        println("\n⚠️  Found $(report.broken_links) broken links!")
        println("Check the dashboard at: $HTML_REPORT")
        exit(1)
    else
        println("\n✅ All links are healthy!")
        exit(0)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end