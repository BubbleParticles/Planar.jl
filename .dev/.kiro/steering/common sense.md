---
inclusion: always
---

# Common Sense Guidelines

## Path and Directory Management
- Always verify current working directory with `pwd` before executing scripts or commands
- Use relative paths from project root when referencing files in commands
- Be aware that Julia REPL and shell commands may have different working directories

## File Operations
- Check file existence before attempting operations
- Use appropriate file permissions when creating executable scripts
- Verify file paths are correct for the current operating system (Linux in this case)

## Command Execution
- Validate command syntax before execution
- Consider environment variables that may affect command behavior
- Use absolute paths for system binaries when necessary for reliability

## Error Prevention
- Double-check file and directory names for typos
- Ensure required dependencies are available before running commands
- Verify network connectivity for operations requiring external resources

## Julia-Specific Considerations
- Confirm correct project environment is activated before package operations
- Check that required modules are loaded before calling functions
- Be mindful of Julia's compilation time on first function calls