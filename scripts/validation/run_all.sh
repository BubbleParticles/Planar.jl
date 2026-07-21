#!/bin/bash

# Super script to run all documentation validation scripts.
# Each script is run and any errors are ignored to ensure exit code 0.

set -e

echo "Running Markdown complexity check..."
python scripts/validation/markdown_complexity.py || echo "markdown_complexity.py failed (ignored)"

echo "Running heading hierarchy check..."
python scripts/validation/heading_hierarchy.py || echo "heading_hierarchy.py failed (ignored)"

echo "Running accessibility check..."
bash scripts/validation/accessibility.sh || echo "accessibility.sh failed (ignored)"

echo "Running performance check..."
bash scripts/validation/performance.sh || echo "performance.sh failed (ignored)"

echo "Running spell check..."
bash scripts/validation/spellcheck.sh || echo "spellcheck.sh failed (ignored)"

echo "Running writing issues check..."
bash scripts/validation/writing_issues.sh || echo "writing_issues.sh failed (ignored)"

echo "All validation scripts completed (errors ignored)."
exit 0
