# Documentation Testing Framework

This directory contains the automated testing and validation framework for Planar documentation.

## Components

### Core Testing Modules

- **`LinkValidator.jl`** - Module for validating internal and external links
- **`ContentConsistency.jl`** - Module for checking content consistency and formatting
- **`TestResultsReporter.jl`** - Module for generating test reports in various formats
- **`config_validator.jl`** - Configuration validation and default settings

### Configuration

- **`config.toml`** - Main configuration file for all testing options
- **`runtests.jl`** - Main test runner script

### Test Execution

The testing framework supports two main types of validation:

1. **Link Validation** - Checks that all internal and external links are valid and accessible
2. **Content Consistency** - Ensures consistent terminology, formatting, and style across documentation

For code example review, see the [AI Code Block Review Guide](../maintenance/ai-code-block-review-guide.md) for systematic manual review procedures.

## Usage

### Running All Tests

```bash
julia --project=Planar docs/test/runtests.jl
```

### Running Specific Test Types

```bash
# Link validation only  
julia --project=Planar docs/test/runtests.jl --skip-format

# Content consistency only
julia --project=Planar docs/test/runtests.jl --skip-links
```

### Configuration Options

The testing framework can be configured via `config.toml`:

- **Link Validation**: External link checking, timeout settings, skip patterns
- **Content Consistency**: Terminology rules, format preferences, severity levels
- **Reporting**: Output formats (HTML, JSON, summary), report locations

### CI Integration

The framework integrates with GitHub Actions via `.github/workflows/docs-validation.yml`:

- Runs on documentation changes
- Tests against multiple Julia versions
- Generates detailed reports
- Provides CI-friendly output

## Features

### Link Validation

- Validates internal relative links
- Checks external HTTP/HTTPS links
- Supports anchor link validation
- Configurable timeout and retry settings
- Batch processing for performance

### Content Consistency

- Terminology consistency checking
- Format validation (headings, code blocks, lists)
- Cross-reference validation
- Style guide compliance
- Configurable rules and severity levels

### Reporting

- HTML reports with detailed results
- JSON reports for programmatic access
- Summary reports for quick overview
- CI-friendly output formats
- Failure details and suggestions

## Implementation Status

✅ **Task 11.1: Add link validation and content consistency checking**
- Link validation for internal and external links
- Content consistency checking (terminology, format)
- Enhanced configuration system
- Comprehensive reporting framework
- Updated CI workflows

## Requirements Addressed

This implementation addresses the following requirements from the docs-improvement spec:

- **Requirement 10.1**: Format validation and consistency checking
- **Requirement 10.2**: Link validation and cross-reference checking

For code example validation, the [AI Code Block Review Guide](../maintenance/ai-code-block-review-guide.md) provides comprehensive procedures for manual review and consistency checking.

The framework ensures that documentation remains accurate, consistent, and up-to-date as the codebase evolves.