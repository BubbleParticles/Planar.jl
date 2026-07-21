# Documentation Quality Assurance System

This directory contains automated tools for ensuring the quality and consistency of the Planar documentation.

## Overview

The QA system consists of three main components:

1. **Link Validation** - Validates all internal and external links
2. **Code Example Testing** - Tests all Julia code examples for correctness
3. **Content Consistency Validation** - Ensures template compliance and style consistency

## Tools

### 1. Link Validator (`simple_link_validator.jl`)

Validates all internal links in the documentation to ensure they point to existing files.

**Features:**
- Scans all markdown files for internal links
- Validates file existence for relative and absolute paths
- Generates detailed reports with broken link locations
- Provides health score based on link validity

**Usage:**
```bash
julia docs/scripts/simple_link_validator.jl
```

### 1.1 Comprehensive Link Validator (`validate_links_final.jl`)

Advanced link validation tool that provides detailed analysis and improvement tracking.

**Features:**
- Validates both internal and external links
- Categorizes failures by type (internal vs external)
- Tracks improvement from baseline (original 502 failures)
- Provides comprehensive statistics and success rates
- Shows sample failures for debugging

**Usage:**
```bash
cd docs/scripts
julia validate_links_final.jl
```

### 1.2 Quick Link Check (`check_links.jl`)

Simplified link validation for quick checks during development.

**Usage:**
```bash
cd docs/scripts  
julia check_links.jl
```

**Output:**
- Console summary with health score
- Detailed text report at `docs/reports/link_validation_report.txt`

### 2. Code Example Review

Code examples are now reviewed using manual AI-guided procedures instead of automated testing. See `docs/maintenance/ai-code-block-review-guide.md` for comprehensive review procedures that ensure code quality while reducing maintenance overhead.

**Example Skipping:**
Code examples are automatically skipped if they contain:
- `# This is just an example`
- `# Not executable`
- `# Pseudo-code`
- `SomeHypotheticalFunction`

### 3. Content Consistency Validator (`content_consistency_validator.jl`)

Validates template compliance, style consistency, and content standards across all documentation.

**Features:**
- **Template Compliance**: Checks for required frontmatter fields
- **Heading Structure**: Validates proper heading hierarchy
- **Markdown Syntax**: Detects malformed links, unmatched backticks, etc.
- **Content Standards**: Ensures required sections in getting-started files
- **Style Consistency**: Checks for trailing whitespace, line length, etc.

**Usage:**
```bash
julia docs/scripts/content_consistency_validator.jl
```

**Output:**
- Console summary with consistency score
- Detailed text report at `docs/reports/content_consistency_report.txt`

**Validation Categories:**
- **Errors**: Critical issues that must be fixed (broken links, syntax errors)
- **Warnings**: Important issues that should be addressed (missing sections, template compliance)
- **Info**: Minor style issues for consideration (line length, whitespace)

## Makefile Integration

The QA tools are integrated into the documentation Makefile for easy execution:

```bash
# Run individual tools
make validate-links        # Link validation only
make test-code-examples    # Code example testing only
make validate-content      # Content consistency validation only

# Run all QA checks
make qa-all               # All quality assurance checks
```

## Reports

All tools generate reports in the `docs/reports/` directory:

- `link_validation_report.txt` - Link validation results
- `code_examples_test_report.txt` - Code example test results  
- `content_consistency_report.txt` - Content consistency validation results

## Continuous Integration

These tools can be integrated into CI/CD pipelines to ensure documentation quality:

```yaml
# Example GitHub Actions workflow
- name: Validate Documentation
  run: |
    julia docs/scripts/simple_link_validator.jl
    # Code examples use manual AI-guided review
    julia docs/scripts/content_consistency_validator.jl
```

## Configuration

### Link Validator Configuration

- `DOCS_ROOT`: Documentation source directory (default: `docs/src`)
- `REPORT_DIR`: Report output directory (default: `docs/reports`)

### Code Example Tester Configuration

- `DOCS_ROOT`: Documentation source directory
- `REPORT_DIR`: Report output directory
- `TEST_DIR`: Temporary directory for test execution (default: `docs/test_examples`)

### Content Validator Configuration

- `DOCS_ROOT`: Documentation source directory
- `REPORT_DIR`: Report output directory

## Best Practices

### For Documentation Authors

1. **Always specify language for code blocks:**
   ```markdown
   
   ```
   # Bad: No language specified
   println("Hello, World!")
   ```

2. **Add frontmatter to all pages:**
   ```yaml
   ---
   title: "Page Title"
   description: "Brief description of the page content"
   ---
   ```

3. **Use proper heading hierarchy:**
   ```markdown
   # Main Title (H1)
   ## Section (H2)
   ### Subsection (H3)
   #### Sub-subsection (H4)
   ```

4. **Mark non-executable examples:**

### For Maintainers

1. **Run QA checks before merging:**
   ```bash
   make qa-all
   ```

2. **Address errors immediately** - broken links and syntax errors should be fixed
3. **Consider warnings** - missing sections and template compliance improve user experience
4. **Monitor success rates** - aim for >90% link health and code example success rates

## Troubleshooting

### Common Issues

1. **"No markdown files found"**
   - Check that `DOCS_ROOT` points to the correct directory
   - Ensure markdown files exist in the specified location

2. **Code examples failing**
   - Verify Julia environment is properly set up
   - Check if examples require specific packages to be loaded
   - Consider marking non-executable examples appropriately

3. **Many broken links reported**
   - Verify file structure matches link references
   - Check for case sensitivity issues
   - Ensure relative paths are correct

### Performance Considerations

- Link validation may be slow for many external links
- Code example testing creates temporary files (automatically cleaned up)
- Large documentation sets may take several minutes to validate completely

## Future Enhancements

Potential improvements to the QA system:

1. **External Link Validation** - Check HTTP status of external links
2. **Image Validation** - Verify referenced images exist
3. **Cross-Reference Validation** - Ensure "See Also" sections are bidirectional
4. **Performance Monitoring** - Track documentation build and test times
5. **Integration Testing** - Test complete user journeys through documentation
6. **Accessibility Validation** - Check for accessibility compliance
7. **SEO Validation** - Verify meta descriptions, titles, and structure for search optimization