#!/usr/bin/env python3
import os
import re

def check_heading_hierarchy(file_path):
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    headings = re.findall(r'^(#{1,6})\s+(.+)$', content, re.MULTILINE)
    issues = []

    prev_level = 0
    for heading_match in headings:
        level = len(heading_match[0])
        title = heading_match[1]

        # Check for level jumps (e.g., H1 to H3)
        if prev_level > 0 and level > prev_level + 1:
            issues.append(f"Heading level jump: H{prev_level} to H{level} - '{title}'")

        prev_level = level

    return issues

if __name__ == "__main__":
    all_issues = []
    for root, dirs, files in os.walk('docs'):
        for file in files:
            if file.endswith('.md'):
                file_path = os.path.join(root, file)
                issues = check_heading_hierarchy(file_path)
                for issue in issues:
                    all_issues.append(f"{file_path}: {issue}")

    if all_issues:
        print("❌ Heading hierarchy issues found:")
        for issue in all_issues:
            print(f"  - {issue}")
        exit(1)
    else:
        print("✅ All heading hierarchies are correct")
        exit(0)