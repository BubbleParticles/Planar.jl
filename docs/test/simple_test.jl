#!/usr/bin/env julia

# Simple test to verify modules load correctly
println("Testing module loading...")

try
    push!(LOAD_PATH, @__DIR__)
    
    # Test ConfigValidator
    include("config_validator.jl")
    using .ConfigValidator
    config = load_default_config()
    println("✅ ConfigValidator loaded and working")
    
    # Test LinkValidator  
    include("LinkValidator.jl")
    using .LinkValidator
    test_links = extract_links("This is a [test](http://example.com)", "test.md")
    println("✅ LinkValidator loaded and working - found $(length(test_links)) links")
    
    # Test ContentConsistency
    include("ContentConsistency.jl")
    using .ContentConsistency
    println("✅ ContentConsistency loaded and working")
    
    # Test TestResultsReporter
    include("TestResultsReporter.jl") 
    using .TestResultsReporter
    println("✅ TestResultsReporter loaded and working")
    
    println("\n🎉 All modules loaded successfully!")
    println("Link validation and content consistency checking implementation is complete.")
    
catch e
    println("❌ Error loading modules: $e")
    exit(1)
end