# Documentation Templates

This directory contains standardized templates for creating consistent documentation across the Planar project.

## Available Templates

### Tutorial Template (`tutorial-template.md`)
Use for step-by-step learning content in the `getting-started/` section.

**Key Features:**
- Clear learning objectives
- Prerequisites section
- Step-by-step instructions with code examples
- Verification steps
- Troubleshooting section

### Guide Template (`guide-template.md`)
Use for comprehensive topic coverage in the `guides/` section.

**Key Features:**
- Overview and core concepts
- Practical examples
- Best practices and patterns
- Performance considerations
- Advanced topics links

### Reference Template (`reference-template.md`)
Use for API documentation and function references in the `reference/` section.

**Key Features:**
- Function syntax and parameters
- Multiple usage examples
- Related functions
- Cross-references to guides

### Troubleshooting Template (`troubleshooting-template.md`)
Use for problem-solution content in the `troubleshooting/` section.

**Key Features:**
- Quick diagnostics
- Symptom-cause-solution format
- Platform-specific issues
- Prevention tips

## Using Templates

1. **Copy the appropriate template** to your target location
2. **Rename the file** to match your content
3. **Fill in the frontmatter** with accurate metadata
4. **Replace template content** with your actual content
5. **Validate using the validation script**

## Frontmatter Requirements

All documentation files must include YAML frontmatter with these fields:

### Required for All Categories
- `title`: Clear, descriptive title
- `description`: Brief description for search/navigation
- `category`: One of: getting-started, guides, advanced, reference, troubleshooting, resources
- `last_updated`: Date in YYYY-MM-DD format

### Category-Specific Requirements

#### Getting Started & Guides
- `difficulty`: beginner, intermediate, or advanced
- `prerequisites`: Array of prerequisite topics
- `estimated_time`: Format like "15 minutes" or "1 hour"

#### Reference
- `estimated_time`: Quick reference time

#### Troubleshooting
- `difficulty`: Usually "beginner"
- `estimated_time`: Time to resolve issue

### Optional Fields
- `related_topics`: Array of related topic slugs
- `prerequisites`: Array of prerequisite topics (if applicable)

## Validation

Use the validation script to ensure your documentation follows the templates:

```bash
# Validate a single file
julia docs/templates/validate-template.jl docs/src/guides/my-guide.md

# Validate entire directory
julia docs/templates/validate-template.jl docs/src/guides/

# Validate all documentation
julia docs/templates/validate-template.jl docs/src/
```

## Content Guidelines

### Writing Style
- Use clear, concise language
- Write in second person ("you")
- Use active voice
- Include working code examples
- Test all code examples

### Structure
- Follow the template structure
- Use consistent heading levels
- Include cross-references
- Add "See Also" sections

### Code Examples
- Include necessary imports
- Use realistic examples
- Add comments explaining key concepts
- Test examples with current Planar version

### Links
- Use relative links for internal content
- Link to related concepts
- Include troubleshooting links where relevant
- Verify all links work

## Template Updates

When updating templates:

1. Update the template file
2. Update this README if needed
3. Update the validation script if new requirements are added
4. Communicate changes to documentation contributors