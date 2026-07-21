# Contributing to Planar Documentation

Thank you for your interest in improving the Planar documentation! This guide will help you contribute effectively and ensure your contributions align with our standards and processes.

## Quick Start for Contributors

1. **Fork the repository** and create a feature branch
2. **Review our style guide** and content standards below
3. **Make your changes** following our templates and guidelines
4. **Test your changes** using our validation tools
5. **Submit a pull request** with a clear description

## Types of Contributions

### 🐛 Bug Fixes
- Correcting factual errors
- Fixing broken links or code examples
- Resolving formatting issues
- Updating outdated information

### 📝 Content Improvements
- Clarifying confusing explanations
- Adding missing information
- Improving code examples
- Enhancing tutorials and guides

### ✨ New Content
- Writing new tutorials or guides
- Adding examples and use cases
- Creating troubleshooting content
- Expanding API documentation

### 🎨 Structure and Organization
- Improving navigation and cross-references
- Reorganizing content for better flow
- Enhancing templates and standards
- Optimizing user journeys

## Before You Start

### Check Existing Issues
- Review [open documentation issues](https://github.com/your-org/Planar.jl/issues?q=is%3Aissue+is%3Aopen+label%3Adocumentation)
- Check if someone is already working on your idea
- Comment on relevant issues to coordinate efforts

### Understand Our Users
Our documentation serves several user personas:
- **New Users**: Need guided onboarding and basic concepts
- **Strategy Developers**: Need development guides and examples
- **Advanced Users**: Need customization guides and API references
- **Troubleshooters**: Need quick problem resolution

### Review Our Standards
- Read our [Content Style Guide](#content-style-guide)
- Understand our [Template System](#template-system)
- Familiarize yourself with our [Review Process](#review-process)

## Content Style Guide

### Writing Style
- **Clear and Concise**: Use simple, direct language
- **Active Voice**: Prefer active over passive voice
- **Present Tense**: Use present tense for instructions
- **Consistent Terminology**: Use established terms consistently
- **Inclusive Language**: Write for a diverse, global audience

### Technical Writing Standards
- **Step-by-Step Instructions**: Break complex tasks into clear steps
- **Code Examples**: Include working, tested examples
- **Prerequisites**: Clearly state what users need before starting
- **Expected Outcomes**: Describe what success looks like
- **Error Handling**: Include common errors and solutions

### Formatting Guidelines
- **Headings**: Use hierarchical heading structure (H1 → H2 → H3)
- **Code Blocks**: Always specify language for syntax highlighting
- **Links**: Use descriptive link text, not "click here"
- **Lists**: Use bullet points for unordered items, numbers for sequences
- **Emphasis**: Use **bold** for UI elements, *italics* for emphasis

## Template System

All documentation follows standardized templates to ensure consistency. Choose the appropriate template for your content:

### Tutorial Template
Use for step-by-step learning content:

```markdown
---
title: "Tutorial Title"
description: "Brief description of what users will learn"
category: "getting-started" # or "guides"
difficulty: "beginner" # beginner|intermediate|advanced
prerequisites: ["installation", "basic-concepts"]
estimated_time: "15 minutes"
---

# Tutorial Title

Brief introduction explaining what this tutorial covers and why it's useful.

## Prerequisites
- [List required knowledge and setup]

## What You'll Learn
- [Specific learning objectives]

## Step 1: [Action]
[Detailed instructions with code examples]

## Step 2: [Action]
[Continue with clear progression]

## Verification
[How to confirm the tutorial worked]

## Next Steps
- [Related tutorials or concepts to explore]

## Troubleshooting
[Common issues specific to this tutorial]
```

### Reference Template
Use for API documentation and technical references:

```markdown
---
title: "Function/Concept Name"
description: "Brief description of functionality"
category: "reference"
---

# Function/Concept Name

Brief description of what this does and when to use it.

## Syntax

## Parameters
- `parameter1` (Type): Description of what this parameter does
- `parameter2` (Type): Description of what this parameter does
- `optional_param` (Type, optional): Description with default value

## Returns
Description of return value and type.

## Examples

### Basic Usage

### Advanced Usage

## Related Functions
- [`related_function`](link): Brief description
- [`another_function`](link): Brief description

## See Also
- [Related Tutorial](link): When to use this in practice
- [Concept Guide](link): Deeper explanation of underlying concepts
```

### Guide Template
Use for comprehensive explanations of concepts or workflows:

```markdown
---
title: "Guide Title"
description: "What this guide covers"
category: "guides"
difficulty: "intermediate"
prerequisites: ["prerequisite-concepts"]
---

# Guide Title

Overview of what this guide covers and who should read it.

## Overview
High-level explanation of the concept or workflow.

## Key Concepts
- **Term 1**: Definition and importance
- **Term 2**: Definition and importance

## Implementation
Detailed explanation with examples and best practices.

## Common Patterns
Typical use cases and recommended approaches.

## Best Practices
- [Specific recommendations]
- [Performance considerations]
- [Security considerations]

## Troubleshooting
Common issues and their solutions.

## Examples
Real-world examples and use cases.

## See Also
Links to related content and next steps.
```

## Code Example Standards

### Quality Requirements
- **Working Code**: All examples must execute successfully
- **Current Version**: Compatible with the latest Planar release
- **Complete Examples**: Include necessary imports and setup
- **Commented Code**: Explain non-obvious parts
- **Error Handling**: Show proper error handling where relevant

### Testing Your Examples
Before submitting, test your code examples:

```bash
# Review code examples using AI-guided procedures
# See docs/maintenance/ai-code-block-review-guide.md

# Or test manually in Julia REPL
julia --project=Planar
julia> # Paste your example code here
```

### Example Format

## Review Process

### Automated Checks
Your pull request will automatically run:
- **Link Validation**: Checks all internal and external links
- **Code Example Testing**: Validates all Julia code examples
- **Template Compliance**: Ensures proper formatting and structure
- **Style Checking**: Validates markdown formatting and style

### Human Review
Documentation maintainers will review for:
- **Technical Accuracy**: Correctness of information and examples
- **Clarity**: Ease of understanding for target audience
- **Completeness**: All necessary information is included
- **Consistency**: Alignment with existing content and standards
- **User Experience**: Effectiveness for intended user journeys

### Review Criteria
Your contribution will be evaluated on:

#### Content Quality
- [ ] Information is accurate and current
- [ ] Explanations are clear and well-organized
- [ ] Examples are practical and working
- [ ] Prerequisites are clearly stated
- [ ] Success criteria are defined

#### Technical Standards
- [ ] Code examples execute successfully
- [ ] Links are functional and appropriate
- [ ] Formatting follows style guidelines
- [ ] Frontmatter is complete and correct
- [ ] Template compliance is maintained

#### User Experience
- [ ] Content serves the intended audience
- [ ] Difficulty progression is appropriate
- [ ] Navigation and cross-references are helpful
- [ ] Integration with existing content is smooth

## Submission Guidelines

### Pull Request Process

1. **Create a Feature Branch**
   ```bash
   git checkout -b docs/your-improvement-description
   ```

2. **Make Your Changes**
   - Follow the appropriate template
   - Include proper frontmatter
   - Test all code examples
   - Validate links and references

3. **Test Your Changes**
   ```bash
   # Run validation tools
   scripts/check-links.sh
   # Use AI-guided code review (see maintenance/ai-code-block-review-guide.md)
   scripts/check-templates.sh
   ```

4. **Commit with Clear Messages**
   ```bash
   git commit -m "docs: improve strategy development guide with error handling examples"
   ```

5. **Submit Pull Request**
   - Use the PR template
   - Provide clear description of changes
   - Reference any related issues
   - Include screenshots for UI changes

### Pull Request Template

```markdown
## Description
Brief description of what this PR changes and why.

## Type of Change
- [ ] Bug fix (correcting errors or broken functionality)
- [ ] Content improvement (clarifying or enhancing existing content)
- [ ] New content (adding new documentation)
- [ ] Structure/organization (improving navigation or organization)

## Changes Made
- [Specific change 1]
- [Specific change 2]
- [Specific change 3]

## Testing
- [ ] All code examples tested and working
- [ ] Links validated
- [ ] Template compliance verified
- [ ] Automated checks passing

## User Impact
How will this change improve the user experience?

## Related Issues
Fixes #XXX
Related to #XXX

## Screenshots (if applicable)
[Include screenshots for visual changes]

## Checklist
- [ ] Content follows style guide
- [ ] Proper frontmatter included
- [ ] Code examples tested
- [ ] Links validated
- [ ] Appropriate template used
- [ ] Clear commit messages
```

## Community Guidelines

### Communication
- **Be Respectful**: Treat all contributors with respect and kindness
- **Be Constructive**: Provide helpful feedback and suggestions
- **Be Patient**: Remember that everyone has different experience levels
- **Be Collaborative**: Work together to improve the documentation

### Getting Help
- **GitHub Issues**: Ask questions or report problems
- **Discussions**: Join community discussions about documentation
- **Discord/Forums**: Get real-time help from the community
- **Direct Contact**: Reach out to maintainers for complex issues

### Recognition
We value all contributions and will:
- Credit contributors in release notes
- Highlight significant contributions in community updates
- Provide feedback and mentorship for new contributors
- Consider regular contributors for maintainer roles

## Advanced Contribution Topics

### Large-Scale Changes
For significant restructuring or major additions:
1. **Create an Issue First**: Discuss the proposal with maintainers
2. **Get Consensus**: Ensure the change aligns with project goals
3. **Plan the Implementation**: Break large changes into smaller PRs
4. **Coordinate with Team**: Work with maintainers on timing and approach

### Maintenance Contributions
Help with ongoing maintenance:
- **Content Reviews**: Participate in regular content audits
- **Link Checking**: Help identify and fix broken links
- **Example Updates**: Keep code examples current with new releases
- **User Feedback**: Help triage and respond to user feedback

### Translation and Localization
While not currently supported, we're interested in:
- Translation frameworks and processes
- Internationalization considerations
- Community interest in specific languages

## Tools and Resources

### Validation Tools
- `scripts/check-links.sh`: Validates all documentation links
- Manual AI-guided code review: See `docs/maintenance/ai-code-block-review-guide.md`
- `scripts/check-templates.sh`: Verifies template compliance
- `scripts/freshness-report.jl`: Analyzes content freshness

### Development Setup
```bash
# Clone the repository
git clone https://github.com/your-org/Planar.jl.git
cd Planar.jl

# Set up development environment
julia --project=Planar
julia> ] instantiate

# Run documentation locally (if applicable)
# [Instructions for local documentation server]
```

### Useful Resources
- [Markdown Guide](https://www.markdownguide.org/)
- [Julia Documentation](https://docs.julialang.org/)
- [Technical Writing Guidelines](https://developers.google.com/tech-writing)

## FAQ

### Q: How do I know if my contribution is needed?
A: Check existing issues, review the content freshness report, and look for gaps in user journeys. When in doubt, create an issue to discuss your idea.

### Q: What if I'm not sure about technical accuracy?
A: That's okay! Submit your contribution and note areas where you're uncertain. Our technical reviewers will help verify accuracy.

### Q: How long does the review process take?
A: Simple fixes are usually reviewed within a few days. Larger contributions may take 1-2 weeks depending on complexity and reviewer availability.

### Q: Can I contribute if I'm new to Planar?
A: Absolutely! Fresh perspectives are valuable, especially for getting-started content. Your questions and confusion points help us identify areas for improvement.

### Q: What if my PR is rejected?
A: We'll provide clear feedback on why changes are needed. Most rejections are due to minor issues that can be easily addressed. Don't be discouraged!

## Contact

- **Documentation Issues**: [GitHub Issues](https://github.com/your-org/Planar.jl/issues)
- **General Questions**: [Community Discord/Forum]
- **Maintainer Contact**: [Email or preferred contact method]

Thank you for helping make Planar's documentation better for everyone! 🚀