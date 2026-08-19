#!/usr/bin/env bash
# Skill: register-packages
# Trigger: when asked to register Julia packages to the Julia registry
#
# Registers monorepo Julia packages (in dependency order after PlanarCore)
# using @JuliaRegistrator commit comments, then verifies.
#
# Usage: register-packages.sh [PACKAGE ...]
#   With no args: registers all packages in order (from scripts/register.jl).
#   With args: registers only the listed packages, in the order given.
#
# Pre-reqs:
#   - `gh` CLI authenticated with write access to BubbleParticles/Planar.jl
#   - The repo is pushed to GitHub and registered with JuliaRegistrator
#   - A version tag (`v<version>`) exists on the commit being registered
#   - The commit is pushed to GitHub (Pkg downloads tarballs from GitHub)
#
# Registration order (must come after PlanarCore, which is already on General):
#   1. PlanarStrategyStats   (deps: PlanarCore ✓)
#   2. Planar                (deps: PlanarCore ✓, PlanarStrategyStats)
#   3. PlanarFeatureSelection
#   4. PlanarDownloadTool
#   5. PlanarPython
#   6. PlanarStrategyTools   (deps: Planar)
#   7. PlanarOptim           (deps: Planar, PlanarDownloadTool)
#   8. PlanarDev             (deps: Planar)

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

COMMIT_HASH=$(git rev-parse HEAD)
echo "Commit: $COMMIT_HASH"
echo ""

# Dependency levels — packages within the same level can be registered
# simultaneously; later levels must wait for earlier level PRs to merge.
declare -A DEP_LEVEL
DEP_LEVEL[PlanarStrategyStats]=0
DEP_LEVEL[Planar]=1
DEP_LEVEL[PlanarFeatureSelection]=0
DEP_LEVEL[PlanarDownloadTool]=0
DEP_LEVEL[PlanarPython]=0
DEP_LEVEL[PlanarStrategyTools]=2
DEP_LEVEL[PlanarOptim]=2
DEP_LEVEL[PlanarDev]=2

for pkg in "${PACKAGES[@]}"; do
  subdir="${pkg%/}"
  echo "--- Registering $pkg (subdir=$subdir) ---"

  # Trigger JuliaRegistrator by commenting on the latest commit
  COMMENT="@JuliaRegistrator register subdir=${subdir}"

  gh api "repos/${REPO}/commits/${COMMIT_HASH}/comments" \
    --method POST \
    -f body="$COMMENT" >/dev/null 2>&1 || \
    echo "  WARNING: could not comment (commit may not be on GitHub)"

  echo "  Triggered registration for $pkg"
  echo "  Monitor at: https://github.com/$REPO/commit/${COMMIT_HASH}"
  echo ""
done

echo "=== Registration triggers sent ==="
echo ""
echo "Check commit comments at https://github.com/$REPO/commit/${COMMIT_HASH}"
echo "for JuliaRegistrator responses (PR created or error)."
echo ""
echo "Dependency-ordered flow:"
echo "  Level 0 (no Planar deps): PlanarStrategyStats, PlanarFeatureSelection,"
echo "    PlanarDownloadTool, PlanarPython → trigger first"
echo "  Level 1 (needs PlanarStrategyStats merged): Planar"
echo "  Level 2 (needs Planar merged): PlanarStrategyTools, PlanarOptim, PlanarDev"
echo ""
echo "If a package errors with 'X not found in registry', merge the PR for X"
echo "on JuliaRegistries/General, then re-run this script for the dependent package(s)."
echo ""
echo "If a package errors with 'non-General dep not found' (e.g. DBnomics,"
echo "CausalityTools), remove the dep from [weakdeps]/[extensions] and delete"
echo "the extension file — the code must load via vendored/runtime paths instead."
