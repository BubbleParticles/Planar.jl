#!/bin/bash
set -euo pipefail

echo "🔍 Checking for common writing issues..."

# Check for passive voice indicators
echo "Checking for passive voice..."
grep -r "is being\|was being\|will be\|has been\|have been\|had been" docs/ --include="*.md" || true

# Check for weak words
echo -e "\nChecking for weak language..."
grep -r "very\|really\|quite\|rather\|somewhat\|pretty\|fairly" docs/ --include="*.md" || true

# Check for unclear references
echo -e "\nChecking for unclear references..."
grep -r "this\|that\|these\|those" docs/ --include="*.md" | grep -v "this tutorial\|this guide\|this section" || true

echo "✅ Writing issues check completed"