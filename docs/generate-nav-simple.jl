#!/usr/bin/env julia

"""
Simple Navigation Generator

Generates navigation elements without external dependencies.
Uses the navigation configuration defined in navigation-config.md.
"""

# Navigation data structure (manually maintained based on navigation-config.md)
const NAVIGATION = Dict(
    "getting_started" => Dict(
        "title" => "Getting Started",
        "icon" => "🚀",
        "path" => "getting-started/",
        "description" => "New to Planar? Start here",
        "order" => 1,
        "pages" => [
            ("index", "Overview", "Getting started overview and path selection", 1),
            ("installation", "Installation", "Install Planar and dependencies", 2, "10 min"),
            ("quick-start", "Quick Start", "Get up and running in 15 minutes", 3, "15 min"),
            ("first-strategy", "First Strategy", "Build your first trading strategy", 4, "20 min")
        ],
        "next_section" => "guides"
    ),
    "guides" => Dict(
        "title" => "Development Guides",
        "icon" => "📚",
        "path" => "guides/",
        "description" => "Build trading strategies",
        "order" => 2,
        "pages" => [
            ("index", "Overview", "Guide overview and topics", 1),
            ("strategy-development", "Strategy Development", "Core development guide", 2, "45 min"),
            ("data-management", "Data Management", "Working with market data", 3, "30 min"),
            ("execution-modes", "Execution Modes", "Sim, Paper, and Live trading", 4, "25 min"),
            ("optimization", "Optimization", "Parameter tuning and optimization", 5, "35 min"),
            ("visualization", "Visualization", "Plotting and analysis", 6, "20 min")
        ],
        "next_section" => "advanced"
    ),
    "advanced" => Dict(
        "title" => "Advanced Topics",
        "icon" => "⚡",
        "path" => "advanced/",
        "description" => "Advanced usage and customization",
        "order" => 3,
        "pages" => [
            ("index", "Overview", "Advanced topics overview", 1),
            ("customization", "Customization", "Extending Planar functionality", 2, "40 min"),
            ("margin-trading", "Margin Trading", "Advanced trading features", 3, "30 min"),
            ("multi-exchange", "Multi-Exchange", "Complex multi-exchange setups", 4, "35 min"),
            ("performance", "Performance", "Optimization and scaling", 5, "25 min")
        ],
        "next_section" => "reference"
    ),
    "reference" => Dict(
        "title" => "API Reference",
        "icon" => "📖",
        "path" => "reference/",
        "description" => "Complete function documentation",
        "order" => 4,
        "pages" => [
            ("index", "Overview", "API reference overview", 1),
            ("configuration", "Configuration", "All configuration options", 2),
            ("types", "Types", "Type system reference", 3)
        ],
        "next_section" => "troubleshooting"
    ),
    "troubleshooting" => Dict(
        "title" => "Troubleshooting",
        "icon" => "🔧",
        "path" => "troubleshooting/",
        "description" => "Problem resolution",
        "order" => 5,
        "pages" => [
            ("index", "Overview", "Problem categories and quick fixes", 1),
            ("installation-issues", "Installation Issues", "Setup and dependency problems", 2),
            ("strategy-problems", "Strategy Problems", "Strategy development issues", 3),
            ("performance-issues", "Performance Issues", "Speed and memory problems", 4),
            ("exchange-issues", "Exchange Issues", "Connection and API problems", 5)
        ],
        "next_section" => "resources"
    ),
    "resources" => Dict(
        "title" => "Resources",
        "icon" => "📚",
        "path" => "resources/",
        "description" => "Additional materials",
        "order" => 6,
        "pages" => [
            ("index", "Overview", "Available resources", 1),
            ("glossary", "Glossary", "Terms and concepts", 2),
            ("migration-guides", "Migration Guides", "Version update guides", 3),
            ("community", "Community", "Support and contacts", 4)
        ]
    )
)

const USER_JOURNEYS = Dict(
    "new_user" => Dict(
        "title" => "New to Planar",
        "description" => "Complete beginner path",
        "time" => "90 minutes",
        "path" => [
            "getting-started/installation",
            "getting-started/quick-start", 
            "getting-started/first-strategy",
            "guides/strategy-development"
        ]
    ),
    "strategy_developer" => Dict(
        "title" => "Strategy Developer",
        "description" => "Focus on building strategies",
        "time" => "3 hours",
        "path" => [
            "guides/strategy-development",
            "guides/data-management",
            "guides/execution-modes", 
            "guides/optimization",
            "advanced/customization"
        ]
    ),
    "advanced_user" => Dict(
        "title" => "Advanced User",
        "description" => "Customization and scaling",
        "time" => "2.5 hours",
        "path" => [
            "advanced/customization",
            "advanced/margin-trading",
            "advanced/multi-exchange",
            "advanced/performance",
            "reference/api/core"
        ]
    ),
    "troubleshooter" => Dict(
        "title" => "Need Help",
        "description" => "Problem resolution",
        "time" => "30 minutes",
        "path" => [
            "troubleshooting/index",
            "troubleshooting/installation-issues",
            "troubleshooting/strategy-problems",
            "resources/community"
        ]
    )
)

"""
Generate main navigation menu
"""
function generate_main_menu()
    sections = sort(collect(NAVIGATION), by=x -> x[2]["order"])
    
    menu = "# Planar Documentation\n\n"
    
    for (key, section) in sections
        icon = section["icon"]
        title = section["title"]
        description = section["description"]
        path = section["path"]
        
        menu *= """
## $icon $title

$description

[Explore $title]($path)

"""
    end
    
    return menu
end

"""
Generate section menu
"""
function generate_section_menu(section_key)
    if !haskey(NAVIGATION, section_key)
        return "Section not found: $section_key"
    end
    
    section = NAVIGATION[section_key]
    pages = section["pages"]
    
    menu = "# $(section["title"])\n\n$(section["description"])\n\n"
    
    for page in pages
        slug, title, description, order = page[1:4]
        time = length(page) > 4 ? " ($(page[5]))" : ""
        path = section["path"] * slug * ".md"
        
        menu *= "- [$title]($path)$time - $description\n"
    end
    
    return menu
end

"""
Generate user journey menu
"""
function generate_user_journey_menu()
    menu = "# Choose Your Path\n\n"
    
    for (key, journey) in USER_JOURNEYS
        title = journey["title"]
        description = journey["description"]
        time = journey["time"]
        first_step = journey["path"][1]
        
        menu *= """
## $title

$description

**Estimated time:** $time

[Start Journey]($first_step.md)

"""
    end
    
    return menu
end

"""
Generate breadcrumbs for a path
"""
function generate_breadcrumbs(current_path)
    parts = split(current_path, "/")
    filter!(p -> !isempty(p) && p != "index.md", parts)
    
    breadcrumbs = ["[Docs](../index.md)"]
    
    if !isempty(parts)
        section_key = replace(parts[1], ".md" => "")
        
        # Find section
        for (key, section) in NAVIGATION
            if key == section_key || section["path"] == "$(parts[1])/"
                push!(breadcrumbs, section["title"])
                break
            end
        end
    end
    
    return join(breadcrumbs, " > ")
end

"""
Generate next steps for current location
"""
function generate_next_steps(section_key, page_slug)
    if !haskey(NAVIGATION, section_key)
        return ""
    end
    
    section = NAVIGATION[section_key]
    pages = section["pages"]
    
    # Find current page
    current_index = 0
    for (i, page) in enumerate(pages)
        if page[1] == page_slug
            current_index = i
            break
        end
    end
    
    suggestions = String[]
    
    # Next page in section
    if current_index > 0 && current_index < length(pages)
        next_page = pages[current_index + 1]
        title = next_page[2]
        slug = next_page[1]
        path = section["path"] * slug * ".md"
        push!(suggestions, "- [Continue: $title]($path)")
    end
    
    # Next section
    if haskey(section, "next_section")
        next_key = section["next_section"]
        if haskey(NAVIGATION, next_key)
            next_section = NAVIGATION[next_key]
            title = next_section["title"]
            path = next_section["path"]
            push!(suggestions, "- [Explore: $title]($path)")
        end
    end
    
    return isempty(suggestions) ? "" : "## Next Steps\n\n" * join(suggestions, "\n")
end

# Command line interface
if abspath(PROGRAM_FILE) == @__FILE__
    if length(ARGS) == 0
        println("Usage:")
        println("  julia generate-nav-simple.jl menu")
        println("  julia generate-nav-simple.jl section <section_key>")
        println("  julia generate-nav-simple.jl journeys")
        println("  julia generate-nav-simple.jl breadcrumbs <path>")
        println("  julia generate-nav-simple.jl next-steps <section> <page>")
        exit(1)
    end
    
    command = ARGS[1]
    
    if command == "menu"
        println(generate_main_menu())
    elseif command == "section" && length(ARGS) >= 2
        println(generate_section_menu(ARGS[2]))
    elseif command == "journeys"
        println(generate_user_journey_menu())
    elseif command == "breadcrumbs" && length(ARGS) >= 2
        println(generate_breadcrumbs(ARGS[2]))
    elseif command == "next-steps" && length(ARGS) >= 3
        println(generate_next_steps(ARGS[2], ARGS[3]))
    else
        println("Unknown command or missing arguments")
        exit(1)
    end
end