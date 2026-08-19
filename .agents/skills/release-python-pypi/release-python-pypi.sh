#!/usr/bin/env bash
# release-python-pypi.sh — Release Python packages to PyPI/TestPyPI
# Usage: release-python-pypi.sh [test|prod] [version] [package...]
#   test/prod: release target (default: test)
#   version: version string like "1.2.3" (without v/py-v prefix)
#   package: ccxt-gateway, planarjl-py, or both (default: both)

set -euo pipefail

TARGET="${1:-test}"
VERSION="${2:-}"
PACKAGES=("${@:3}")

if [[ -z "$VERSION" ]]; then
    echo "Usage: $0 [test|prod] <version> [ccxt-gateway] [planarjl-py]"
    echo "  test  -> tag py-v<version> (TestPyPI)"
    echo "  prod  -> tag v<version> (PyPI)"
    exit 1
fi

# Default to both packages
if [[ ${#PACKAGES[@]} -eq 0 ]]; then
    PACKAGES=("ccxt-gateway" "planarjl-py")
fi

# Validate target
if [[ "$TARGET" != "test" && "$TARGET" != "prod" ]]; then
    echo "Error: target must be 'test' or 'prod'"
    exit 1
fi

# Validate packages
for pkg in "${PACKAGES[@]}"; do
    if [[ "$pkg" != "ccxt-gateway" && "$pkg" != "planarjl-py" ]]; then
        echo "Error: unknown package '$pkg' (must be ccxt-gateway or planarjl-py)"
        exit 1
    fi
done

# Construct tag
if [[ "$TARGET" == "test" ]]; then
    TAG="py-v$VERSION"
else
    TAG="v$VERSION"
fi

echo "Releasing to ${TARGET^^}PI with tag: $TAG"
echo "Packages: ${PACKAGES[*]}"

# Check if tag already exists
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "Error: tag '$TAG' already exists"
    exit 1
fi

# Check working tree is clean
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Error: working tree has uncommitted changes"
    exit 1
fi

# Create and push tag
git tag "$TAG"
echo "Created tag: $TAG"
git push origin "$TAG"
echo "Pushed tag to origin"

echo "Release triggered! Monitor workflows at:"
echo "  https://github.com/BubbleParticles/Planar.jl/actions"
echo ""
echo "Workflows:"
for pkg in "${PACKAGES[@]}"; do
    if [[ "$pkg" == "ccxt-gateway" ]]; then
        echo "  - pypi-ccxt (ccxt-gateway)"
    else
        echo "  - pypi (planarjl-py)"
    fi
done