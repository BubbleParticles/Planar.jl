#!/usr/bin/env python3
import os
import re
import sys

def analyze_complexity(file_path):
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Count various elements
    headings = len(re.findall(r'^#{1,6}', content, re.MULTILINE))
    links = len(re.findall(r'\[.*?\]\(.*?\)', content))
    code_blocks = len(re.findall(r'```', content)) // 2
    lists = len(re.findall(r'^\s*[-*+]\s', content, re.MULTILINE))

    # Calculate complexity score
    complexity = headings + (links * 0.5) + (code_blocks * 2) + (lists * 0.3)

    return {
        'headings': headings,
        'links': links,
        'code_blocks': code_blocks,
        'lists': lists,
        'complexity': complexity
    }

if __name__ == "__main__":
    high_complexity_files = []
    for root, dirs, files in os.walk('docs'):
        for file in files:
            if file.endswith('.md'):
                file_path = os.path.join(root, file)
                stats = analyze_complexity(file_path)
                if stats['complexity'] > 50:  # Threshold for high complexity
                    high_complexity_files.append((file_path, stats))

    if high_complexity_files:
        print("❌ High complexity files detected:")
        for file_path, stats in high_complexity_files:
            print(f"  - {file_path}: complexity={stats['complexity']:.1f}")
        sys.exit(1)
    else:
        print("✅ All files have reasonable complexity")
        sys.exit(0)