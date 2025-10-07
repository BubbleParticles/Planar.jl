#!/usr/bin/env julia

"""
Script to systematically fix documentation code blocks
"""

using Pkg

# Common patterns for fixing code blocks
const COMMON_FIXES = [
    # Add project activation for Planar usage
    (r"```julia\n(using Planar)", "```julia\n# Activate Planar project\nimport Pkg; Pkg.activate(\"Planar\")\n\n\\1"),
    
    # Add project activation for PlanarInteractive usage  
    (r"```julia\n(using PlanarInteractive)", "```julia\n# Activate PlanarInteractive project\nimport Pkg; Pkg.activate(\"PlanarInteractive\")\n\n\\1"),
    
    # Wrap Scrapers usage in try-catch
    (r"```julia\n(using Scrapers[^\n]*\n)", "```julia\n# Activate Planar project\nimport Pkg; Pkg.activate(\"Planar\")\n\ntry\n    \\1"),
    
    # Add missing variable definitions
    (r"exchange_name", "exchange_name = \"binance\"  # Example exchange"),
    (r"symbol(?![a-zA-Z])", "symbol = \"BTCUSDT\"  # Example symbol"),
    (r"key(?![a-zA-Z])", "key = \"example_key\"  # Example key"),
    (r"storage_config", "storage_config = Dict(\"path\" => \"data/\")  # Example storage config"),
]

function fix_file(filepath::String)
    println("Fixing file: $filepath")
    
    content = read(filepath, String)
    original_content = content
    
    # Apply common fixes
    for (pattern, replacement) in COMMON_FIXES
        content = replace(content, pattern => replacement)
    end
    
    # Write back if changed
    if content != original_content
        write(filepath, content)
        println("  ✓ Applied fixes to $filepath")
    else
        println("  - No changes needed for $filepath")
    end
end

function main()
    # Files to fix based on error log
    files_to_fix = [
        "docs/src/config.md",
        "docs/src/data.md", 
        "docs/src/devdocs.md",
        "docs/src/exchanges.md"
    ]
    
    for file in files_to_fix
        if isfile(file)
            fix_file(file)
        else
            println("File not found: $file")
        end
    end
    
    println("\nFixes applied. Run documentation tests to verify.")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end