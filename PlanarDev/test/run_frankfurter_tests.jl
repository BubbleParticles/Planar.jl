#!/usr/bin/env julia

# Simple test runner for Frankfurter API tests
# Usage: julia run_frankfurter_tests.jl

using Pkg
Pkg.activate(".")

# Load the test file
include("test_frankfurter.jl")

# Run the tests
println("Running Frankfurter API tests...")
test_frankfurter()
println("Frankfurter API tests completed!")
