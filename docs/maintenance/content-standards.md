# Content Standards and Templates

This document defines the standards, templates, and guidelines for creating and maintaining Planar documentation. All contributors should follow these standards to ensure consistency and quality.

## Content Categories

### Getting Started
**Purpose**: Guide new users from installation to first success  
**Audience**: Complete beginners to Planar  
**Tone**: Encouraging, step-by-step, assumes no prior knowledge  
**Success Criteria**: User can complete tasks independently

### Guides  
**Purpose**: Explain concepts and workflows in depth  
**Audience**: Users with basic Planar knowledge  
**Tone**: Educational, comprehensive, practical  
**Success Criteria**: User understands concepts and can apply them

### Advanced
**Purpose**: Cover complex topics and customization  
**Audience**: Experienced users and developers  
**Tone**: Technical, detailed, assumes expertise  
**Success Criteria**: User can implement advanced features

### Reference
**Purpose**: Provide complete API and configuration documentation  
**Audience**: All users looking up specific information  
**Tone**: Precise, comprehensive, searchable  
**Success Criteria**: User finds exact information needed

### Troubleshooting
**Purpose**: Help users resolve problems quickly  
**Audience**: Users encountering specific issues  
**Tone**: Solution-focused, systematic, empathetic  
**Success Criteria**: User resolves their problem

## Writing Standards

### Language and Style

#### Voice and Tone
- **Active Voice**: "Configure the strategy" not "The strategy should be configured"
- **Present Tense**: "The function returns" not "The function will return"
- **Direct Address**: "You can configure" not "One can configure"
- **Positive Framing**: "To enable this feature" not "To avoid disabling this feature"

#### Clarity Guidelines
- **One Concept per Sentence**: Keep sentences focused and clear
- **Parallel Structure**: Use consistent grammatical patterns in lists
- **Specific Language**: "Set timeout to 30 seconds" not "Set a reasonable timeout"
- **Avoid Jargon**: Define technical terms or link to definitions

#### Inclusive Language
- **Gender Neutral**: Use "they/them" or rephrase to avoid gendered pronouns
- **Accessible Examples**: Use diverse names and scenarios in examples
- **Plain Language**: Avoid unnecessarily complex vocabulary
- **Cultural Sensitivity**: Avoid idioms and cultural references that may not translate

### Technical Writing Principles

#### Structure and Organization
- **Logical Flow**: Information builds from simple to complex
- **Scannable Format**: Use headings, lists, and white space effectively
- **Consistent Patterns**: Similar content follows similar organization
- **Clear Hierarchy**: Heading levels reflect information importance

#### Code and Examples
- **Working Code**: All examples must execute successfully
- **Complete Context**: Include necessary imports and setup
- **Realistic Examples**: Use practical, real-world scenarios
- **Error Handling**: Show proper error handling patterns
- **Comments**: Explain non-obvious code sections

#### Links and References
- **Descriptive Link Text**: "See the configuration guide" not "click here"
- **Contextual Links**: Link to relevant information when concepts are introduced
- **Current Links**: Regularly validate and update all links
- **Appropriate Scope**: Link to the most specific relevant section

## Template Specifications

### Frontmatter Standards

All documentation files must include YAML frontmatter with these fields:

```yaml
---
title: "Page Title"                    # Required: Clear, descriptive title
description: "Brief page description"   # Required: 1-2 sentence summary for search/navigation
category: "getting-started"            # Required: One of the five main categories
difficulty: "beginner"                 # Optional: beginner|intermediate|advanced
prerequisites: ["installation"]        # Optional: Array of prerequisite topics
related_topics: ["strategy-dev"]       # Optional: Array of related topics  
last_updated: "2024-01-15"            # Optional: Date of last significant update (YYYY-MM-DD)
estimated_time: "15 minutes"          # Optional: Expected completion time for tutorials
tags: ["backtesting", "strategies"]    # Optional: Array of searchable tags
---
```

#### Field Specifications

**title**: 
- Use title case
- Be specific and descriptive
- Avoid redundant words like "Guide" or "Tutorial" (category indicates this)
- Maximum 60 characters for SEO

**description**:
- 1-2 sentences maximum
- Explain what the user will learn or accomplish
- Use active voice and present tense
- Include key terms for searchability

**category**:
- Must be one of: `getting-started`, `guides`, `advanced`, `reference`, `troubleshooting`
- Determines navigation placement and user expectations

**difficulty**:
- `beginner`: No prior Planar knowledge required
- `intermediate`: Basic Planar concepts understood
- `advanced`: Significant Planar experience assumed

**prerequisites**:
- List specific topics/pages user should understand first
- Use the same naming as the actual file/section names
- Keep list minimal - only true prerequisites

**estimated_time**:
- Realistic estimate for average user
- Include time for reading, coding, and testing
- Use format: "X minutes" or "X hours"

### Tutorial Template

Use for step-by-step learning content in `getting-started/` and `guides/`:

```markdown
---
title: "Tutorial Title"
description: "What the user will learn and accomplish"
category: "getting-started"
difficulty: "beginner"
prerequisites: ["installation", "basic-concepts"]
estimated_time: "20 minutes"
---

# Tutorial Title

Brief introduction (2-3 sentences) explaining:
- What this tutorial covers
- Why it's useful or important
- What the user will accomplish

## Prerequisites

Before starting this tutorial, make sure you have:
- [Specific requirement with link if needed]
- [Another requirement]
- [Basic knowledge requirement]

## What You'll Learn

By the end of this tutorial, you will be able to:
- [Specific, measurable learning objective]
- [Another objective]
- [Final objective]

## Overview

[Optional: Brief overview of the process or concept being taught]

## Step 1: [Descriptive Action Title]

[Clear explanation of what this step accomplishes]

### Instructions

1. [Specific action with exact commands/code]
2. [Next action]
3. [Final action for this step]

### Code Example

```julia
# Clear comments explaining the code
using Planar

# Show realistic, working example
config = Configuration(
    exchange = "binance",
    mode = :paper
)
```

### Expected Output

```
[Show what the user should see]
```

### Troubleshooting

If you encounter [specific issue]:
- [Specific solution]
- [Alternative approach]

## Step 2: [Next Action Title]

[Continue with same pattern]

## Verification

To confirm everything is working correctly:

1. [Specific test or check]
2. [Another verification step]

You should see [expected result]. If not, [troubleshooting guidance].

## Next Steps

Now that you've completed this tutorial, you can:
- [Logical next tutorial or concept]
- [Alternative path]
- [Advanced topic to explore]

### Recommended Reading
- [Link to related guide]: [Brief description]
- [Link to reference]: [Brief description]

## Troubleshooting

### Common Issues

**Issue**: [Specific problem description]
**Solution**: [Step-by-step resolution]

**Issue**: [Another common problem]
**Solution**: [Resolution steps]

### Getting Help

If you're still having trouble:
- [Link to relevant troubleshooting section]
- [Community support channels]
- [How to report bugs]
```

### Reference Template

Use for API documentation and technical references in `reference/`:

```markdown
---
title: "Function/Class/Concept Name"
description: "Brief description of functionality and purpose"
category: "reference"
tags: ["api", "relevant-topic"]
---

# Function/Class/Concept Name

Brief description (1-2 sentences) of what this is and its primary purpose.

## Syntax

```julia
function_name(required_param, another_param; optional_param=default_value)
```

## Parameters

### Required Parameters
- **`required_param`** (`Type`): Description of what this parameter does and any constraints
- **`another_param`** (`Type`): Description with examples of valid values

### Optional Parameters  
- **`optional_param`** (`Type`, default: `default_value`): Description of optional behavior

## Returns

**Type**: `ReturnType`

Description of what the function returns, including:
- Structure of return value
- Possible return states
- Error conditions

## Description

[Detailed explanation of functionality, behavior, and use cases]

### Key Concepts
- **Concept 1**: Definition and relevance
- **Concept 2**: Definition and relevance

## Examples

### Basic Usage

```julia
# Simple, common use case with explanation
using Planar

result = function_name("example_value", 42)
println(result)  # Expected output explanation
```

### Advanced Usage

```julia
# More complex example showing optional parameters
result = function_name(
    "complex_value", 
    100; 
    optional_param = custom_value
)

# Show how to handle the result
if result.success
    println("Operation completed: $(result.data)")
else
    println("Error: $(result.error)")
end
```

### Integration Example

```julia
# Show how this fits into larger workflows
strategy = create_strategy()
config = Configuration(exchange="binance")

# Use the function in context
result = function_name(strategy.symbol, config.timeframe)
apply_to_strategy(strategy, result)
```

## Error Handling

### Common Errors

**`ErrorType`**: Description of when this occurs
```julia
# Example that triggers the error
try
    function_name(invalid_input)
catch e
    println("Handle the error appropriately")
end
```

**`AnotherErrorType`**: Description and resolution
```julia
# Prevention or handling example
```

## Performance Considerations

[If applicable, include performance notes, memory usage, or optimization tips]

## Related Functions

- [`related_function`](link): Brief description of relationship
- [`another_function`](link): How it complements this function
- [`alternative_function`](link): When to use instead

## See Also

### Tutorials
- [Tutorial Name](link): Learn to use this in practice
- [Another Tutorial](link): Related workflow

### Guides  
- [Concept Guide](link): Deeper explanation of underlying concepts
- [Best Practices](link): Recommended usage patterns

### Reference
- [Related API](link): Connected functionality
- [Configuration Options](link): Relevant settings
```

### Guide Template

Use for comprehensive explanations in `guides/` and `advanced/`:

```markdown
---
title: "Guide Title"
description: "What this guide covers and who should read it"
category: "guides"
difficulty: "intermediate"
prerequisites: ["basic-concepts", "installation"]
estimated_time: "45 minutes"
---

# Guide Title

Introduction paragraph explaining:
- What this guide covers
- Who should read it  
- What problems it solves
- How it fits into the larger Planar ecosystem

## Overview

High-level explanation of the concept, workflow, or feature being covered.

### Key Benefits
- [Primary advantage]
- [Secondary advantage]  
- [Additional benefit]

### When to Use This
- [Specific use case]
- [Another scenario]
- [Problem this solves]

## Core Concepts

### Concept 1: [Name]
**Definition**: [Clear, concise definition]

**Purpose**: [Why this concept matters]

**Example**: [Simple illustration]

### Concept 2: [Name]
[Same pattern as above]

## Implementation

### Basic Setup

[Step-by-step instructions for basic implementation]

```julia
# Complete, working example
using Planar

# Show realistic setup
config = Configuration(
    # Relevant configuration
)
```

### Configuration Options

#### Required Settings
- **`setting_name`**: Description and valid values
- **`another_setting`**: Purpose and examples

#### Optional Settings
- **`optional_setting`**: When to use and default behavior
- **`advanced_setting`**: Advanced use cases

### Advanced Configuration

[More complex setup for advanced users]

```julia
# Advanced example with explanation
advanced_config = Configuration(
    # Show sophisticated usage
)
```

## Common Patterns

### Pattern 1: [Descriptive Name]

**Use Case**: [When to apply this pattern]

**Implementation**:
```julia
# Complete example of the pattern
```

**Benefits**: [Why this approach is recommended]

### Pattern 2: [Another Pattern]
[Same structure as above]

## Best Practices

### Performance
- [Specific performance recommendation]
- [Another optimization tip]
- [Resource management advice]

### Security
- [Security consideration]
- [Safe usage pattern]
- [What to avoid]

### Maintainability  
- [Code organization advice]
- [Documentation recommendations]
- [Testing suggestions]

## Integration with Other Features

### Feature Integration 1
[How this works with other Planar features]

```julia
# Integration example
```

### Feature Integration 2
[Another integration scenario]

## Troubleshooting

### Common Issues

#### Issue: [Specific Problem]
**Symptoms**: [How to recognize this issue]
**Cause**: [Why this happens]
**Solution**: [Step-by-step resolution]

#### Issue: [Another Problem]
[Same structure as above]

### Debugging Tips
- [Diagnostic approach]
- [Useful debugging commands]
- [Log analysis guidance]

## Real-World Examples

### Example 1: [Practical Scenario]
[Complete, realistic example with context]

```julia
# Full implementation example
```

**Explanation**: [Why this approach was chosen]

### Example 2: [Different Scenario]
[Another complete example]

## Migration and Upgrades

[If applicable, guidance for updating from previous versions or migrating from other approaches]

## Performance and Scaling

[If applicable, guidance on performance optimization and scaling considerations]

## See Also

### Next Steps
- [Logical next guide]: [What to learn next]
- [Advanced topic]: [For deeper exploration]

### Related Guides
- [Complementary guide]: [How it relates]
- [Alternative approach]: [When to use instead]

### Reference Documentation
- [API reference]: [Relevant functions]
- [Configuration reference]: [Related settings]
```

### Troubleshooting Template

Use for problem-solving content in `troubleshooting/`:

```markdown
---
title: "Problem Category or Specific Issue"
description: "Brief description of problems covered"
category: "troubleshooting"
tags: ["error-type", "component"]
---

# Problem Category or Specific Issue

Brief description of the problem area and what this page covers.

## Quick Diagnosis

### Symptoms Checklist
- [ ] [Specific symptom to check]
- [ ] [Another observable symptom]
- [ ] [Error message or behavior]

### Immediate Actions
If you're experiencing [critical issue]:
1. [Immediate step to prevent damage]
2. [Quick temporary fix]
3. [When to seek additional help]

## Common Problems

### Problem 1: [Specific Issue Name]

**Symptoms**: 
- [Observable behavior]
- [Error messages]
- [Performance indicators]

**Likely Causes**:
- [Most common cause]
- [Alternative cause]
- [Less common but possible cause]

**Solution**:
1. [First diagnostic step]
2. [Corrective action]
3. [Verification step]

**Prevention**:
- [How to avoid this in the future]
- [Best practices to follow]

### Problem 2: [Another Issue]
[Same structure as above]

## Diagnostic Procedures

### Step-by-Step Diagnosis

1. **Check [First Thing]**
   ```julia
   # Diagnostic command
   ```
   Expected output: [What to look for]

2. **Verify [Second Thing]**
   ```bash
   # System check command
   ```
   If this shows [problem indicator]: [what it means]

3. **Test [Third Thing]**
   [Diagnostic procedure]

### Advanced Diagnostics

For complex issues:

```julia
# Advanced diagnostic code
```

## Error Reference

### Error Code: [Specific Error]
**Message**: `[Exact error text]`
**Meaning**: [What this error indicates]
**Resolution**: [How to fix it]

### Error Code: [Another Error]
[Same structure]

## Platform-Specific Issues

### Linux
[Linux-specific problems and solutions]

### macOS
[macOS-specific problems and solutions]

### Windows
[Windows-specific problems and solutions]

## Getting Help

### Before Asking for Help
1. [Information to gather]
2. [Steps to try first]
3. [How to reproduce the issue]

### Where to Get Help
- **GitHub Issues**: [When to use and how]
- **Community Forums**: [For what types of questions]
- **Discord/Chat**: [Real-time help scenarios]

### Information to Include
When reporting issues, include:
- [System information needed]
- [Configuration details]
- [Error messages and logs]
- [Steps to reproduce]

## Prevention

### Best Practices
- [Preventive measure 1]
- [Preventive measure 2]
- [Monitoring recommendation]

### Regular Maintenance
- [Maintenance task 1]
- [Maintenance task 2]
- [Update procedures]
```

## Quality Assurance Standards

### Content Review Checklist

#### Technical Accuracy
- [ ] All code examples execute successfully
- [ ] API information matches current version
- [ ] Links are functional and current
- [ ] Prerequisites are accurate and complete
- [ ] Instructions produce expected results

#### Clarity and Usability
- [ ] Language is clear and appropriate for audience
- [ ] Steps are in logical order
- [ ] Examples are realistic and practical
- [ ] Success criteria are clearly defined
- [ ] Troubleshooting covers common issues

#### Consistency and Standards
- [ ] Follows appropriate template
- [ ] Frontmatter is complete and correct
- [ ] Formatting follows style guidelines
- [ ] Cross-references are appropriate
- [ ] Terminology is consistent

#### User Experience
- [ ] Content serves intended user journey
- [ ] Difficulty progression is appropriate
- [ ] Navigation aids are helpful
- [ ] Integration with existing content is smooth

### Automated Validation

All content is automatically checked for:
- **Link Health**: Internal and external link validation
- **Code Execution**: All Julia examples must run successfully
- **Template Compliance**: Proper structure and frontmatter
- **Style Consistency**: Markdown formatting and conventions

### Manual Review Process

1. **Technical Review**: Subject matter expert validates accuracy
2. **Editorial Review**: Writing quality and clarity assessment  
3. **User Experience Review**: Usability and journey effectiveness
4. **Final Approval**: Maintainer approval for publication

## Maintenance Procedures

### Regular Updates
- **Monthly**: Review getting-started content for accuracy
- **Quarterly**: Update code examples for new releases
- **Annually**: Comprehensive content audit and refresh

### Version Control
- All changes tracked in Git with descriptive commit messages
- Major updates documented in changelog
- Breaking changes communicated to users

### Community Contributions
- Clear contribution guidelines and templates
- Responsive review process
- Recognition and credit for contributors
- Mentorship for new contributors

This document is itself subject to these standards and should be updated as our practices evolve.