#!/bin/bash

# Link Checker Script for Planar Documentation
# Validates all internal and external links in documentation

set -e

DOCS_DIR="docs/src"
REPORT_FILE="docs/maintenance/link-check-report.md"
TEMP_FILE="/tmp/link-check.tmp"

echo "# Link Check Report - $(date)" > "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Function to check internal links
check_internal_links() {
    echo "## Internal Links" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    find "$DOCS_DIR" -name "*.md" -exec grep -l "\[.*\](.*\.md)" {} \; | while read -r file; do
        echo "Checking internal links in: $file"
        
        # Extract markdown links
        grep -o '\[.*\](.*\.md[^)]*)' "$file" | while read -r link; do
            # Extract the file path from the link
            link_path=$(echo "$link" | sed 's/.*](\([^)]*\)).*/\1/' | sed 's/#.*//')
            
            # Convert relative path to absolute
            if [[ "$link_path" == /* ]]; then
                full_path="$DOCS_DIR$link_path"
            else
                dir=$(dirname "$file")
                full_path="$dir/$link_path"
            fi
            
            # Check if file exists
            if [[ ! -f "$full_path" ]]; then
                echo "- ❌ **$file**: Broken link to \`$link_path\`" >> "$REPORT_FILE"
            fi
        done
    done
    
    echo "" >> "$REPORT_FILE"
}

# Function to check external links
check_external_links() {
    echo "## External Links" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    find "$DOCS_DIR" -name "*.md" -exec grep -l "http" {} \; | while read -r file; do
        echo "Checking external links in: $file"
        
        # Extract HTTP/HTTPS links
        grep -o 'https\?://[^)]*' "$file" | sort -u | while read -r url; do
            # Clean up URL (remove trailing punctuation)
            clean_url=$(echo "$url" | sed 's/[.,;)]$//')
            
            # Check if URL is accessible
            if ! curl -s --head --fail "$clean_url" > /dev/null 2>&1; then
                echo "- ❌ **$file**: Broken external link to \`$clean_url\`" >> "$REPORT_FILE"
            fi
        done
    done
    
    echo "" >> "$REPORT_FILE"
}

# Function to check anchor links
check_anchor_links() {
    echo "## Anchor Links" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    find "$DOCS_DIR" -name "*.md" -exec grep -l "#.*)" {} \; | while read -r file; do
        echo "Checking anchor links in: $file"
        
        # Extract anchor links within the same file
        grep -o '\[.*\](#[^)]*' "$file" | while read -r link; do
            anchor=$(echo "$link" | sed 's/.*](#\([^)]*\)).*/\1/')
            
            # Convert anchor to expected heading format
            expected_heading=$(echo "$anchor" | sed 's/-/ /g' | tr '[:upper:]' '[:lower:]')
            
            # Check if heading exists in the file
            if ! grep -qi "^#.*$expected_heading" "$file"; then
                echo "- ❌ **$file**: Broken anchor link to \`#$anchor\`" >> "$REPORT_FILE"
            fi
        done
    done
    
    echo "" >> "$REPORT_FILE"
}

# Main execution
echo "Starting link validation..."

# Create maintenance directory if it doesn't exist
mkdir -p "$(dirname "$REPORT_FILE")"

# Run checks
check_internal_links
check_external_links
check_anchor_links

# Summary
echo "## Summary" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

broken_count=$(grep -c "❌" "$REPORT_FILE" || echo "0")
if [[ "$broken_count" -eq 0 ]]; then
    echo "✅ All links are working correctly!" >> "$REPORT_FILE"
    echo "Link check completed successfully - no broken links found."
    exit 0
else
    echo "❌ Found $broken_count broken links that need attention." >> "$REPORT_FILE"
    echo "Link check completed - found $broken_count broken links. See $REPORT_FILE for details."
    exit 1
fi