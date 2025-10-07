# Documentation Formatting Standards

This document defines the standardized formatting conventions for all Planar.jl documentation.

## Heading Structure

### Primary Headings (H1)
- Use for main page titles only
- Format: `# Page Title`
- Should be unique per page
- Use title case

### Section Headings (H2)
- Use for major sections
- Format: `## Section Name`
- Use title case
- Leave one blank line before and after

### Subsection Headings (H3)
- Use for subsections within major sections
- Format: `### Subsection Name`
- Use title case
- Leave one blank line before and after

### Sub-subsection Headings (H4)
- Use sparingly for detailed breakdowns
- Format: `#### Sub-subsection Name`
- Use title case
- Leave one blank line before and after

## Code Formatting

### Inline Code
- Use backticks for inline code: `code_here`
- Use for function names, variable names, file paths, and short code snippets

### Code Blocks
- Use triple backticks with language specification
- Always specify language: ```julia, ```bash, ```toml, etc.
- Include descriptive comments for complex examples
- Keep examples concise but complete

### Code Block Examples

## Lists and Structure

### Unordered Lists
- Use `-` for bullet points (not `*` or `+`)
- Maintain consistent indentation (2 spaces per level)
- Leave blank line before and after lists
- Use parallel structure in list items

### Ordered Lists
- Use `1.` format for numbered lists
- Let markdown auto-number subsequent items
- Use for step-by-step procedures
- Include verification steps where applicable

### Definition Lists
- Use **Bold Term**: Description format
- Align descriptions consistently
- Group related terms together

## Cross-References and Links

### Internal Links
- Use relative paths: `[Strategy Guide](strategy.md)`
- Include section anchors: `[Backtesting](engine/backtesting.md#configuration)`
- Verify all links are functional

### External Links
- Use descriptive link text (not "click here")
- Open external links in new tabs when appropriate
- Include brief context for external resources

### API References
- Use consistent format: [`Function.name`](@ref)
- Link to relevant API documentation
- Include module context when needed

## Content Structure

### Page Introduction
- Start with brief overview paragraph
- Include prerequisites when applicable
- Provide navigation hints for complex topics

### Examples and Code Samples
- Include complete, runnable examples
- Provide expected output when relevant
- Add troubleshooting notes for common issues
- Use realistic data and scenarios

### Admonitions and Callouts
- Use consistent formatting for warnings, tips, notes
- Place at logical points in content flow
- Keep concise and actionable

## Formatting Conventions

### Emphasis
- Use **bold** for important terms and UI elements
- Use *italics* for emphasis and foreign terms
- Use `code formatting` for technical terms

### Tables
- Include headers for all tables
- Align columns consistently
- Use tables for comparison data
- Keep table content concise

### Images and Assets
- Use descriptive alt text
- Include captions when helpful
- Optimize image sizes for web
- Store in `docs/src/assets/` directory

## Language and Style

### Tone
- Use clear, direct language
- Write in active voice when possible
- Address the reader directly ("you")
- Maintain professional but approachable tone

### Technical Terms
- Define technical terms on first use
- Maintain consistent terminology throughout
- Use glossary for complex concepts
- Provide context for Julia-specific concepts

### Code Comments
- Include explanatory comments in code examples
- Explain non-obvious logic
- Provide context for parameter choices
- Use consistent comment style

## File Organization

### File Naming
- Use kebab-case for file names
- Use descriptive, specific names
- Group related files in directories
- Maintain consistent naming patterns

### Directory Structure
- Follow logical hierarchy
- Group related content together
- Use clear directory names
- Maintain parallel structure across sections

## Quality Assurance

### Content Review Checklist
- [ ] All headings follow hierarchy rules
- [ ] Code examples are tested and functional
- [ ] Links are verified and working
- [ ] Formatting is consistent throughout
- [ ] Language is clear and accessible
- [ ] Examples use realistic scenarios
- [ ] Cross-references are accurate
- [ ] Images have appropriate alt text

### Validation Steps
1. Run spell check
2. Verify all code examples
3. Test all internal and external links
4. Check formatting consistency
5. Review for clarity and completeness