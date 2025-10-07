# Documentation Code Block Guidelines

This document provides guidelines for writing testable code blocks in Planar documentation to prevent common errors and ensure all examples work correctly.

## Common Error Patterns and Solutions

### 1. Project Activation Issues

**Problem**: Code blocks using PlanarInteractive features while Planar project is active.

**Error Pattern**: `TaskFailedException` when loading PlanarInteractive modules

**Solution**:

### 2. Undefined Variables

**Problem**: Code blocks reference variables that aren't defined in scope.

**Error Pattern**: `UndefVarError: variable not defined`

**Solution**:

### 3. Import Conflicts

**Problem**: Multiple modules importing conflicting identifiers.

**Error Pattern**: `WARNING: using X.Y conflicts with an existing identifier`

**Solution**:

### 4. Module Loading Issues

**Problem**: Specific modules or submodules cannot be loaded.

**Error Pattern**: `WARNING: could not import X.Y into DocTestFramework`

**Solution**:

## Best Practices for Code Blocks

### 1. Always Include Necessary Imports

Every code block should be self-contained:


### 2. Use Realistic Example Values

When demonstrating functionality, use realistic values:


### 3. Add Error Handling for Robustness

Make examples robust with proper error handling:

```julia
# ✅ Good - handles potential errors
try
    exchange = getexchange!(:binance)
    data = fetch_ohlcv(exchange, tf"1h", "BTC/USDT"; from=-100)
    @info "Successfully fetched $(nrow(data)) candles"
# ✅ Good - properly scoped strategy module
module ExampleStrategy
using Planar

const DESCRIPTION = "Example strategy"

#### For Strategy Development

## Testing Your Code Blocks

### Manual Testing
Before submitting documentation, test your code blocks:

```bash
# Test individual code block
julia --project=Planar -e "
# Paste your code block here
"
```

### Automated Testing
The documentation test suite runs:
```bash
julia --project=Planar docs/test/runtests.jl --skip-external --verbose
```

## Common Pitfalls to Avoid

### 1. Don't Use Bare Environment Macros

### 2. Don't Assume Previous Code Block Context
Each code block should be independent:


### 3. Don't Use Hardcoded Paths

### 4. Don't Ignore Error Handling

## Validation Checklist

Before submitting documentation with code blocks:

- [ ] All necessary imports are included
- [ ] Variables are defined before use
- [ ] Realistic example values are used
- [ ] Error handling is included where appropriate
- [ ] Code blocks are properly scoped (modules where needed)
- [ ] Project activation is explicit when needed
- [ ] No hardcoded paths or system-specific values
- [ ] Code blocks are independent and self-contained
- [ ] Examples demonstrate the intended functionality clearly

## Getting Help

If you encounter issues with documentation code blocks:

1. Check this guide for common patterns
2. Test your code block manually
3. Review similar examples in existing documentation
4. Ask for help in the development channels

## Contributing

When adding new documentation:

1. Follow these guidelines
2. Test your code blocks
3. Include proper error handling
4. Use realistic example values
5. Ensure educational value is maintained