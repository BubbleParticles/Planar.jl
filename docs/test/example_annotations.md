# Documentation Testing Annotations

This file demonstrates how to add testing annotations to documentation code blocks.

## Basic Code Block

Simple code blocks are tested automatically:


## Code Block with Expected Output

You can specify expected output for validation:


## Code Block with Multiple Julia Versions

Test compatibility across Julia versions:


## Code Block with Requirements

Specify required packages:


## Code Block with Custom Timeout

For long-running examples:


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


## Complex Example with Multiple Annotations


## Example with Output Validation Features

This example demonstrates the enhanced output validation:


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