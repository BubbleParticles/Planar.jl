# Installation

This guide covers how to install Planar.

## Prerequisites

- Julia 1.11+
- Git

## Installation Steps

1. Clone the repository
2. Install dependencies
3. Run setup

See also: [Quick Start](quick-start.md)

Back to [main documentation](../index.md)

## Testing Your Installation

Once installed, you can test your setup with this simple Julia code:

```julia
# Test basic Julia functionality
println("Hello, Planar!")
x = 1 + 1
println("1 + 1 = $x")
```

You can also verify package loading:

```julia
using Pkg
Pkg.status()
```

## Example with Error (for testing)

This example will fail:

```julia
# This will cause an error
undefined_function()
```
