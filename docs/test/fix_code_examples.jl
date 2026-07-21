#!/usr/bin/env julia

"""
Fix Code Examples Script

This script fixes Julia code blocks that contain markdown links,
which cause parsing errors during testing.
"""

function fix_code_blocks(filepath::String)
    if !isfile(filepath)
        return false
    end
    
    content = read(filepath, String)
    original_content = content
    
    # Fix common issues in Julia code blocks
    fixes = Dict(
        # Remove markdown links from Julia code
        r"s = strategy\(:QuickStart, \[exchange\]\([^)]+\)=:binance\)" => "s = strategy(:QuickStart, exchange=:binance)",
        r"\[strategy\]\([^)]+\)" => "strategy",
        r"\[exchange\]\([^)]+\)" => "exchange", 
        r"\[API keys\]\([^)]+\)" => "API keys",
        r"\[configuration\]\([^)]+\)" => "configuration",
        r"\[RSI\]\([^)]+\)" => "RSI",
        r"\[backtesting\]\([^)]+\)" => "backtesting",
        r"\[live trading\]\([^)]+\)" => "live trading",
        r"\[OHLCV data\]\([^)]+\)" => "OHLCV data",
        r"\[timeframe\]\([^)]+\)" => "timeframe",
        r"\[strategies\]\([^)]+\)" => "strategies",
        
        # Fix string interpolation issues
        r"\$\$\(" => "\$(",
        
        # Fix malformed comments
        r"# Test small data fetch \(should work without \[API keys\]\([^)]+\)\)" => "# Test small data fetch (should work without API keys)",
        r"# \(this is normal without \[exchange\]\([^)]+\) API\)" => "# (this is normal without exchange API)",
    )
    
    for (pattern, replacement) in fixes
        content = replace(content, pattern => replacement)
    end
    
    # Write back if changes were made
    if content != original_content
        write(filepath, content)
        println("✅ Fixed code examples in $(basename(filepath))")
        return true
    else
        println("ℹ️  No code fixes needed for $(basename(filepath))")
        return false
    end
end

println("🔧 Fixing Code Examples in Documentation")
println("=" ^ 45)

files_to_fix = [
    "docs/src/getting-started/installation.md",
    "docs/src/getting-started/quick-start.md",
    "docs/src/getting-started/first-strategy.md"
]

global fixes_applied = 0
for filepath in files_to_fix
    if fix_code_blocks(filepath)
        global fixes_applied += 1
    end
end

println("\n📊 Code Fix Results:")
println("Files processed: $(length(files_to_fix))")
println("Files fixed: $fixes_applied")
println("\n🎉 Code example fixes completed!")