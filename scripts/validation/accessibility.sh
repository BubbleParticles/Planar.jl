#!/bin/bash
set -euo pipefail

echo "♿ Checking accessibility..."

# Check for images without alt text
echo "Checking for images without alt text..."
if grep -r "!\[\](" docs/ --include="*.md"; then
    echo "❌ Images without alt text found"
    exit 1
fi

# Check for inaccessible link text
echo -e "\nChecking for inaccessible link text..."
if grep -r "\[click here\]\|\[here\]\|\[link\]\|\[read more\]" docs/ --include="*.md"; then
    echo "❌ Non-descriptive link text found"
    exit 1
fi

echo "✅ Accessibility check completed"
exit 0