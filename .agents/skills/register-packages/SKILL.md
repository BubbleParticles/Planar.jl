# register-packages

**Trigger:** User asks to register Julia packages to the Julia registry, publish packages, or run `@JuliaRegistrator`.

## ⚠️ **Mandatory: Registrator (not manual PRs)**

Per the upstream JuliaRegistries/General registry rules ([AGENTS.md](https://github.com/JuliaRegistries/General/blob/master/AGENTS.md)):

> *"If a package is hosted on GitHub.com or GitLab.com, Registrator MUST be used to register it. Do NOT make a manual PR to register the package or versions."*

All Planar packages are hosted on **GitHub.com** (`BubbleParticles/Planar.jl` and `BubbleParticles/PlanarStrategies`). Therefore:

- **MUST** trigger `@JuliaRegistrator register subdir=<package>` on a commit comment.
- **MUST NOT** create a manual PR on `JuliaRegistries/General` to register a package or version — registry maintainers **will reject** such PRs (e.g. [#169724](https://github.com/JuliaRegistries/General/pull/169724), [#169725](https://github.com/JuliaRegistries/General/pull/169725), [#169726](https://github.com/JuliaRegistries/General/pull/169726) — all closed by maintainers with "Registrator required").
- A fork + manual PR is only a fallback for **drafting** registry files; the merged path is always the Registrator-created PR.
- The Registrator bot must be installed as a GitHub App on the host org (`juliateam-registrator` on `BubbleParticles`). It responds to `@JuliaRegistrator` comments on commits.

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

- **A version on General must keep the same tree in PlanarRegistry** — Pkg aborts with `ERROR: hash mismatch in registries for <Name> at version <v>` when both registries are reachable and disagree. Moving a tag or re-registering a version from a later commit (e.g. package cleanup) changes the tree without changing the version. A plain `diff` per file is **not sufficient** — it misses versions that exist on only one side (General has a version PlanarRegistry lacks, or PlanarRegistry carries a stale version General never published). Compare the **full version sets** and copy all four metadata files:
  ```bash
  for d in Planar PlanarCore PlanarDownloadTool PlanarFeatureSelection \
           PlanarOptim PlanarPython PlanarStrategyStats PlanarStrategyTools; do
    curl -sL "https://raw.githubusercontent.com/JuliaRegistries/General/master/P/$d/Versions.toml" \
      | grep -oP '^\["[^"]+"\]' | sort > /tmp/gen_$d
    grep -oP '^\["[^"]+"\]' PlanarRegistry/Packages/P/$d/Versions.toml | sort > /tmp/loc_$d
    echo "=== $d ==="
    echo "only in General: $(comm -23 /tmp/gen_$d /tmp/loc_$d)"
    echo "only locally:   $(comm -13 /tmp/gen_$d /tmp/loc_$d)"
    diff <(curl -sL "https://raw.githubusercontent.com/JuliaRegistries/General/master/P/$d/Versions.toml") \
         "PlanarRegistry/Packages/P/$d/Versions.toml"
  done
  ```
  Both `comm` lines must be empty **and** `diff` must be empty. Then copy `Package.toml`, `Deps.toml`, and `Compat.toml` from General too — the tree SHA alone is not enough; the metadata files must agree or Pkg fails validation. See `PACKAGING.md` §1.3 for the same loop with commentary.

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

**`Planar` is merged to General (2026-10-03).** Strategy deps beyond `Planar`: `BBWithOpt` and `ExampleMargin` additionally depend on `PlanarOptim`; `QuickStart` and `StrategyFramework` additionally depend on `PlanarStrategyTools` — those four register after their dependency's PR merges.

## Current status

| Package | PR | Status |
|---------|-----|--------|
| PlanarCore v1.0.0 / v1.0.1 | — | ✅ **ON GENERAL** |
| PlanarStrategyStats v0.1.0 | [General/165040](https://github.com/JuliaRegistries/General/pull/165040) | ✅ **ON GENERAL** (merged) |
| PlanarFeatureSelection v0.1.0 | [General/165041](https://github.com/JuliaRegistries/General/pull/165041) | ✅ **ON GENERAL** (merged) |
| PlanarPython v0.1.0 | [General/165042](https://github.com/JuliaRegistries/General/pull/165042) | ✅ **ON GENERAL** (merged) |
| PlanarDownloadTool v0.1.0 | [General/165044](https://github.com/JuliaRegistries/General/pull/165044) | ✅ **ON GENERAL** (merged) |
| Planar v1.9.0 | [General/#169714](https://github.com/JuliaRegistries/General/pull/169714) | ✅ **ON GENERAL** (merged 2026-10-03T16:33:13Z) |
| PlanarStrategyTools v0.1.2 | [General/#170501](https://github.com/JuliaRegistries/General/pull/170501) | ⏳ Registrator PR created 2026-10-04 from commit `7c1c0152d`; AutoMerge staging (~3-day wait for new packages) |
| PlanarOptim v0.1.2 | [General/#170502](https://github.com/JuliaRegistries/General/pull/170502) | ⏳ Registrator PR created 2026-10-04 from commit `7c1c0152d`; AutoMerge staging (~3-day wait for new packages) |
| PlanarDev v0.1.2 | — | ❌ Deferred (needs PlanarStrategyTools merged; PlanarOptim is in `[extras]`) |
| PlanarStrategies (8 pkgs) | — | ⏳ Registrator comments posted on commit `5f9154b` (2026-10-04): BollingerBands, Example, MarginStrat, RandomStratIso, SimpleStrategy, TickStrat, TwoIntervals, TwoParameters — **BLOCKED: JuliaRegistrator app silent on this repo (not installed); org admin must install `juliateam-registrator` on `BubbleParticles/PlanarStrategies`** |
| PlanarStrategies (4 pkgs) | — | ❌ Deferred: BBWithOpt + ExampleMargin (need PlanarOptim merged); QuickStart + StrategyFramework (need PlanarStrategyTools merged) |

## After registration

- Merge the open PRs on `JuliaRegistries/General` (manual review required; only `Planar` qualifies for automerge due to repo URL matching)
- After merge, re-trigger `@JuliaRegistrator` for the next dependency level
- **BLOCKER (2026-10-04):** the JuliaRegistrator app responds on `BubbleParticles/Planar.jl` but is NOT installed on `BubbleParticles/PlanarStrategies` — 8 trigger comments posted on `5f9154b` received zero bot replies in 5+ min (monorepo replies arrived in <90 s). An org admin must install the `juliateam-registrator` GitHub App on the repo (GitHub Apps → juliateam-registrator → Configure → add repo). API installation is impossible with a user PAT (HTTP 403 "must authenticate with an access token authorized to a GitHub App"). After installation, re-post the 8 `@JuliaRegistrator register subdir=<pkg>` comments on the tagged commit.
- Verify with a fresh environment:
  ```julia
  using Pkg
  Pkg.Registry.add(RegistrySpec(url="https://github.com/BubbleParticles/PlanarRegistry.git"))
  Pkg.add("Planar")
  ```
