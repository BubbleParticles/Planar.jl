#!/bin/bash
set -e

PROJECT="/project"
PACKAGES=(
    Cli Collections Engine Executors Exchanges FeatureSelection
    Fetch Instances LiveMode Metrics Opt PaperMode
    Planar PlanarDev PlanarInteractive Plotting Processing
    Remote Scrapers SimMode Simulations Strategies
    StrategyStats StrategyTools Stubs Watchers
)

UPDATED=0
SKIPPED=0
FAILED=0

for pkg in "${PACKAGES[@]}"; do
    manifest="$PROJECT/$pkg/Manifest.toml"
    
    if [ ! -f "$manifest" ]; then
        echo "SKIP $pkg (no Manifest)"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi
    
    if ! grep -q 'vendor/Zarr' "$manifest"; then
        echo "SKIP $pkg (no vendored Zarr)"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi
    
    echo "UPDATING $pkg..."
    
    # Try resolving first - if fails, update
    if julia --project="$PROJECT/$pkg" -e 'import Pkg; Pkg.update()' 2>&1 | tail -3 | grep -q 'ERROR\|Error'; then
        echo "  FAILED"
        FAILED=$((FAILED + 1))
    else
        echo "  OK"
        UPDATED=$((UPDATED + 1))
    fi
    
    # Small delay to let system breathe
    sleep 0.5
done

echo ""
echo "Done! Updated: $UPDATED, Skipped: $SKIPPED, Failed: $FAILED"
