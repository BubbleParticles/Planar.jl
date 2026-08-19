# register-packages

**Trigger:** User asks to register Julia packages to the Julia registry, publish packages, or run `@JuliaRegistrator`.

## Overview

Registers monorepo Julia packages to the General registry by triggering `@JuliaRegistrator` on GitHub commit comments. `PlanarCore` is already on the General registry and is **not** re-registered here (see `PACKAGING.md` §1.4 and `scripts/register.jl:38-41`).

`PlanarStrategies` (external repo at `github.com/BubbleParticles/PlanarStrategies`, included as a git submodule at `user/strategies/`) contains 12 strategy packages. These are registered separately on the **PlanarStrategies** repo — not Planar.jl. See [PlanarStrategies registration](#planarstrategies-registration) below.

## Registration order

After `PlanarCore` (on General), packages are registered in dependency order:

| Level | Package | Depends on (must be merged first) |
|-------|---------|-----------------------------------|
| 0 | **PlanarStrategyStats** | PlanarCore ✓ |
| 0 | **PlanarFeatureSelection** | PlanarCore ✓ |
| 0 | **PlanarDownloadTool** | PlanarCore ✓ |
| 0 | **PlanarPython** | PlanarCore ✓ |
| 1 | **Planar** | PlanarCore ✓, PlanarStrategyStats |
| 2 | **PlanarStrategyTools** | Planar |
| 2 | **PlanarOptim** | Planar, PlanarDownloadTool |
| 2 | **PlanarDev** | Planar |

This order is sourced from `scripts/register.jl` (`PACKAGES` constant). Level 0 packages can be registered simultaneously; Level 1 must wait for PlanarStrategyStats's PR to merge; Level 2 must wait for Planar's PR to merge.

## Usage

### Via the shell wrapper (simplests, records output)

```bash
# Register all packages in order
bash .agents/skills/register-packages/register-packages.sh

# Register specific packages only (in the order given)
bash .agents/skills/register-packages/register-packages.sh Planar PlanarDev
```

### Via Registrator comment directly (manual)

Comment on the tagged commit in `BubbleParticles/Planar.jl`:

```
@JuliaRegistrator register subdir=PlanarCore
@JuliaRegistrator register subdir=PlanarStrategyStats
@JuliaRegistrator register subdir=Planar
@JuliaRegistrator register subdir=PlanarFeatureSelection
@JuliaRegistrator register subdir=PlanarDownloadTool
@JuliaRegistrator register subdir=PlanarPython
@JuliaRegistrator register subdir=PlanarStrategyTools
@JuliaRegistrator register subdir=PlanarOptim
@JuliaRegistrator register subdir=PlanarDev
```

`PlanarCore` is included only for the General registry (it is NOT in the custom registry's `PACKAGES` list — see `scripts/register.jl:38-41`).

## Prerequisites

- `gh` CLI authenticated with write access to `BubbleParticles/Planar.jl`
- The repo is pushed to GitHub (Registrator needs the commit on GitHub to compute a tarball SHA)
- A version tag (`v<version>`) exists on the commit being registered
- The package is registered with JuliaRegistrator (install the [app](https://juliahub.com/Registrator.jl/dev/) on the repo)

## Constraints

- **Commit must be pushed before registering** — `Pkg.add` downloads a tarball from `api.github.com`, so the tree SHA must exist on GitHub.
- **Version must be unique** across all registries — Registrator rejects re-registration of an already-published version.
- **Non-General weakdeps block extensions** — Registrator validates UUIDs in `[weakdeps]`/`[extensions]` against General. Packages not in General (e.g. `CausalityTools`, `EffectSizes` in `PlanarStrategyStats`, `DBnomics` in `PlanarDownloadTool`) cause registration to fail. Fix: **remove the `[weakdeps]`/`[extensions]` blocks entirely** and delete the extension file, since (a) `Pkg.test` cannot resolve non-General extras either, and (b) the extension code degrades gracefully when the functions are unavailable. Do NOT move to `[extras]`/`[targets]` — `Pkg.test` will still fail trying to resolve them. Check a package's deps against General with:
  ```julia
  using Pkg, UUIDs
  r = Pkg.Registry.reachable_registries()[1]
  haskey(r, UUID("uuid-string"))
  ```
- **Compat entries must be present** — `julia`, each external `[dep]`, and each `[weakdeps]` entry must have a `[compat]` row. Missing compat triggers a Registrator error.
- **`test/Project.toml` must not have `name`/`uuid`/`version`/`authors`** — Registrator treats such files as nested packages and fails precompilation.
- **Placeholder UUIDs cause collisions** — strategy packages `QuickStart` and `StrategyFramework` both had UUID `a1b2c3d4-e5f6-7890-abcd-ef1234567890` which collides with `WildlandFire` in General. Fix: generate unique UUIDs with `julia -e 'using UUIDs; println(uuid4())'`.
- **Wrong dep UUIDs in Project.toml** — `QuickStart` and `StrategyFramework` used `Optim = "01837..."` (PlanarStrategyStats's UUID, not the real Optim package) and `StrategyTools` (an alias for `PlanarStrategyTools`). Fix: remove unused `Optim` dep, rename `StrategyTools` → `PlanarStrategyTools`, update source imports.
- **MUST wait for dependency PRs to merge before registering downstream packages** — JuliaRegistrator validates every dep's UUID against the *merged* General registry (not pending PRs). If package X's PR on `JuliaRegistries/General` is still OPEN, any package depending on X will error with "X not found in registry". The sequence is:
  1. Register Level 0 packages (PlanarStrategyStats, PlanarFeatureSelection, PlanarDownloadTool, PlanarPython)
  2. **Wait for their PRs to be merged** into JuliaRegistries/General
  3. Register Level 1 (Planar) — triggers only after PlanarStrategyStats is merged
  4. **Wait for Planar's PR to be merged**
  5. Register Level 2 (PlanarStrategyTools, PlanarOptim, PlanarDev)
  6. **Wait for Planar's PR to be merged** (PlanarOptim also needs PlanarDownloadTool)
  7. Register PlanarStrategies packages on the PlanarStrategies repo — only after Planar (and PlanarOptim) are merged

## PlanarStrategies registration

The 12 strategy packages in `github.com/BubbleParticles/PlanarStrategies` (submodule at `user/strategies/`) are registered on the **PlanarStrategies repo**, not Planar.jl. Each package's `@JuliaRegistrator register subdir=<package>` comment must be made on a commit in `BubbleParticles/PlanarStrategies`.

```bash
# From the strategies submodule:
cd user/strategies
COMMIT=$(git rev-parse HEAD)
for pkg in BBWithOpt BollingerBands Example ExampleMargin MarginStrat \
           QuickStart RandomStratIso SimpleStrategy StrategyFramework \
           TickStrat TwoIntervals TwoParameters; do
  gh api "repos/BubbleParticles/PlanarStrategies/commits/$COMMIT/comments" \
    --method POST -f body="@JuliaRegistrator register subdir=$pkg"
done
```

**All strategy packages depend on `Planar` (not yet in General)**, so registration will fail until Planar's PR is merged. `BBWithOpt` and `ExampleMargin` additionally depend on `PlanarOptim`.

## Current status

| Package | PR | Status |
|---------|-----|--------|
| PlanarStrategyStats v0.1.0 | [General/165040](https://github.com/JuliaRegistries/General/pull/165040) | OPEN — needs merge |
| PlanarFeatureSelection v0.1.0 | [General/165041](https://github.com/JuliaRegistries/General/pull/165041) | OPEN — needs merge |
| PlanarPython v0.1.0 | [General/165042](https://github.com/JuliaRegistries/General/pull/165042) | OPEN — needs merge |
| PlanarDownloadTool v0.1.0 | [General/165044](https://github.com/JuliaRegistries/General/pull/165044) | OPEN — needs merge |
| Planar | — | ❌ Failed (PlanarStrategyStats not merged yet) |
| PlanarStrategyTools | — | ❌ Failed (Planar not registered yet) |
| PlanarOptim | — | ❌ Failed (Planar not registered yet) |
| PlanarDev | — | ❌ Failed (Planar not registered yet) |
| PlanarStrategies (12 pkgs) | — | ⏳ Comments triggered, JuliaRegistrator not installed on PlanarStrategies repo |

## After registration

- Merge the open PRs on `JuliaRegistries/General` (manual review required; only `Planar` qualifies for automerge due to repo URL matching)
- After merge, re-trigger `@JuliaRegistrator` for the next dependency level
- Install JuliaRegistrator on `BubbleParticles/PlanarStrategies` before strategy registration can proceed
- Verify with a fresh environment:
  ```julia
  using Pkg
  Pkg.Registry.add(RegistrySpec(url="https://github.com/BubbleParticles/PlanarRegistry.git"))
  Pkg.add("Planar")
  ```
