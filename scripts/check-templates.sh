#!/bin/bash

# Template Compliance Checker for Planar Documentation
# Validates that documentation follows established templates and standards

set -e

DOCS_DIR="docs/src"
REPORT_FILE="docs/maintenance/template-compliance-report.md"

echo "# Template Compliance Report - $(date)" > "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Function to check frontmatter
check_frontmatter() {
    echo "## Frontmatter Validation" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    find "$DOCS_DIR" -name "*.md" | while read -r file; do
        echo "Checking frontmatter in: $file"
        
        # Check if file has frontmatter
        if ! head -n 1 "$file" | grep -q "^---$"; then
            echo "- ❌ **$file**: Missing frontmatter" >> "$REPORT_FILE"
            continue
        fi
        
        # Extract frontmatter
        frontmatter=$(sed -n '/^---$/,/^---$/p' "$file" | sed '1d;$d')
        
        # Check required fields
        if ! echo "$frontmatter" | grep -q "^title:"; then
            echo "- ❌ **$file**: Missing title in frontmatter" >> "$REPORT_FILE"
        fi
        
        if ! echo "$frontmatter" | grep -q "^description:"; then
            echo "- ❌ **$file**: Missing description in frontmatter" >> "$REPORT_FILE"
        fi
        
        if ! echo "$frontmatter" | grep -q "^category:"; then
            echo "- ❌ **$file**: Missing category in frontmatter" >> "$REPORT_FILE"
        fi
    done
    
    echo "" >> "$REPORT_FILE"
}

# Function to check heading structure
check_heading_structure() {
    echo "## Heading Structure" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    find "$DOCS_DIR" -name "*.md" | while read -r file; do
        echo "Checking heading structure in: $file"
        
        # Check for proper heading hierarchy
        headings=$(grep "^#" "$file" | sed 's/^#*//' | wc -l)
        
        if [[ $headings -eq 0 ]]; then
            echo "- ❌ **$file**: No headings found" >> "$REPORT_FILE"
            continue
        fi
        
        # Check if first heading is H1
        first_heading=$(grep "^#" "$file" | head -n 1)
        if [[ ! "$first_heading" =~ ^#[^#] ]]; then
            echo "- ❌ **$file**: First heading should be H1" >> "$REPORT_FILE"
        fi
        
        # Check for heading level jumps (e.g., H1 to H3)
        prev_level=0
        grep "^#" "$file" | while read -r heading; do
            level=$(echo "$heading" | grep -o "^#*" | wc -c)
            level=$((level - 1))
            
            if [[ $prev_level -gt 0 && $level -gt $((prev_level + 1)) ]]; then
                echo "- ❌ **$file**: Heading level jump detected (H$prev_level to H$level)" >> "$REPORT_FILE"
            fi
            
            prev_level=$level
        done
    done
    
    echo "" >> "$REPORT_FILE"
}

# Function to check code block formatting
check_code_blocks() {
    echo "## Code Block Formatting" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    find "$DOCS_DIR" -name "*.md" | while read -r file; do
        echo "Checking code blocks in: $file"
        
        # Check for unclosed code blocks
        backtick_count=$(grep -c "^```" "$file" || echo "0")
        if [[ $((backtick_count % 2)) -ne 0 ]]; then
            echo "- ❌ **$file**: Unclosed code block detected" >> "$REPORT_FILE"
        fi
        
        # Check for code blocks without language specification
        while IFS= read -r line; do
            line_num=$(echo "$line" | cut -d: -f1)
            echo "- ⚠️ **$file:$line_num**: Code block without language specification" >> "$REPORT_FILE"
        done < <(grep -n "^```$" "$file" 2>/dev/null)
    done
    
    echo "" >> "$REPORT_FILE"
}

# Function to check tutorial template compliance
check_tutorial_template() {
    echo "## Tutorial Template Compliance" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Find files in getting-started and guides directories
    find "$DOCS_DIR/getting-started" "$DOCS_DIR/guides" -name "*.md" 2>/dev/null | while read -r file; do
        echo "Checking tutorial template in: $file"
        
        # Check for required sections
        if ! grep -q "## Prerequisites" "$file"; then
            echo "- ❌ **$file**: Missing Prerequisites section" >> "$REPORT_FILE"
        fi
        
        if ! grep -q "## What You'll Learn\|## Learning Objectives" "$file"; then
            echo "- ❌ **$file**: Missing learning objectives section" >> "$REPORT_FILE"
        fi
        
        if ! grep -q "## Next Steps\|## What's Next" "$file"; then
            echo "- ❌ **$file**: Missing next steps section" >> "$REPORT_FILE"
        fi
    done
    
    echo "" >> "$REPORT_FILE"
}

# Function to check reference template compliance
check_reference_template() {
    echo "## Reference Template Compliance" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Find files in reference directory
    find "$DOCS_DIR/reference" -name "*.md" 2>/dev/null | while read -r file; do
        echo "Checking reference template in: $file"
        
        # Check for required sections
        if ! grep -q "## Syntax\|## Usage" "$file"; then
            echo "- ❌ **$file**: Missing syntax/usage section" >> "$REPORT_FILE"
        fi
        
        if ! grep -q "## Examples" "$file"; then
            echo "- ❌ **$file**: Missing examples section" >> "$REPORT_FILE"
        fi
        
        if ! grep -q "## See Also\|## Related" "$file"; then
            echo "- ❌ **$file**: Missing see also section" >> "$REPORT_FILE"
        fi
    done
    
    echo "" >> "$REPORT_FILE"
}

# Function to check link formatting
check_link_formatting() {
    echo "## Link Formatting" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    find "$DOCS_DIR" -name "*.md" | while read -r file; do
        echo "Checking link formatting in: $file"
        
        # Check for malformed markdown links
        grep -n "\[.*\]([^)]*" "$file" | grep -v "\[.*\]([^)]*)" | while read -r line; do
            line_num=$(echo "$line" | cut -d: -f1)
            echo "- ❌ **$file:$line_num**: Malformed markdown link" >> "$REPORT_FILE"
        done
        
        # Check for bare URLs that should be formatted as links
        grep -n "https\?://[^ ]*" "$file" | grep -v "\[.*\](https\?://[^)]*)" | while read -r line; do
            line_num=$(echo "$line" | cut -d: -f1)
            echo "- ⚠️ **$file:$line_num**: Bare URL should be formatted as markdown link" >> "$REPORT_FILE"
        done
    done
    
    echo "" >> "$REPORT_FILE"
}

# Main execution
echo "Starting template compliance check..."

# Create maintenance directory if it doesn't exist
mkdir -p "$(dirname "$REPORT_FILE")"

# Run checks
check_frontmatter
check_heading_structure
check_code_blocks
check_tutorial_template
check_reference_template
check_link_formatting

# Summary
echo "## Summary" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

issue_count=$(grep -c "❌\|⚠️" "$REPORT_FILE" || echo "0")
error_count=$(grep -c "❌" "$REPORT_FILE" || echo "0")
warning_count=$(grep -c "⚠️" "$REPORT_FILE" || echo "0")

if [[ "$issue_count" -eq 0 ]]; then
    echo "✅ All documentation follows template standards!" >> "$REPORT_FILE"
    echo "Template compliance check completed successfully - no issues found."
    exit 0
else
    echo "Found $issue_count template compliance issues:" >> "$REPORT_FILE"
    echo "- ❌ Errors: $error_count" >> "$REPORT_FILE"
    echo "- ⚠️ Warnings: $warning_count" >> "$REPORT_FILE"
    echo ""
    echo "Template compliance check completed - found $issue_count issues. See $REPORT_FILE for details."
    
    if [[ "$error_count" -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
fi