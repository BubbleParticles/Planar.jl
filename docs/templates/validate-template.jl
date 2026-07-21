#!/usr/bin/env julia

"""
Template Validation System

This script validates that documentation files follow the established templates
and contain required frontmatter metadata.
"""

using YAML

# Required frontmatter fields for each category
const REQUIRED_FIELDS = Dict(
    "getting-started" => ["title", "description", "category", "difficulty", "estimated_time"],
    "guides" => ["title", "description", "category", "difficulty", "prerequisites", "estimated_time"],
    "advanced" => ["title", "description", "category", "difficulty", "prerequisites", "estimated_time"],
    "reference" => ["title", "description", "category", "estimated_time"],
    "troubleshooting" => ["title", "description", "category", "difficulty", "estimated_time"],
    "resources" => ["title", "description", "category"]
)

const VALID_CATEGORIES = ["getting-started", "guides", "advanced", "reference", "troubleshooting", "resources"]
const VALID_DIFFICULTIES = ["beginner", "intermediate", "advanced"]

"""
    validate_frontmatter(filepath::String) -> Bool

Validate that a markdown file has proper frontmatter metadata.
"""
function validate_frontmatter(filepath::String)
    content = read(filepath, String)
    
    # Check if file has frontmatter
    if !startswith(content, "---\n")
        @warn "File missing frontmatter: $filepath"
        return false
    end
    
    # Extract frontmatter
    parts = split(content, "---\n", limit=3)
    if length(parts) < 3
        @warn "Invalid frontmatter format: $filepath"
        return false
    end
    
    try
        frontmatter = YAML.load(parts[2])
        
        # Validate category
        category = get(frontmatter, "category", "")
        if category ∉ VALID_CATEGORIES
            @warn "Invalid category '$category' in $filepath"
            return false
        end
        
        # Check required fields
        required = REQUIRED_FIELDS[category]
        for field in required
            if !haskey(frontmatter, field) || isempty(string(frontmatter[field]))
                @warn "Missing required field '$field' in $filepath"
                return false
            end
        end
        
        # Validate difficulty if present
        if haskey(frontmatter, "difficulty")
            difficulty = frontmatter["difficulty"]
            if difficulty ∉ VALID_DIFFICULTIES
                @warn "Invalid difficulty '$difficulty' in $filepath"
                return false
            end
        end
        
        # Validate estimated_time format
        if haskey(frontmatter, "estimated_time")
            time_str = frontmatter["estimated_time"]
            if !occursin(r"^\d+\s+(minutes?|hours?)$", time_str)
                @warn "Invalid estimated_time format '$time_str' in $filepath (should be 'X minutes' or 'X hours')"
                return false
            end
        end
        
        return true
        
    catch e
        @warn "Error parsing frontmatter in $filepath: $e"
        return false
    end
end

"""
    validate_content_structure(filepath::String, category::String) -> Bool

Validate that content follows the expected structure for its category.
"""
function validate_content_structure(filepath::String, category::String)
    content = read(filepath, String)
    
    # Basic structure checks based on category
    if category == "getting-started"
        required_sections = ["Prerequisites", "What You'll Learn", "Next Steps"]
    elseif category == "guides"
        required_sections = ["Overview", "Prerequisites", "See Also"]
    elseif category == "reference"
        required_sections = ["Syntax", "Parameters", "Examples"]
    elseif category == "troubleshooting"
        required_sections = ["Symptoms", "Solution"]
    else
        return true  # No specific structure requirements for other categories
    end
    
    missing_sections = []
    for section in required_sections
        if !occursin("## $section", content) && !occursin("### $section", content)
            push!(missing_sections, section)
        end
    end
    
    if !isempty(missing_sections)
        @warn "Missing required sections in $filepath: $(join(missing_sections, ", "))"
        return false
    end
    
    return true
end

"""
    validate_file(filepath::String) -> Bool

Validate a single documentation file.
"""
function validate_file(filepath::String)
    if !endswith(filepath, ".md")
        return true  # Skip non-markdown files
    end
    
    if !isfile(filepath)
        @warn "File not found: $filepath"
        return false
    end
    
    println("Validating: $filepath")
    
    # Validate frontmatter
    frontmatter_valid = validate_frontmatter(filepath)
    
    # Get category for structure validation
    content = read(filepath, String)
    if startswith(content, "---\n")
        parts = split(content, "---\n", limit=3)
        if length(parts) >= 3
            try
                frontmatter = YAML.load(parts[2])
                category = get(frontmatter, "category", "")
                structure_valid = validate_content_structure(filepath, category)
                return frontmatter_valid && structure_valid
            catch
                return false
            end
        end
    end
    
    return frontmatter_valid
end

"""
    validate_directory(dir::String) -> Bool

Validate all markdown files in a directory recursively.
"""
function validate_directory(dir::String)
    all_valid = true
    
    for (root, dirs, files) in walkdir(dir)
        for file in files
            if endswith(file, ".md")
                filepath = joinpath(root, file)
                if !validate_file(filepath)
                    all_valid = false
                end
            end
        end
    end
    
    return all_valid
end

# Main execution
if abspath(PROGRAM_FILE) == @__FILE__
    if length(ARGS) == 0
        println("Usage: julia validate-template.jl <file_or_directory>")
        exit(1)
    end
    
    target = ARGS[1]
    
    if isfile(target)
        success = validate_file(target)
    elseif isdir(target)
        success = validate_directory(target)
    else
        @error "Target not found: $target"
        exit(1)
    end
    
    if success
        println("✅ All validations passed!")
        exit(0)
    else
        println("❌ Validation failed!")
        exit(1)
    end
end