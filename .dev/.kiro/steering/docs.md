---
inclusion: always
---

# Documentation Guidelines

## Content Standards

### Writing Style
- Use clear, concise language with active voice and present tense
- Write for diverse user personas: new users, strategy developers, advanced users, troubleshooters
- Include step-by-step instructions with prerequisites and expected outcomes
- Provide working, tested code examples with proper error handling

### Code Examples
- All Julia code must execute successfully and be compatible with current Planar version
- Include necessary imports and setup: `using Planar`, configuration objects
- Add clear comments explaining non-obvious parts
- Test examples with: `julia scripts/validate-examples.jl`
- Follow JuliaFormatter standards: Blue style, 92 character margin

### Frontmatter Requirements
All documentation files must include YAML frontmatter:
```yaml
---
title: "Clear, descriptive title"
description: "1-2 sentence summary"
category: "getting-started|guides|advanced|reference|troubleshooting"
difficulty: "beginner|intermediate|advanced"  # optional
prerequisites: ["installation", "basic-concepts"]  # optional
---
```

## Template System

### Tutorial Template
For step-by-step learning content with prerequisites, learning objectives, verification steps, and troubleshooting sections.

### Reference Template  
For API documentation with syntax, parameters, returns, examples, and related functions.

### Guide Template
For comprehensive concept explanations with overview, key concepts, implementation details, and best practices.

## File Organization

### Documentation Structure
- `docs/src/`: Main documentation source files
- `docs/templates/`: Standardized content templates
- `docs/scripts/`: Documentation build and validation tools
- User guides in appropriate category subdirectories

### Validation Tools
- `scripts/check-links.sh`: Validates all documentation links
- `scripts/validate-examples.jl`: Tests Julia code examples  
- `scripts/check-templates.sh`: Verifies template compliance
- `scripts/freshness-report.jl`: Analyzes content currency

## Contribution Process

### Before Contributing
- Check existing issues and coordinate with maintainers
- Review content style guide and template requirements
- Understand target user personas and their needs

### Submission Requirements
- Follow conventional commit format: `docs: improve strategy guide with error handling`
- Test all code examples and validate links before submission
- Include clear PR description with type of change and user impact
- Use feature branch: `docs/your-improvement-description`

### Review Criteria
- Technical accuracy and working examples
- Clarity for intended audience and proper template compliance
- Integration with existing content and navigation
- Automated checks passing (links, examples, formatting)

## Planar-Specific Conventions

### Module References
- Reference Planar modules using proper hierarchy: `Engine`, `Strategies`, `Exchanges`
- Use `@environment!` macro examples for module loading
- Include project activation: `julia --project=Planar` or `julia --project=PlanarInteractive`

### Configuration Examples
- Show proper configuration setup with exchange and mode specification
- Include user directory structure references: `user/planar.toml`, `user/strategies/`
- Demonstrate both simple file-based and package-based strategy organization

### Cross-References
- Link to related modules and concepts using descriptive link text
- Reference validation tools and build scripts appropriately
- Include troubleshooting sections with common Planar-specific issues