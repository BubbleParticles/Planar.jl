# AI Agent Code Block Review Guide

This guide provides instructions for AI agents to systematically review code blocks in documentation for consistency, accuracy, and best practices.

## Overview

Code blocks in documentation serve as examples, tutorials, and reference implementations. They must be:
- **Accurate**: Work correctly with the current version of Planar
- **Consistent**: Follow established patterns and conventions
- **Complete**: Include necessary imports and setup
- **Educational**: Demonstrate best practices and clear concepts

## Review Process

### 1. Initial Assessment

For each documentation file containing code blocks:

1. **Identify all Julia code blocks** (marked with ```julia)
2. **Categorize by purpose**:
   - Tutorial examples (step-by-step learning)
   - Reference examples (API demonstration)
   - Configuration examples (setup and configuration)
   - Advanced examples (complex use cases)

### 2. Consistency Checks

#### Import and Setup Patterns
- **Standard imports**: Verify consistent use of `using Planar` vs `using PlanarInteractive`
- **Project activation**: Check for proper project setup patterns
- **Environment loading**: Ensure `@environment!` macro usage is consistent

```julia
# Preferred pattern for basic examples
using Planar

# Preferred pattern for interactive examples
using PlanarInteractive
@environment!
```

#### Naming Conventions
- **Variables**: Use descriptive, consistent names (`strategy`, `exchange`, `config`)
- **Functions**: Follow Julia conventions (snake_case for variables, CamelCase for types)
- **Constants**: Use UPPER_CASE for configuration constants

#### Code Structure
- **Indentation**: Consistent 4-space indentation
- **Line length**: Respect 92-character limit (JuliaFormatter Blue style)
- **Comments**: Clear, helpful comments that explain non-obvious concepts

### 3. Technical Accuracy Review

#### Version Compatibility
- **API calls**: Verify all function calls match current Planar API
- **Module structure**: Ensure imports reflect current module organization
- **Deprecated features**: Flag any usage of deprecated functions or patterns

#### Completeness
- **Required imports**: All necessary modules are imported
- **Setup code**: Configuration objects are properly initialized
- **Error handling**: Appropriate error handling for examples that might fail

#### Planar-Specific Patterns
- **Exchange configuration**: Proper exchange setup with API keys handling
- **Strategy definition**: Consistent strategy structure and inheritance
- **Data handling**: Correct OHLCV data access and manipulation patterns
- **Mode switching**: Proper demonstration of SimMode/PaperMode/LiveMode usage

### 4. Educational Value Assessment

#### Clarity
- **Progressive complexity**: Examples build from simple to complex
- **Explanatory comments**: Code includes helpful explanations
- **Context**: Examples include sufficient context to understand purpose

#### Best Practices
- **Security**: No hardcoded API keys or sensitive information
- **Performance**: Examples demonstrate efficient patterns
- **Error handling**: Show proper error handling techniques
- **Resource management**: Demonstrate proper cleanup and resource management

## Common Issues to Flag

### Critical Issues (Must Fix)
- **Syntax errors**: Code that won't parse or run
- **Import errors**: Missing or incorrect module imports
- **API mismatches**: Calls to non-existent or changed functions
- **Security vulnerabilities**: Exposed credentials or unsafe practices

### Consistency Issues (Should Fix)
- **Mixed import styles**: Inconsistent use of import patterns
- **Variable naming**: Inconsistent naming conventions
- **Code formatting**: Deviations from JuliaFormatter standards
- **Comment style**: Inconsistent comment formatting

### Enhancement Opportunities (Nice to Have)
- **Missing examples**: Gaps in coverage of important features
- **Outdated patterns**: Code using old but still functional approaches
- **Performance improvements**: Opportunities to demonstrate better patterns
- **Educational improvements**: Ways to make examples clearer

## Review Checklist

For each code block, verify:

- [ ] **Syntax**: Code parses without errors
- [ ] **Imports**: All required modules are imported correctly
- [ ] **Compatibility**: Code works with current Planar version
- [ ] **Completeness**: Example includes all necessary setup
- [ ] **Consistency**: Follows established patterns and conventions
- [ ] **Security**: No exposed credentials or unsafe practices
- [ ] **Comments**: Adequate explanatory comments
- [ ] **Formatting**: Follows JuliaFormatter Blue style
- [ ] **Context**: Sufficient context for understanding
- [ ] **Best practices**: Demonstrates recommended approaches

## Reporting Format

When reporting issues, use this format:

```markdown
## Code Block Review: [File Path]

### Summary
- Total code blocks: X
- Issues found: Y
- Critical issues: Z

### Issues by Category

#### Critical Issues
- **[File:Line]**: Description of issue
  - **Problem**: What's wrong
  - **Impact**: Why it matters
  - **Suggestion**: How to fix

#### Consistency Issues
- **[File:Line]**: Description of issue
  - **Current**: What it currently shows
  - **Preferred**: What it should show
  - **Reason**: Why the change improves consistency

#### Enhancement Opportunities
- **[File:Line]**: Description of opportunity
  - **Current**: Current approach
  - **Enhancement**: Suggested improvement
  - **Benefit**: Why the improvement helps users
```

## Integration with Planar Ecosystem

### Module Awareness
- **Core modules**: Engine, Strategies, Exchanges, Executors
- **Data modules**: Data, Fetch, Processing, Metrics
- **Utility modules**: Collections, Misc, Lang, TimeTicks
- **Interactive modules**: Plotting, Opt, PlanarInteractive

### Configuration Patterns
- **User directory**: Examples should reference `user/` directory structure
- **Configuration files**: Proper use of `planar.toml` and `secrets.toml`
- **Strategy organization**: Both file-based and package-based approaches

### Common Planar Patterns
- **Strategy lifecycle**: Initialization, execution, cleanup
- **Data pipeline**: Fetching, processing, storage, retrieval
- **Exchange interaction**: Authentication, API calls, error handling
- **Mode transitions**: Moving between simulation, paper, and live trading

## Automation Considerations

While this guide is designed for AI agents, consider these automation opportunities:

- **Syntax checking**: Automated parsing and compilation checks
- **Import validation**: Verify all imports resolve correctly
- **Pattern matching**: Automated detection of common anti-patterns
- **Consistency scoring**: Metrics for measuring consistency across examples

## Maintenance

This guide should be updated when:
- Planar API changes significantly
- New modules or patterns are introduced
- Documentation standards evolve
- Common issues patterns emerge from reviews

---

*This guide is part of the Planar documentation maintenance system. For questions or improvements, see the main documentation contribution guidelines.*