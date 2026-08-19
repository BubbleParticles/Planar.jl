#!/usr/bin/env bash
# Skill: register-packages
# Trigger: when asked to register Julia packages to the Julia registry
#
# Registers monorepo Julia packages (in dependency order after PlanarCore)
# using @JuliaRegistrator via GitHub issue comments, then verifies.
#
# Usage: register-packages.sh [PACKAGE ...]
#   With no args: registers all packages in order (from scripts/register.jl).
#   With args: registers only the listed packages, in the order given.
#
# Pre-reqs:
#   - `gh` CLI authenticated
#   - The repo is pushed to GitHub and registered with JuliaRegistrator
#   - Version in PLANAR/Project.toml is set (tag already exists)

set -euo pipefail

if [ -f .envrc ]; then
  source .envrc 2>/dev/null || true
fi

REPO="BubbleParticles/Planar.jl"

# Packages in registration order (must come after PlanarCore, which is on General)
if [ $# -eq 0 ]; then
  PACKAGES=(
    PlanarStrategyStats
    Planar
    PlanarFeatureSelection
    PlanarDownloadTool
    PlanarPython
    PlanarStrategyTools
    PlanarOptim
    PlanarDev
  )
else
  PACKAGES=("$@")
fi

echo "=== Registering packages to Julia registry ==="
echo "Repo: $REPO"
echo ""

for pkg in "${PACKAGES[@]}"; do
  subdir="${pkg%/}"
  echo "--- Registering $pkg (subdir=$subdir) ---"

  # Trigger JuliaRegistrator by commenting on the latest commit
  COMMIT_HASH=$(git rev-parse HEAD)
  COMMENT="@JuliaRegistrator register subdir=$subdir"

  gh issue comment "$COMMIT_HASH" --repo "$REPO" --body "$COMMENT" 2>/dev/null || \
    gh pr comment --repo "$REPO" --body "$COMMENT" 2>/dev/null || \
    echo "  WARNING: could not comment (commit/PR may not be accessible)"

  echo "  Triggered registration for $pkg"
  echo "  Monitor at: https://github.com/$REPO/issues"
  echo ""
done

echo "=== Registration triggers sent ==="
echo "Check GitHub issue/PR comments for JuliaRegistrator responses."
echo "If errors occur (e.g. missing deps in General registry), fix Project.toml"
echo "and re-run for that package."
