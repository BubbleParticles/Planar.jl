#!/bin/bash
set -euo pipefail

echo "⚡ Checking performance issues..."

# Check for large documentation files
echo "Checking for large documentation files..."
find docs -name "*.md" -size +100k -exec ls -lh {} \; | while read -r line; do
    echo "❌ Large file detected: $line"
done

# Check for large images
echo -e "\nChecking for large images..."
find docs \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" -o -name "*.gif" \) | while read -r file; do
    size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo 0)
    if [ "$size" -gt 1048576 ]; then  # 1MB
        echo "❌ Large image detected: $file ($((size / 1024))KB)"
    fi
done

echo "✅ Performance check completed"
exit 0