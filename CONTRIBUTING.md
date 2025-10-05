# Contributing to Planar.jl

Thank you for your interest in contributing to Planar.jl! This document provides guidelines for contributing to the project, with special attention to documentation standards.

## Getting Started

1. Fork the repository
2. Clone your fork with submodules:
   ```bash
   git clone --recurse-submodules https://github.com/yourusername/Planar.jl
   cd Planar.jl
   direnv allow
   ```
3. Set up the development environment:
   ```bash
   julia --project=Planar
   ] instantiate
   ```

## Types of Contributions

### Code Contributions
- Bug fixes
- New features
- Performance improvements
- Test coverage improvements

### Documentation Contributions
- Fixing errors in existing documentation
- Adding new guides and tutorials
- Improving code examples
- Updating API documentation

### Other Contributions
- Reporting bugs
- Suggesting features
- Improving CI/CD
- Community support

## Documentation Standards

### Code Block Requirements

All code blocks in documentation must follow these standards to ensure they pass the automated testing suite:

#### 1. Self-Contained Examples
Every code block should be executable independently:

```julia
# ✅ Good - includes all necessary imports
using Planar
using TimeTicks

# Your example code here
```

#### 2. Project Activation
When using different Planar modules, explicitly activate the correct project:

```julia
# For basic Planar features
import Pkg
Pkg.activate("Planar")
using Planar

# For interactive features (plotting, optimization)
import Pkg
Pkg.activate("PlanarInteractive")
using PlanarInteractive
@environment!
```

#### 3. Variable Definitions
Define all variables used in examples:

```julia
# ✅ Good - variables are defined
exchange_name = "binance"
pair = "BTC/USDT"
timeframe = tf"1h"

# Use variables in your example
@info "Fetching data for $pair from $exchange_name"
```

#### 4. Error Handling
Include appropriate error handling for robustness:

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

#### 5. Module Scoping
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

### Testing Documentation

Before submitting documentation changes:

1. **Test individual code blocks**:
   ```bash
   julia --project=Planar -e "
   # Paste your code block here to test it
   "
   ```

2. **Run the full documentation test suite**:
   ```bash
   julia --project=Planar docs/test/runtests.jl --skip-external --verbose
   ```

3. **Check for common issues**:
   - All imports are included
   - Variables are defined before use
   - Realistic example values are used
   - Error handling is appropriate
   - Code blocks are properly scoped

### Documentation Guidelines Reference

For detailed guidelines on writing testable documentation, see:
- [Documentation Code Block Guidelines](docs/DOCUMENTATION_CODE_BLOCK_GUIDELINES.md)

## Code Style

### Julia Code
- Follow [Blue Style](https://github.com/invenia/BlueStyle) formatting
- Use JuliaFormatter with the project's `.JuliaFormatter.toml`
- Maximum line length: 92 characters
- Use descriptive variable names
- Add docstrings for public functions

### Documentation
- Use clear, concise language
- Include working code examples
- Add proper frontmatter to documentation files:
  ```yaml
  ---
  title: "Clear, descriptive title"
  description: "1-2 sentence summary"
  category: "getting-started|guides|advanced|reference|troubleshooting"
  difficulty: "beginner|intermediate|advanced"
  ---
  ```

## Submission Process

### Pull Request Guidelines

1. **Create a feature branch**:
   ```bash
   git checkout -b feature/your-feature-name
   # or
   git checkout -b docs/your-documentation-improvement
   ```

2. **Make your changes**:
   - Follow the coding standards
   - Add tests for new functionality
   - Update documentation as needed
   - Test your changes thoroughly

3. **Commit with conventional format**:
   ```bash
   git commit -m "feat: add new strategy optimization feature"
   git commit -m "docs: improve data management guide with error handling"
   git commit -m "fix: resolve import conflicts in strategy examples"
   ```

4. **Submit pull request**:
   - Use a clear, descriptive title
   - Include a detailed description of changes
   - Reference any related issues
   - Ensure all tests pass

### PR Review Process

1. Automated checks must pass:
   - Code formatting (JuliaFormatter)
   - Documentation tests
   - Unit tests
   - Integration tests

2. Manual review focuses on:
   - Code quality and design
   - Documentation clarity
   - Test coverage
   - Breaking changes

3. Address review feedback promptly

## Development Setup

### Environment Variables
Check and configure the environment variables in `.envrc`:
```bash
export JULIA_PROJECT=Planar  # or PlanarInteractive
export JULIA_NUM_THREADS=auto
# ... other variables
```

### Testing
Run tests before submitting:
```bash
# Unit tests
julia --project=Planar -e "using Pkg; Pkg.test()"

# Documentation tests
julia --project=Planar docs/test/runtests.jl

# Integration tests (if applicable)
julia --project=Planar test/integration/runtests.jl
```

### Building Documentation
To build documentation locally:
```bash
julia --project=docs docs/make.jl
```

## Community Guidelines

### Code of Conduct
- Be respectful and inclusive
- Focus on constructive feedback
- Help newcomers learn and contribute
- Maintain a professional tone in all interactions

### Getting Help
- Check existing documentation and issues first
- Use GitHub Discussions for questions
- Join the Discord server for real-time help
- Tag maintainers only when necessary

### Reporting Issues
When reporting bugs:
1. Use the issue template
2. Include minimal reproduction steps
3. Provide system information
4. Include relevant logs/error messages

## Recognition

Contributors are recognized in:
- Git commit history
- Release notes for significant contributions
- Documentation acknowledgments
- Community highlights

## Questions?

If you have questions about contributing:
- Check the [documentation](https://defnlnotme.github.io/Planar.jl/)
- Open a GitHub Discussion
- Join our Discord server
- Review existing issues and PRs

Thank you for contributing to Planar.jl!