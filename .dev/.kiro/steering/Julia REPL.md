---
inclusion: always
---

# Julia REPL Guidelines

## Session Management
- **Persistent sessions**: Always use a single Julia REPL session and reuse it instead of spawning new processes
- **Project activation**: Start with correct project environment:
  - `julia --project=Planar` for core functionality
  - `julia --project=PlanarInteractive` for plotting/optimization features
- **Environment loading**: Use `@environment!` macro to load Planar modules into scope
- **Session recovery**: If REPL becomes unresponsive, restart and re-activate project environment

## REPL Modes and Navigation
- **Package mode**: `]` for dependency management (`instantiate`, `add`, `remove`, `status`)
- **Help mode**: `?` for function/type documentation
- **Shell mode**: `;` for system commands (check `pwd` before running scripts)
- **Search mode**: `Ctrl+R` for command history search

## Development Workflow
- **Module reloading**: Use `Revise.jl` for automatic code reloading during development
- **Strategy testing**: Load strategies with `using` and test interactively
- **Data inspection**: Use `first()`, `last()`, `size()` for DataFrame/array exploration
- **Memory management**: Call `GC.gc()` if memory usage becomes excessive

## Planar-Specific Patterns
- **Module loading**: Follow Planar's hierarchical module structure
- **Strategy development**: Test strategies in REPL before running full backtests
- **Exchange testing**: Use paper mode for safe API testing
- **Data pipeline**: Test data fetching and processing incrementally

## Performance and Debugging
- **Compilation time**: Allow initial startup for precompilation (especially with sysimage)
- **Type stability**: Use `@code_warntype` to check for type instabilities
- **Profiling**: Use `@time`, `@benchmark` for performance analysis
- **Error inspection**: Julia stack traces provide detailed error context - read them carefully
- **Workspace inspection**: Use `varinfo()` or `names(Main)` to see loaded variables/modules

## Common Commands
```julia
# Load Planar environment
@environment!

# Check loaded modules
names(Main)

# Memory usage
varinfo()

# Force garbage collection
GC.gc()

# Package operations
] status
] instantiate
```