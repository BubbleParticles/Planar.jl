# Documentation Code Block Guidelines

This document provides guidelines for writing testable code blocks in Planar documentation to prevent common errors and ensure all examples work correctly.

## Common Error Patterns and Solutions

### 1. Project Activation Issues

**Problem**: Code blocks using PlanarInteractive features while Planar project is active.

**Error Pattern**: `TaskFailedException` when loading PlanarInteractive modules

**Solution**:
```julia
# ❌ Wrong - will fail if Planar project is active
using PlanarInteractive

# ✅ Correct - explicitly activate the right project
import Pkg
Pkg.activate("PlanarInteractive")
using PlanarInteractive
```

### 2. Undefined Variables

**Problem**: Code blocks reference variables that aren't defined in scope.

**Error Pattern**: `UndefVarError: variable not defined`

**Solution**:
```julia
# ❌ Wrong - exchange_name not defined
@info "Processing exchange: $exchange_name"

# ✅ Correct - define variables with example values
exchange_name = "binance"  # Example exchange
@info "Processing exchange: $exchange_name"
```

### 3. Import Conflicts

**Problem**: Multiple modules importing conflicting identifiers.

**Error Pattern**: `WARNING: using X.Y conflicts with an existing identifier`

**Solution**:
```julia
# ❌ Wrong - can cause conflicts
using Executors
using Strategies

# ✅ Correct - use qualified imports or proper module scoping
module MyStrategy
using Planar
@strategyenv!  # This handles imports properly

# Your strategy code here
end
```

### 4. Module Loading Issues

**Problem**: Specific modules or submodules cannot be loaded.

**Error Pattern**: `WARNING: could not import X.Y into DocTestFramework`

**Solution**:
```julia
# ❌ Wrong - may not be available
using Engine.Executors: SimMode as sm

# ✅ Correct - use standard Planar patterns
using Planar
@environment!
# Use standard functions like strategy(), start!(), etc.
```

## Best Practices for Code Blocks

### 1. Always Include Necessary Imports

Every code block should be self-contained:

```julia
# ✅ Good - includes all necessary imports
using Planar
using TimeTicks
using Exchanges

# Your code here
```

### 2. Use Realistic Example Values

When demonstrating functionality, use realistic values:

```julia
# ✅ Good - realistic example values
exchange_name = "binance"
pair = "BTC/USDT"
timeframe = tf"1h"
```

### 3. Add Error Handling for Robustness

Make examples robust with proper error handling:

```julia
# ✅ Good - handles potential errors
try
    exchange = getexchange!(:binance)
    data = fetch_ohlcv(exchange, tf"1h", "BTC/USDT"; from=-100)
    @info "Successfully fetched $(nrow(data)) candles"
catch e
    @warn "Data fetch failed: $e"
    @info "This is normal without proper API configuration"
end
```

### 4. Proper Module Scoping

When showing strategy examples, use proper module structure:

```julia
# ✅ Good - properly scoped strategy module
module ExampleStrategy
using Planar

const DESCRIPTION = "Example strategy"
const EXC = :binance
const MARGIN = NoMargin
const TF = tf"1h"

@strategyenv!

function call!(::Type{<:SC}, ::LoadStrategy, config)
    # Strategy implementation
end

end
```

### 5. Project-Specific Patterns

#### For Basic Planar Features
```julia
import Pkg
Pkg.activate("Planar")
using Planar
```

#### For Interactive Features
```julia
import Pkg
Pkg.activate("PlanarInteractive")
using PlanarInteractive
@environment!
```

#### For Strategy Development
```julia
module MyStrategy
using Planar
@strategyenv!
# Strategy code here
end
```

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
```julia
# ❌ Wrong - causes import conflicts
@strategyenv!
@contractsenv!

# ✅ Correct - use within module context
module MyStrategy
using Planar
@strategyenv!
end
```

### 2. Don't Assume Previous Code Block Context
Each code block should be independent:

```julia
# ❌ Wrong - assumes previous definitions
println("Exchange: $exchange_name")

# ✅ Correct - self-contained
exchange_name = "binance"
println("Exchange: $exchange_name")
```

### 3. Don't Use Hardcoded Paths
```julia
# ❌ Wrong - hardcoded paths
config = load_config("/path/to/config.toml")

# ✅ Correct - relative or example paths
config = load_config("examples/simple_strategy.toml")
```

### 4. Don't Ignore Error Handling
```julia
# ❌ Wrong - no error handling
data = fetch_ohlcv(exchange, tf"1h", "BTC/USDT")

# ✅ Correct - proper error handling
try
    data = fetch_ohlcv(exchange, tf"1h", "BTC/USDT")
    @info "Data fetched successfully"
catch e
    @warn "Fetch failed: $e"
end
```

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