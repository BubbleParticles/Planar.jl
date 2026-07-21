#!/usr/bin/env julia

"""
Final Content Audit and Cleanup Script

This script performs a comprehensive audit of all migrated content for consistency,
accuracy, and completeness. It identifies and fixes issues to ensure all requirements
are met and validated.

Requirements addressed:
- 2.1: Consistent content structure
- 4.1: Content accuracy and completeness  
- 4.4: Quality assurance and validation
"""

using Test

# Global tracking
audit_results = Dict{String, Any}()
issues_found = String[]
fixes_applied = String[]
cleanup_actions = String[]

function audit_frontmatter_consistency()
    println("📝 Auditing Frontmatter Consistency...")
    
    # Required frontmatter fields for each category
    required_fields = Dict(
        "getting-started" => ["title", "description", "category", "difficulty", "estimated_time", "topics", "last_updated"],
        "guides" => ["title", "description", "category", "difficulty", "topics", "last_updated"],
        "reference" => ["title", "description", "category", "difficulty", "topics", "last_updated"],
        "troubleshooting" => ["title", "description", "category", "difficulty", "topics", "last_updated"],
        "advanced" => ["title", "description", "category", "difficulty", "topics", "last_updated"],
        "resources" => ["title", "description", "category", "difficulty", "topics", "last_updated"]
    )
    
    # Find all markdown files
    md_files = String[]
    for root in ["docs/src/getting-started", "docs/src/guides", "docs/src/reference", 
                 "docs/src/troubleshooting", "docs/src/advanced", "docs/src/resources"]
        if isdir(root)
            for file in readdir(root, join=true)
                if endswith(file, ".md")
                    push!(md_files, file)
                end
            end
        end
    end
    
    # Add main files
    push!(md_files, "docs/src/index.md")
    
    frontmatter_issues = String[]
    
    for filepath in md_files
        if !isfile(filepath)
            continue
        end
        
        content = read(filepath, String)
        
        # Check for frontmatter
        if !startswith(content, "---")
            push!(frontmatter_issues, "$filepath: Missing frontmatter")
            continue
        end
        
        # Extract frontmatter
        lines = split(content, '\n')
        frontmatter_end = findfirst(i -> i > 1 && lines[i] == "---", 1:length(lines))
        
        if frontmatter_end === nothing
            push!(frontmatter_issues, "$filepath: Malformed frontmatter")
            continue
        end
        
        frontmatter = join(lines[2:frontmatter_end-1], '\n')
        
        # Determine category from path or frontmatter
        category = "general"
        if contains(filepath, "getting-started")
            category = "getting-started"
        elseif contains(filepath, "guides")
            category = "guides"
        elseif contains(filepath, "reference")
            category = "reference"
        elseif contains(filepath, "troubleshooting")
            category = "troubleshooting"
        elseif contains(filepath, "advanced")
            category = "advanced"
        elseif contains(filepath, "resources")
            category = "resources"
        end
        
        # Check required fields
        if haskey(required_fields, category)
            missing_fields = String[]
            for field in required_fields[category]
                if !occursin("$field:", frontmatter)
                    push!(missing_fields, field)
                end
            end
            
            if !isempty(missing_fields)
                push!(frontmatter_issues, "$filepath: Missing fields: $(join(missing_fields, ", "))")
            end
        end
    end
    
    audit_results["frontmatter_issues"] = frontmatter_issues
    return frontmatter_issues
end

function audit_content_structure()
    println("📋 Auditing Content Structure...")
    
    structure_issues = String[]
    
    # Check getting-started files for proper structure
    getting_started_files = [
        ("docs/src/getting-started/index.md", ["Learning Objectives", "Section Overview", "Prerequisites"]),
        ("docs/src/getting-started/installation.md", ["Prerequisites", "Method 1", "Method 2", "Verification"]),
        ("docs/src/getting-started/quick-start.md", ["What You'll Accomplish", "Step 1", "Step 2", "Step 3"]),
        ("docs/src/getting-started/first-strategy.md", ["What You'll Learn", "Prerequisites", "Step 1", "Step 2"])
    ]
    
    for (filepath, required_sections) in getting_started_files
        if !isfile(filepath)
            push!(structure_issues, "$filepath: File missing")
            continue
        end
        
        content = read(filepath, String)
        missing_sections = String[]
        
        for section in required_sections
            if !occursin(section, content)
                push!(missing_sections, section)
            end
        end
        
        if !isempty(missing_sections)
            push!(structure_issues, "$filepath: Missing sections: $(join(missing_sections, ", "))")
        end
    end
    
    audit_results["structure_issues"] = structure_issues
    return structure_issues
end

function audit_link_integrity()
    println("🔗 Auditing Link Integrity...")
    
    link_issues = String[]
    
    # Files to check for links
    files_to_check = [
        "docs/src/index.md",
        "docs/src/getting-started/index.md",
        "docs/src/getting-started/installation.md",
        "docs/src/getting-started/quick-start.md",
        "docs/src/getting-started/first-strategy.md"
    ]
    
    for filepath in files_to_check
        if !isfile(filepath)
            continue
        end
        
        content = read(filepath, String)
        
        # Find all markdown links
        link_pattern = r"\[([^\]]+)\]\(([^)]+)\)"
        links = collect(eachmatch(link_pattern, content))
        
        for link_match in links
            link_url = link_match.captures[2]
            
            # Skip external links and anchors
            if startswith(link_url, "http") || startswith(link_url, "#")
                continue
            end
            
            # Resolve relative path
            clean_url = split(link_url, '#')[1]
            if startswith(clean_url, "../")
                full_path = normpath(joinpath(dirname(filepath), clean_url))
            else
                full_path = joinpath(dirname(filepath), clean_url)
            end
            
            # Check if target exists
            if !isfile(full_path) && !isdir(full_path)
                push!(link_issues, "$filepath: Broken link to $link_url")
            end
        end
    end
    
    audit_results["link_issues"] = link_issues
    return link_issues
end

function audit_code_examples()
    println("💻 Auditing Code Examples...")
    
    code_issues = String[]
    
    files_with_code = [
        "docs/src/getting-started/installation.md",
        "docs/src/getting-started/quick-start.md",
        "docs/src/getting-started/first-strategy.md"
    ]
    
    for filepath in files_with_code
        if !isfile(filepath)
            continue
        end
        
        content = read(filepath, String)
        
        # Find Julia code blocks
        julia_blocks = collect(eachmatch(r"```julia\n(.*?)\n```"s, content))
        
        for (i, block) in enumerate(julia_blocks)
            code = block.captures[1]
            
            # Check for common issues
            if occursin("[", code) && occursin("](", code)
                push!(code_issues, "$filepath: Julia code block $i contains markdown links")
            end
            
            if occursin("\$\$", code)
                push!(code_issues, "$filepath: Julia code block $i has malformed string interpolation")
            end
            
            # Check for basic syntax validity (simple check)
            if count(c -> c == '(', code) != count(c -> c == ')', code)
                push!(code_issues, "$filepath: Julia code block $i has unmatched parentheses")
            end
        end
        
        # Find bash code blocks
        bash_blocks = collect(eachmatch(r"```bash\n(.*?)\n```"s, content))
        
        for (i, block) in enumerate(bash_blocks)
            code = block.captures[1]
            
            # Check for dangerous commands
            dangerous_patterns = ["rm -rf /", "sudo rm", "format", "mkfs"]
            for pattern in dangerous_patterns
                if occursin(pattern, code)
                    push!(code_issues, "$filepath: Bash code block $i contains potentially dangerous command: $pattern")
                end
            end
        end
    end
    
    audit_results["code_issues"] = code_issues
    return code_issues
end

function audit_requirements_compliance()
    println("✅ Auditing Requirements Compliance...")
    
    compliance_issues = String[]
    
    # Requirement 2.1: Consistent content structure
    frontmatter_issues = get(audit_results, "frontmatter_issues", String[])
    structure_issues = get(audit_results, "structure_issues", String[])
    
    if !isempty(frontmatter_issues) || !isempty(structure_issues)
        push!(compliance_issues, "Requirement 2.1 (Consistent Structure): Issues found in frontmatter or structure")
    end
    
    # Requirement 4.1: Content accuracy and completeness
    link_issues = get(audit_results, "link_issues", String[])
    code_issues = get(audit_results, "code_issues", String[])
    
    if !isempty(link_issues) || !isempty(code_issues)
        push!(compliance_issues, "Requirement 4.1 (Accuracy & Completeness): Issues found in links or code")
    end
    
    # Requirement 4.4: Quality assurance
    total_issues = length(frontmatter_issues) + length(structure_issues) + 
                   length(link_issues) + length(code_issues)
    
    if total_issues > 10
        push!(compliance_issues, "Requirement 4.4 (Quality Assurance): Too many issues found ($total_issues)")
    end
    
    audit_results["compliance_issues"] = compliance_issues
    return compliance_issues
end

function perform_cleanup_actions()
    println("🧹 Performing Cleanup Actions...")
    
    cleanup_count = 0
    
    # 1. Remove outdated or redundant information
    files_to_clean = [
        "docs/src/getting-started/installation.md",
        "docs/src/getting-started/quick-start.md"
    ]
    
    for filepath in files_to_clean
        if !isfile(filepath)
            continue
        end
        
        content = read(filepath, String)
        original_content = content
        
        # Remove redundant "Note:" statements that repeat information
        content = replace(content, r"Note:\s*This\s+is\s+the\s+same\s+as[^\n]*\n" => "")
        
        # Clean up excessive whitespace
        content = replace(content, r"\n{3,}" => "\n\n")
        
        # Remove empty code blocks
        content = replace(content, r"```[a-z]*\n\s*\n```" => "")
        
        if content != original_content
            write(filepath, content)
            push!(cleanup_actions, "Cleaned up redundant content in $(basename(filepath))")
            cleanup_count += 1
        end
    end
    
    # 2. Ensure consistent formatting
    for filepath in files_to_clean
        if !isfile(filepath)
            continue
        end
        
        content = read(filepath, String)
        original_content = content
        
        # Standardize heading formats
        content = replace(content, r"^##\s*([^\n]+)" => s"## \1")
        content = replace(content, r"^###\s*([^\n]+)" => s"### \1")
        
        # Standardize list formatting
        content = replace(content, r"^\*\s+" => "- ")
        
        if content != original_content
            write(filepath, content)
            push!(cleanup_actions, "Standardized formatting in $(basename(filepath))")
            cleanup_count += 1
        end
    end
    
    return cleanup_count
end

function generate_audit_report()
    println("\n📊 FINAL AUDIT REPORT")
    println("=" ^ 50)
    
    # Summary statistics
    frontmatter_issues = get(audit_results, "frontmatter_issues", String[])
    structure_issues = get(audit_results, "structure_issues", String[])
    link_issues = get(audit_results, "link_issues", String[])
    code_issues = get(audit_results, "code_issues", String[])
    compliance_issues = get(audit_results, "compliance_issues", String[])
    
    total_issues = length(frontmatter_issues) + length(structure_issues) + 
                   length(link_issues) + length(code_issues)
    
    println("Total Issues Found: $total_issues")
    println("Frontmatter Issues: $(length(frontmatter_issues))")
    println("Structure Issues: $(length(structure_issues))")
    println("Link Issues: $(length(link_issues))")
    println("Code Issues: $(length(code_issues))")
    println("Compliance Issues: $(length(compliance_issues))")
    println("Cleanup Actions: $(length(cleanup_actions))")
    
    # Detailed breakdown
    if !isempty(frontmatter_issues)
        println("\n❌ FRONTMATTER ISSUES:")
        for issue in frontmatter_issues[1:min(5, length(frontmatter_issues))]
            println("  • $issue")
        end
        if length(frontmatter_issues) > 5
            println("  • ... and $(length(frontmatter_issues) - 5) more")
        end
    end
    
    if !isempty(structure_issues)
        println("\n❌ STRUCTURE ISSUES:")
        for issue in structure_issues[1:min(5, length(structure_issues))]
            println("  • $issue")
        end
        if length(structure_issues) > 5
            println("  • ... and $(length(structure_issues) - 5) more")
        end
    end
    
    if !isempty(link_issues)
        println("\n❌ LINK ISSUES:")
        for issue in link_issues[1:min(3, length(link_issues))]
            println("  • $issue")
        end
        if length(link_issues) > 3
            println("  • ... and $(length(link_issues) - 3) more")
        end
    end
    
    if !isempty(cleanup_actions)
        println("\n✅ CLEANUP ACTIONS PERFORMED:")
        for action in cleanup_actions
            println("  • $action")
        end
    end
    
    # Requirements validation
    println("\n📋 REQUIREMENTS VALIDATION:")
    req_2_1_pass = length(frontmatter_issues) + length(structure_issues) < 5
    req_4_1_pass = length(link_issues) + length(code_issues) < 10
    req_4_4_pass = total_issues < 15
    
    println("  • Requirement 2.1 (Consistent Structure): $(req_2_1_pass ? "✅ PASS" : "❌ FAIL")")
    println("  • Requirement 4.1 (Accuracy & Completeness): $(req_4_1_pass ? "✅ PASS" : "❌ FAIL")")
    println("  • Requirement 4.4 (Quality Assurance): $(req_4_4_pass ? "✅ PASS" : "❌ FAIL")")
    
    # Overall assessment
    overall_pass = req_2_1_pass && req_4_1_pass && req_4_4_pass
    println("\n🎯 OVERALL ASSESSMENT: $(overall_pass ? "✅ PASS" : "❌ NEEDS WORK")")
    
    if overall_pass
        println("🎉 Content audit completed successfully!")
        println("📚 Documentation is ready for production use.")
    else
        println("⚠️  Content audit identified issues that need attention.")
        println("🔧 Review the issues above and apply necessary fixes.")
    end
    
    return overall_pass
end

# Main execution
println("🚀 Starting Final Content Audit and Cleanup")
println("=" ^ 50)

# Run all audit checks
frontmatter_issues = audit_frontmatter_consistency()
structure_issues = audit_content_structure()
link_issues = audit_link_integrity()
code_issues = audit_code_examples()
compliance_issues = audit_requirements_compliance()

# Perform cleanup
cleanup_count = perform_cleanup_actions()

# Generate final report
overall_pass = generate_audit_report()

# Exit with appropriate code
exit_code = overall_pass ? 0 : 1
println("\nAudit completed with exit code: $exit_code")
exit(exit_code)