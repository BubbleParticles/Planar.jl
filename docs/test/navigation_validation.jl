#!/usr/bin/env julia

"""
Navigation and User Journey Validation Script

This script validates the complete user journey from landing page through
getting started, ensuring all navigation paths work correctly.
"""

function validate_user_journey()
    println("🛤️  Validating User Journey Navigation")
    println("=" ^ 40)
    
    # Define the expected user journey
    journey_steps = [
        ("docs/src/index.md", "Landing Page"),
        ("docs/src/getting-started/index.md", "Getting Started Overview"),
        ("docs/src/getting-started/installation.md", "Installation Guide"),
        ("docs/src/getting-started/quick-start.md", "Quick Start Guide"),
        ("docs/src/getting-started/first-strategy.md", "First Strategy Tutorial")
    ]
    
    validation_results = Dict{String, Bool}()
    
    for (filepath, description) in journey_steps
        println("\n📄 Validating: $description")
        
        if !isfile(filepath)
            println("  ❌ File missing: $filepath")
            validation_results[description] = false
            continue
        end
        
        content = read(filepath, String)
        
        # Check for required elements
        checks = Dict{String, Bool}()
        
        # 1. Has frontmatter
        checks["Has frontmatter"] = startswith(content, "---")
        
        # 2. Has title/heading  
        checks["Has main heading"] = occursin(r"^#\s+\w+"m, content) || occursin("\n# ", content)
        
        # 3. Has navigation elements
        if filepath == "docs/src/index.md"
            checks["Has user paths"] = occursin("First Time Here", content) || occursin("Getting Started", content)
            checks["Has quick access"] = occursin("Quick access", content) || occursin("API Docs", content)
        else
            checks["Has next steps"] = occursin("Next Steps", content) || occursin("What's Next", content)
            checks["Has see also"] = occursin("See Also", content) || occursin("Related", content)
        end
        
        # 4. Links to next step in journey
        if filepath != last(journey_steps)[1]  # Not the last step
            next_step_index = findfirst(x -> x[1] == filepath, journey_steps)
            if next_step_index !== nothing && next_step_index < length(journey_steps)
                next_file = journey_steps[next_step_index + 1][1]
                next_filename = basename(next_file)
                checks["Links to next step"] = occursin(next_filename, content)
            end
        end
        
        # 5. Has estimated time (for getting-started pages)
        if contains(filepath, "getting-started") && filepath != "docs/src/getting-started/index.md"
            checks["Has time estimate"] = occursin("estimated_time", content) || occursin("minutes", content)
        end
        
        # Report results for this page
        all_passed = all(values(checks))
        validation_results[description] = all_passed
        
        for (check_name, passed) in checks
            status = passed ? "✅" : "❌"
            println("  $status $check_name")
        end
        
        if all_passed
            println("  🎉 All checks passed for $description")
        else
            failed_checks = [name for (name, passed) in checks if !passed]
            println("  ⚠️  Failed checks: $(join(failed_checks, ", "))")
        end
    end
    
    return validation_results
end

function validate_cross_references()
    println("\n🔗 Validating Cross-References")
    println("=" ^ 30)
    
    # Key files that should cross-reference each other
    cross_ref_pairs = [
        ("docs/src/index.md", "docs/src/getting-started/installation.md"),
        ("docs/src/getting-started/installation.md", "docs/src/getting-started/quick-start.md"),
        ("docs/src/getting-started/quick-start.md", "docs/src/getting-started/first-strategy.md"),
        ("docs/src/getting-started/first-strategy.md", "docs/src/guides/strategy-development.md")
    ]
    
    cross_ref_results = Dict{String, Bool}()
    
    for (source_file, target_file) in cross_ref_pairs
        if !isfile(source_file) || !isfile(target_file)
            cross_ref_results["$(basename(source_file)) → $(basename(target_file))"] = false
            continue
        end
        
        source_content = read(source_file, String)
        target_filename = basename(target_file)
        
        # Check if source links to target
        has_link = occursin(target_filename, source_content)
        cross_ref_results["$(basename(source_file)) → $(basename(target_file))"] = has_link
        
        status = has_link ? "✅" : "❌"
        println("$status $(basename(source_file)) → $(basename(target_file))")
    end
    
    return cross_ref_results
end

function validate_content_completeness()
    println("\n📋 Validating Content Completeness")
    println("=" ^ 35)
    
    # Required content sections for each page type
    content_requirements = Dict(
        "docs/src/index.md" => [
            "What's Next", "First Time Here", "Ready to Build", "Going Live"
        ],
        "docs/src/getting-started/installation.md" => [
            "Prerequisites", "Docker", "Verification", "Troubleshooting", "Next Steps"
        ],
        "docs/src/getting-started/quick-start.md" => [
            "What You'll Accomplish", "Step 1", "Step 2", "Expected output"
        ],
        "docs/src/getting-started/first-strategy.md" => [
            "What You'll Learn", "Prerequisites", "Strategy Structure", "Step"
        ]
    )
    
    completeness_results = Dict{String, Float64}()
    
    for (filepath, required_sections) in content_requirements
        if !isfile(filepath)
            completeness_results[basename(filepath)] = 0.0
            continue
        end
        
        content = read(filepath, String)
        found_sections = 0
        
        println("\n📄 $(basename(filepath)):")
        for section in required_sections
            has_section = occursin(section, content)
            status = has_section ? "✅" : "❌"
            println("  $status $section")
            if has_section
                found_sections += 1
            end
        end
        
        completeness_score = found_sections / length(required_sections)
        completeness_results[basename(filepath)] = completeness_score
        
        println("  📊 Completeness: $(round(completeness_score * 100, digits=1))%")
    end
    
    return completeness_results
end

function validate_time_requirements()
    println("\n⏱️  Validating Time Requirements")
    println("=" ^ 30)
    
    # Extract time estimates from frontmatter
    time_files = [
        "docs/src/getting-started/installation.md",
        "docs/src/getting-started/quick-start.md", 
        "docs/src/getting-started/first-strategy.md"
    ]
    
    total_time = 0
    time_results = Dict{String, Int}()
    
    for filepath in time_files
        if !isfile(filepath)
            continue
        end
        
        content = read(filepath, String)
        
        # Look for estimated_time in frontmatter
        time_match = match(r"estimated_time:\s*[\"']?(\d+)", content)
        if time_match !== nothing
            estimated_time = parse(Int, time_match.captures[1])
            time_results[basename(filepath)] = estimated_time
            total_time += estimated_time
            
            println("📄 $(basename(filepath)): $estimated_time minutes")
        else
            println("❌ $(basename(filepath)): No time estimate found")
            time_results[basename(filepath)] = 0
        end
    end
    
    println("\n📊 Total estimated time: $total_time minutes")
    
    # Check against requirement (should be ≤ 30 minutes)
    meets_requirement = total_time <= 30
    status = meets_requirement ? "✅" : "❌"
    println("$status Meets 30-minute requirement: $meets_requirement")
    
    return time_results, total_time, meets_requirement
end

# Main execution
println("🚀 Starting Navigation and User Journey Validation")
println("=" ^ 55)

# Run all validations
journey_results = validate_user_journey()
cross_ref_results = validate_cross_references()
completeness_results = validate_content_completeness()
time_results, total_time, time_ok = validate_time_requirements()

# Generate summary report
println("\n📊 VALIDATION SUMMARY")
println("=" ^ 25)

# Journey validation
journey_passed = count(values(journey_results))
journey_total = length(journey_results)
println("User Journey: $journey_passed/$journey_total pages validated ($(round(journey_passed/journey_total*100, digits=1))%)")

# Cross-reference validation
cross_ref_passed = count(values(cross_ref_results))
cross_ref_total = length(cross_ref_results)
println("Cross-References: $cross_ref_passed/$cross_ref_total links working ($(round(cross_ref_passed/cross_ref_total*100, digits=1))%)")

# Content completeness
avg_completeness = sum(values(completeness_results)) / length(completeness_results) * 100
println("Content Completeness: $(round(avg_completeness, digits=1))% average")

# Time requirements
println("Time Requirements: $(time_ok ? "✅ PASS" : "❌ FAIL") ($total_time/30 minutes)")

# Overall assessment
overall_score = (journey_passed/journey_total + cross_ref_passed/cross_ref_total + avg_completeness/100) / 3
println("\n🎯 Overall Score: $(round(overall_score * 100, digits=1))%")

if overall_score >= 0.8
    println("🎉 User journey validation PASSED!")
    exit(0)
else
    println("⚠️  User journey validation needs improvement")
    exit(1)
end