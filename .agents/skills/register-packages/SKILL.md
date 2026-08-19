# register-packages

**Trigger:** User asks to register Julia packages to the Julia registry, publish packages, or run `@JuliaRegistrator`.

## Overview

Registers monospace Julia packages to the custom `PlanarRegistry` (and optionally General) by triggering `@JuliaRegistrator` on GitHub. `PlanarCore` is already on the General registry and is **not** re-registered here (see `PACKAGING.md` §1.4).

## Registration order

After `PlanarCore` (on General), packages are registered in dependency order:

1. **PlanarStrategyStats**
2. **Planar**
3. **PlanarFeatureSelection**
4. **PlanarDownloadTool**
5. **PlanarPython**
6. **PlanarStrategyTools**
7. **PlanarOptim**
8. **PlanarDev**

This order is sourced from `scripts/register.jl` (`PACKAGES` constant). Each package's deps are already in the registry by the time it is registered.

`PlanarStrategies` (external, at `github.com/BubbleParticles/PlanarStrategies`) is registered separately at the end — strategies depend on the engine, not vice versa.

## Usage

### Via the shell wrapper (simplest, records output)

```bash
# Register all packages in order
bash .agents/skills/register-packages/register-packages.sh

# Register specific packages only (in the order given)
bash .agents/skills/register-packages/register-packages.sh Planar PlanarDev
```

### Via Registrator comment directly (manual)

Comment on the tagged commit (or PR) in `BubbleParticles/Planar.jl`:

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
- **Non-General weakdeps block extensions** — Registrator validates UUIDs in `[weakdeps]`/`[extensions]` against General. Packages not in General (e.g. `CausalityTools`, `EffectSizes` in `PlanarStrategyStats`) cause registration to fail. Fix: **remove the `[extensions]`/`[weakdeps]` blocks entirely** and delete the extension file, since (a) `Pkg.test` cannot resolve non-General extras either, and (b) the extension code degrades gracefully when the functions are unavailable (e.g. `gridbbands`'s `corr::Symbol` arg falls back to no post-processing). Do NOT move to `[extras]`/`[targets]` — `Pkg.test` will still fail trying to resolve them. Check a package's deps against General with: `julia -e 'using Pkg; r=Pkg.Registry.reachable_registries()[1]; println(haskey(r, UUID("...")) ? "FOUND" : "MISSING")'`.
- **Compat entries must be present** — `julia`, each external `[dep]`, and each `[weakdeps]` entry must have a `[compat]` row. Missing compat triggers a Registrator error.
- **`test/Project.toml` must not have `name`/`uuid`/`version`/`authors`** — Registrator treats such files as nested packages and fails precompilation.
- **Do NOT regenerate UUIDs** — they are permanent identities (see `PACKAGING.md` §1.4.7).

## After registration

- Registrator auto-creates a PR on the target registry (`General` or `PlanarRegistry`)
- Merge the PR (automerge usually handles this if compat/license/name checks pass)
- Verify with a fresh environment:
  ```julia
  using Pkg
  Pkg.Registry.add(RegistrySpec(url="https://github.com/BubbleParticles/PlanarRegistry.git"))
  Pkg.add("Planar")
  ```
