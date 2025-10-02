# Documentation Testing Annotations

This file demonstrates how to add testing annotations to documentation code blocks.

## Basic Code Block

Simple code blocks are tested automatically:

```julia
# This will be tested
x = 1 + 1
println("Result: $x")
```

## Code Block with Expected Output

You can specify expected output for validation:

```julia
# DOCTEST_OUTPUT:
# Result: 2
x = 1 + 1
println("Result: $x")
```

## Code Block with Multiple Julia Versions

Test compatibility across Julia versions:

```julia
# This works on Julia 1.10+
x = [1, 2, 3]
y = sum(x)
println("Sum: $y")
```

## Code Block with Requirements

Specify required packages:

```julia
# DOCTEST_REQUIRES: DataFrames, Statistics
using DataFrames, Statistics
df = DataFrame(x = [1, 2, 3, 4, 5])
mean(df.x)
```

## Code Block with Custom Timeout

For long-running examples:

```julia
# DOCTEST_TIMEOUT: 60
# This example might take longer to run
using Planar
# ... some complex operation
```

## Skipped Code Block

Some code blocks should not be tested (e.g., pseudocode):

```julia
# DOCTEST_SKIP
# This is just pseudocode to illustrate a concept
function my_strategy(data)
    # ... implementation details
    return result
end
```

## Interactive Examples

Code that requires user interaction should be skipped:

```julia
# DOCTEST_SKIP
# Interactive plotting example
using Plotting
plot_ohlcv(data)
# User would interact with the plot here
```

## Complex Example with Multiple Annotations

```julia
# DOCTEST_REQUIRES: Statistics
# DOCTEST_TIMEOUT: 45
# DOCTEST_OUTPUT:
# Mean: 2.0
# Std: 1.58
using Statistics

# Simple statistical calculation
data = [1, 2, 3]
mean_val = mean(data)
std_val = round(std(data), digits=2)

println("Mean: $mean_val")
println("Std: $std_val")
```

## Example with Output Validation Features

This example demonstrates the enhanced output validation:

```julia
# DOCTEST_OUTPUT:
# Processing complete in 0.123s
# Status: SUCCESS
println("Processing complete in 0.123s")  # Timing will be ignored
println("Status: SUCCESS")
```

## Testing Guidelines

1. **Use DOCTEST_SKIP** for:
   - Pseudocode examples
   - Interactive examples
   - Examples requiring external services
   - Examples with non-deterministic output

2. **Use DOCTEST_REQUIRES** for:
   - Examples needing specific packages
   - Examples requiring optional dependencies

3. **Use DOCTEST_OUTPUT** for:
   - Examples where output validation is important
   - Examples demonstrating specific results

4. **Use DOCTEST_TIMEOUT** for:
   - Long-running optimization examples
   - Examples involving data downloads
   - Complex computations

## Best Practices

- Keep code examples simple and focused
- Ensure examples are self-contained
- Use realistic but minimal data
- Avoid examples that depend on external state
- Test examples locally before committing