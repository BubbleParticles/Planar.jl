#!/bin/bash
set -euo pipefail

echo "📝 Running spell check..."

# Create custom dictionary
cat > .aspell.en.pws << 'EOF'
personal_ws-1.1 en 100
Planar
Julia
CCXT
API
APIs
backtesting
cryptocurrency
OHLCV
timeframe
timeframes
config
configs
workflow
workflows
GitHub
Markdown
YAML
JSON
TOML
DataFrame
DataFrames
async
await
struct
structs
enum
enums
tuple
tuples
dict
dicts
EOF

# Run spell check on all markdown files
error_count=0
for file in $(find docs -name "*.md"); do
    echo "Checking $file..."
    if ! aspell --personal=./.aspell.en.pws --dont-backup --mode=markdown check "$file"; then
        echo "❌ Spell check failed for $file"
        error_count=$((error_count + 1))
    fi
done

if [ $error_count -gt 0 ]; then
    echo "❌ Spell check failed with $error_count errors"
    exit 1
else
    echo "✅ Spell check completed successfully"
    exit 0
fi