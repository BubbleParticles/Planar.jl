# testing-strategy

Trigger: when running tests / asked how to test.

Describes the project's testing philosophy and patterns.

Usage: `testing-strategy.sh`

Output summary:
1. **Full suite** — `PlanarDev/test/runtests.jl` runs 14 test files.
2. **Per-package tests** — `cd <package> && julia --project=. -e 'using Pkg; Pkg.test()'`
3. **Interactive runner** — `julia --project=PlanarDev -e 'using PlanarDev; PlanarDev.test()'`
4. **Specific file** — `timeout -k 30 300 julia --project=PlanarDev PlanarDev/test/runtests.jl`
5. **Coverage** — `PlanarDev/scripts/coverage.sh`
