#!/bin/bash
set -euo pipefail

echo "Running spell check..."
cd "$(dirname "$0")/../.."   # repo root

# aspell needs a UTF-8 locale to tokenize multi-byte characters correctly
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

WORDLIST="docs/maintenance/aspell-wordlist.txt"

# Build the aspell personal wordlist from the committed technical vocabulary.
# Header format: personal_ws-1.1 <lang> <count> <encoding>
{
    echo "personal_ws-1.1 en 1000 utf-8"
    cat "$WORDLIST"
} > /tmp/.aspell-planar.pws

error_count=0
while IFS= read -r file; do
    bad_words=$(aspell --personal=/tmp/.aspell-planar.pws --dont-backup --mode=markdown list < "$file" | sort -u)
    if [ -n "$bad_words" ]; then
        echo "Misspelled words in $file:"
        echo "$bad_words"
        error_count=$((error_count + 1))
    fi
done < <(find docs/src -name "*.md")

if [ "$error_count" -gt 0 ]; then
    echo "Spell check failed in $error_count file(s)"
    exit 1
fi
echo "Spell check completed successfully"
