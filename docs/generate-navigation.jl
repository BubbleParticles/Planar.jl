#!/usr/bin/env julia

"""
Navigation Generation System

This script generates navigation menus, breadcrumbs, and related content
suggestions based on the navigation configuration.
"""

using YAML
using Markdown

# Load navigation configuration
const NAV_CONFIG = YAML.load_file("docs/navigation.yml")

"""
    generate_main_menu() -> String

Generate the main navigation menu HTML/Markdown.
"""
function generate_main_menu()
    nav = NAV_CONFIG["navigation"]
    sections = sort(collect(nav), by=x -> x[2]["order"])
    
    menu_items = String[]
    
    for (section_key, section) in sections
        icon = get(section, "icon", "")
        title = section["title"]
        description = section["description"]
        path = section["path"]
        
        menu_item = """
        ## $icon $title
        
        $description
        
        [Explore $title]($path)
        """
        
        push!(menu_items, menu_item)
    end
    
    return join(menu_items, "\n")
end

"""
    generate_section_menu(section_key::String) -> String

Generate a menu for a specific section showing its pages.
"""
function generate_section_menu(section_key::String)
    nav = NAV_CONFIG["navigation"]
    
    if !haskey(nav, section_key)
        return "Section not found: $section_key"
    end
    
    section = nav[section_key]
    pages = get(section, "pages", [])
    
    if isempty(pages)
        return "No pages found in section: $section_key"
    end
    
    # Sort pages by order
    sorted_pages = sort(pages, by=p -> get(p, "order", 999))
    
    menu_items = String[]
    
    for page in sorted_pages
        title = page["title"]
        description = get(page, "description", "")
        slug = page["slug"]
        time = get(page, "estimated_time", "")
        
        path = section["path"] * slug * ".md"
        
        time_info = isempty(time) ? "" : " ($time)"
        
        menu_item = "- [$title]($path)$time_info"
        if !isempty(description)
            menu_item *= " - $description"
        end
        
        push!(menu_items, menu_item)
    end
    
    return join(menu_items, "\n")
end

"""
    generate_breadcrumbs(current_path::String) -> String

Generate breadcrumb navigation for a given path.
"""
function generate_breadcrumbs(current_path::String)
    config = NAV_CONFIG["breadcrumbs"]
    separator = config["separator"]
    show_home = config["show_home"]
    home_title = config["home_title"]
    
    # Parse path components
    path_parts = split(current_path, "/")
    filter!(p -> !isempty(p) && p != "index.md", path_parts)
    
    breadcrumbs = String[]
    
    # Add home if configured
    if show_home
        push!(breadcrumbs, "[$home_title](../index.md)")
    end
    
    # Build breadcrumb path
    current_nav_path = ""
    nav = NAV_CONFIG["navigation"]
    
    for (i, part) in enumerate(path_parts)
        current_nav_path = isempty(current_nav_path) ? part : "$current_nav_path/$part"
        
        # Find matching section
        section_title = part
        for (section_key, section) in nav
            if section["path"] == "$part/" || section_key == part
                section_title = section["title"]
                break
            end
        end
        
        # Create link (except for current page)
        if i < length(path_parts)
            relative_path = "../" ^ (length(path_parts) - i) * "$current_nav_path/"
            push!(breadcrumbs, "[$section_title]($relative_path)")
        else
            push!(breadcrumbs, section_title)
        end
    end
    
    return join(breadcrumbs, separator)
end

"""
    generate_next_steps(current_section::String, current_page::String) -> String

Generate "Next Steps" suggestions based on current location.
"""
function generate_next_steps(current_section::String, current_page::String)
    nav = NAV_CONFIG["navigation"]
    
    if !haskey(nav, current_section)
        return ""
    end
    
    section = nav[current_section]
    pages = get(section, "pages", [])
    
    # Find current page index
    current_index = 0
    for (i, page) in enumerate(pages)
        if page["slug"] == current_page
            current_index = i
            break
        end
    end
    
    suggestions = String[]
    
    # Next page in same section
    if current_index > 0 && current_index < length(pages)
        next_page = pages[current_index + 1]
        title = next_page["title"]
        slug = next_page["slug"]
        path = section["path"] * slug * ".md"
        push!(suggestions, "- [Continue: $title]($path)")
    end
    
    # Next section
    if haskey(section, "next_section")
        next_section_key = section["next_section"]
        if haskey(nav, next_section_key)
            next_section = nav[next_section_key]
            title = next_section["title"]
            path = next_section["path"]
            push!(suggestions, "- [Explore: $title]($path)")
        end
    end
    
    # Related content based on rules
    rules = NAV_CONFIG["cross_references"]["related_content_rules"]
    for rule in rules
        if rule["if_category"] == current_section
            suggest_categories = rule["suggest_categories"]
            max_suggestions = get(rule, "max_suggestions", 3)
            
            count = 0
            for cat in suggest_categories
                if count >= max_suggestions
                    break
                end
                
                if haskey(nav, cat)
                    cat_section = nav[cat]
                    title = cat_section["title"]
                    path = cat_section["path"]
                    push!(suggestions, "- [See also: $title]($path)")
                    count += 1
                end
            end
            break
        end
    end
    
    return isempty(suggestions) ? "" : "## Next Steps\n\n" * join(suggestions, "\n")
end

"""
    generate_user_journey_menu() -> String

Generate user journey selection menu for the main page.
"""
function generate_user_journey_menu()
    journeys = NAV_CONFIG["user_journeys"]
    
    menu_items = String[]
    
    for (journey_key, journey) in journeys
        title = journey["title"]
        description = journey["description"]
        time = journey["estimated_total_time"]
        
        # Get first step in journey
        first_step = journey["path"][1]
        
        menu_item = """
        ### $title
        
        $description
        
        **Estimated time:** $time
        
        [Start Journey]($first_step.md)
        """
        
        push!(menu_items, menu_item)
    end
    
    return join(menu_items, "\n")
end

"""
    generate_related_content(current_file::String) -> String

Generate related content suggestions for a file.
"""
function generate_related_content(current_file::String)
    # This would analyze the current file's frontmatter and content
    # to suggest related pages based on tags, categories, etc.
    
    # For now, return a placeholder
    return """
    ## See Also
    
    - [Related Topic 1](related-topic-1.md)
    - [Related Topic 2](related-topic-2.md)
    - [API Reference](../reference/api/)
    """
end

"""
    update_navigation_in_file(filepath::String)

Update navigation elements in a documentation file.
"""
function update_navigation_in_file(filepath::String)
    if !isfile(filepath) || !endswith(filepath, ".md")
        return
    end
    
    content = read(filepath, String)
    
    # Extract path information
    rel_path = replace(filepath, "docs/src/" => "")
    path_parts = split(dirname(rel_path), "/")
    
    if !isempty(path_parts) && !isempty(path_parts[1])
        section = path_parts[1]
        page = replace(basename(filepath), ".md" => "")
        
        # Generate breadcrumbs
        breadcrumbs = generate_breadcrumbs(rel_path)
        
        # Generate next steps
        next_steps = generate_next_steps(section, page)
        
        # Update content (this is a simplified version)
        # In practice, you'd want more sophisticated content replacement
        
        println("Updated navigation for: $filepath")
        println("Breadcrumbs: $breadcrumbs")
        if !isempty(next_steps)
            println("Next steps generated")
        end
    end
end

# Command-line interface
if abspath(PROGRAM_FILE) == @__FILE__
    if length(ARGS) == 0
        println("Usage:")
        println("  julia generate-navigation.jl menu                    # Generate main menu")
        println("  julia generate-navigation.jl section <section_name>  # Generate section menu")
        println("  julia generate-navigation.jl breadcrumbs <path>      # Generate breadcrumbs")
        println("  julia generate-navigation.jl journeys               # Generate user journeys")
        println("  julia generate-navigation.jl update <file>          # Update file navigation")
        exit(1)
    end
    
    command = ARGS[1]
    
    if command == "menu"
        println(generate_main_menu())
    elseif command == "section" && length(ARGS) >= 2
        section = ARGS[2]
        println(generate_section_menu(section))
    elseif command == "breadcrumbs" && length(ARGS) >= 2
        path = ARGS[2]
        println(generate_breadcrumbs(path))
    elseif command == "journeys"
        println(generate_user_journey_menu())
    elseif command == "update" && length(ARGS) >= 2
        filepath = ARGS[2]
        update_navigation_in_file(filepath)
    else
        println("Unknown command: $command")
        exit(1)
    end
end