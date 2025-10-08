#!/usr/bin/env julia

# Fix script to update error handling in DocTestFramework.jl
# This script will change line 397 from 'output = string(e)' to 'output = sprint(showerror, e, catch_backtrace())'

file_path = "docs/test/DocTestFramework.jl"

# Read the current file
content = read(file_path, String)

# Replace the specific line
lines = split(content, '\n')
if length(lines) >= 397
    lines[397] = "            output = sprint(showerror, e, catch_backtrace())"
end

# Write back to file
open(file_path, "w") do f
    write(f, join(lines, '\n'))
end

println("Fixed error handling in DocTestFramework.jl")