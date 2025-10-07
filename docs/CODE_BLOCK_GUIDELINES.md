# Code Block Usage Guidelines

## Overview

This document establishes clear criteria for when to include Julia code blocks in Planar documentation. The goal is to maintain essential functionality examples while dramatically reducing maintenance overhead.

## Target Metrics

- **Total code blocks**: Maximum 50 across all documentation
- **Per-package limit**: 2-5 code blocks for most packages
- **Core packages**: Maximum 5-8 code blocks for user-facing packages (Planar, PlanarInteractive)

## Tier System

### Tier 1 - Essential (Always Keep)

**Module Loading Examples**:
- `using Planar` and `@environment!` patterns
- Basic strategy creation and configuration
- Exchange setup and connection

**Error Handling Patterns**:
- Critical error handling for common failures
- Connection resilience and retry logic
- Data validation and quality checks

**Exchange Configuration**:
- API credentials and authentication
- Rate limiting and timeout configuration
- Multi-exchange setup patterns

**Strategy Creation**:
- Basic strategy template and structure
- Core dispatch patterns (`call!` methods)
- Essential trading logic examples

### Tier 2 - Remove (Redundant)

**Simple Output Examples**:
- `println()` and `display()` statements
- Basic variable assignments
- Simple data access patterns

**Multiple Similar Examples**:
- Variations of the same API call
- Different parameter combinations for the same function
- Duplicate examples showing identical concepts

**Reference-Only Content**:
- Simple syntax demonstrations
- Parameter listings without execution context
- Configuration examples better shown as TOML/YAML

### Tier 3 - Convert to Text

**Simple Syntax**:
- Function signatures and type definitions
- Basic usage patterns that don't require execution
- Error messages and warnings

## Decision Criteria

### When to Include a Code Block

1. **Demonstrates core functionality** that users need to understand
2. **Shows proper error handling** for critical operations
3. **Provides essential setup** or configuration patterns
4. **Cannot be adequately explained** with inline code or text

### When to Remove a Code Block

1. **Duplicates existing examples** with minor variations
2. **Shows trivial operations** like simple assignments
3. **Demonstrates obvious usage** that doesn't need execution
4. **Can be replaced** with inline code or descriptive text

### When to Convert to Inline Code

1. **Simple syntax examples** like `using Package`
2. **Function signatures** and type definitions
3. **Configuration values** and parameter settings
4. **Error messages** and status outputs

## Package-Specific Guidelines

### Core Packages (3-5 blocks max)
- **Engine**: Strategy loading, data access, execution modes
- **Strategies**: Basic strategy structure, dispatch patterns
- **Exchanges**: Connection setup, error handling

### Utility Packages (1-2 blocks max)
- **Collections, Misc, Lang**: Only most essential usage
- **TimeTicks**: Basic timeframe operations
- **Instruments**: Core asset definitions

### Specialized Packages (2-3 blocks max)
- **Plotting**: Backend setup, basic chart creation
- **Optimization**: Configuration and execution
- **Watchers**: Setup and lifecycle management

### User-Facing Packages (5-8 blocks max)
- **Planar**: Module loading, basic usage, getting started
- **PlanarInteractive**: Setup, plotting integration

## Content Type Distribution

### Getting Started (15-20 blocks total)
- Installation and setup
- First strategy creation
- Basic usage patterns

### API Reference (10-15 blocks total)
- Core function usage
- Essential patterns for each module
- Error handling examples

### Advanced Guides (10-15 blocks total)
- Complex workflows
- Integration patterns
- Performance optimization

### Troubleshooting (5-10 blocks total)
- Common error resolution
- Debugging techniques
- Performance issues

## Review Process

### For New Documentation

1. **Justify each code block** against the tier system
2. **Check for existing examples** that cover the same concept
3. **Consider inline alternatives** for simple syntax
4. **Ensure essential functionality** is demonstrated

### For Existing Documentation

1. **Audit against guidelines** using the tier system
2. **Remove redundant examples** that don't add value
3. **Consolidate similar patterns** into single examples
4. **Convert simple syntax** to inline code

## Maintenance

### Regular Audits

- **Quarterly review** of code block counts per package
- **Validation runs** to ensure examples remain functional
- **User feedback analysis** to identify missing essential examples

### Contribution Guidelines

- **New code blocks** must be justified against tier system
- **Existing examples** should be updated rather than duplicated
- **Simple syntax** should use inline code format
- **Complex examples** should include error handling

## Tools

### Scanning Script
Use `scripts/scan-code-blocks.jl` to:
- Count current code blocks by file and category
- Identify files exceeding package limits
- Track progress toward reduction targets

### Validation
- Run existing validation scripts on reduced set
- Ensure essential functionality remains covered
- Monitor success rates and execution time

## Examples

### Good: Essential Module Loading

### Good: Essential Error Handling

### Bad: Redundant Simple Output

### Convert to Inline: Simple Syntax
Instead of a code block, use inline: `Strategy{Mode, Name, Exchange, Margin, QuoteCurrency}`

## Enforcement

- **Automated checks** in CI/CD to prevent code block proliferation
- **Review requirements** for documentation changes
- **Regular audits** to maintain compliance with guidelines
- **Clear rejection criteria** for unnecessary code blocks