# Code Block Usage Guidelines

## CRITICAL: Maximum 50 Code Blocks Total

After aggressive elimination, we maintain **45 total Julia code blocks** across all documentation. This limit must be strictly enforced.

## Allocation Limits

- **Getting Started**: 15 blocks maximum (currently 15)
- **Strategy Examples**: 10 blocks maximum (currently 10)  
- **API Reference**: 9 blocks maximum (currently 9)
- **Integration**: 5 blocks maximum (currently 5)
- **Error Handling**: 4 blocks maximum (currently 4)
- **Troubleshooting**: 1 block maximum (currently 1)
- **Configuration**: 1 block maximum (currently 1)

## Strict Rules

### When Code Blocks Are Allowed
1. **Essential workflow demonstrations** that cannot be explained textually
2. **Complete, realistic examples** showing end-to-end functionality
3. **Critical error handling patterns** that must be shown in code
4. **Core API usage** that requires executable demonstration

### When Code Blocks Are PROHIBITED
1. **Simple syntax demonstrations** - use inline code: `using Planar`
2. **Configuration examples** - show as TOML files, not Julia
3. **Parameter variations** - describe textually
4. **Duplicate concepts** - one example per concept maximum
5. **Tutorial increments** - use step-by-step text instead

### Per-File Limits
- **Maximum 3 code blocks per file**
- **Most files should have 0-1 blocks**
- **Only critical files get 2-3 blocks**

## Review Process

### Before Adding Any Code Block
1. **Is this absolutely essential?** Can it be explained with text?
2. **Does this duplicate existing examples?** Remove duplicates first
3. **Can this be shown as inline code?** Use `backticks` instead
4. **Is this configuration?** Show as TOML/YAML file instead

### Enforcement
- **Total count must stay under 50**
- **Run inventory script before any additions**
- **Remove existing blocks before adding new ones**
- **Prefer textual explanations over code examples**

## Alternative Documentation Methods

### Instead of Code Blocks, Use:
1. **Inline code**: `using Planar` for simple syntax
2. **TOML examples**: Show actual config file content
3. **Step-by-step text**: Numbered instructions
4. **Conceptual explanations**: Describe patterns in prose
5. **Reference to working examples**: Point to existing blocks

## Current Status
- **Total blocks**: 45/50 (5 blocks remaining capacity)
- **Files with blocks**: 21/104 files
- **Average per file**: 2.1 blocks
- **Reduction achieved**: 93.8% (from 731 to 45)

## Emergency Protocol
If blocks exceed 50:
1. **Immediate removal** of least essential blocks
2. **Convert to alternative documentation**
3. **Re-run validation to ensure under 50**
4. **Update this document with new counts**