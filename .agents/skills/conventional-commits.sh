#!/usr/bin/env bash
# Skill: conventional-commits
# Trigger: when creating git commit messages
#
# Use Conventional Commits format for all commit messages.
# Format: <type>(<scope>): <description>
#
# Types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert
# Scope: optional, indicates the part of the codebase affected
# Description: imperative mood, lowercase, no trailing period
#
# Examples:
#   feat(auth): add OAuth2 login support
#   fix(api): resolve null pointer on empty response
#   docs: update README with setup instructions
#   refactor(core): simplify query builder logic
#   test(utils): add edge cases for date parsing

set -euo pipefail

usage() {
	cat <<EOF
Usage: $(basename "$0") [--types] [--example] [-h|--help]

Flags:
  --types      List all valid commit types
  --example    Show example commit messages
  -h, --help   Show this help message
EOF
	exit 0
}

show_types() {
	cat <<EOF
Valid Conventional Commit types:
  feat     - A new feature
  fix      - A bug fix
  docs     - Documentation only changes
  style    - Code style changes (formatting, semicolons, etc)
  refactor - Code change that neither fixes a bug nor adds a feature
  perf     - Code change that improves performance
  test     - Adding or correcting tests
  build    - Changes to build system or dependencies
  ci       - Changes to CI configuration
  chore    - Other changes that don't modify src or test files
  revert   - Reverts a previous commit
EOF
	exit 0
}

show_example() {
	cat <<EOF
Example commit messages:
  feat(auth): add OAuth2 login support
  fix(api): resolve null pointer on empty response
  docs: update README with setup instructions
  refactor(core): simplify query builder logic
  test(utils): add edge cases for date parsing
  perf(db): reduce query time by caching results
  ci: add GitHub Actions workflow for PR checks
EOF
	exit 0
}

while [ "$#" -gt 0 ]; do
	case "$1" in
	--types) show_types ;;
	--example) show_example ;;
	-h | --help) usage ;;
	*)
		echo "Unknown arg: $1"
		exit 2
		;;
	esac
	shift
done

echo "Reminder: Use Conventional Commits format for commit messages."
echo "Format: <type>(<scope>): <description>"
echo "Run with --types to see valid types, --example for examples."
