#!/usr/bin/env julia

"""
Simple test script to verify the link validation and content consistency functionality.
"""

push!(LOAD_PATH, @__DIR__)

include("LinkValidator.jl")
include("ContentConsistency.jl") 
include("config_validator.jl")

using .LinkValidator
using .ContentConsistency
using .ConfigValidator

# Test configuration
config = load_default_config()

println("🧪 Testing Link Validation...")

# Test link extraction
test_content = """
# Test Document

This is a [test link](https://example.com) and an [internal link](../other.md).

Here's a reference link [ref link][1] and a bare URL: https://github.com

[1]: https://docs.julialang.org
"""

links = LinkValidator.extract_links(test_content, "test.md")
println("Extracted $(length(links)) links:")
for (url, line) in links
    println("  Line $line: $url")
end

println("\n🧪 Testing Content Consistency...")

# Test terminology checking
test_content2 = """
# Test Document

This document uses julia instead of Julia.
We also mention the api instead of API.
"""

write("test_temp.md", test_content2)
try
    results = check_terminology_consistency("test_temp.md", config)
    println("Found $(length(results)) terminology issues:")
    for result in results
        println("  Line $(result.line): $(result.issue)")
        if result.suggestion !== nothing
            println("    Suggestion: $(result.suggestion)")
        end
    end
finally
    rm("test_temp.md", force=true)
end

println("\n✅ Basic validation tests completed!")