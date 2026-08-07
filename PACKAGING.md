# Packaging & Distribution

Planar is distributed through two channels:

| Channel | Artifact | Users |
|---|---|---|
| Julia registry | `Planar` + 8 companion packages (custom registry, General later) | `Pkg.add("Planar")` |
| PyPI | `planar-trader` (Python driver for the Julia engine) | `pip install planar-trader` |

The repository is a monorepo: nine Julia packages live in subdirectories
(`Planar/`, `PlanarCore/`, …) and the Python driver lives in `planar-py/`.

---

## 1. Julia registry

### 1.1 How it works

None of the packages are in the General registry, so `Pkg.add("Planar")` needs a
custom registry that points at this monorepo. The registry uses the same mechanism
as General-registry monorepos (`subdir` entries, e.g. `AppEnv`, `ACEradials`):

- each `Package.toml` sets `repo = "https://github.com/BubbleParticles/Planar.jl.git"`
  and `subdir = "Planar"` (the package directory in the monorepo);
- each version in `Versions.toml` records `git-tree-sha1` — the SHA of the package
  *subtree* at the tagged commit (`git rev-parse <tag>:<subdir>`);
- Pkg downloads the subtree tarball from
  `https://api.github.com/repos/BubbleParticles/Planar.jl/tarball/<git-tree-sha1>`
  (GitHub serves tarballs for arbitrary tree SHAs), so the archive contains exactly
  the package — no subdir extraction needed.

`scripts/register.jl` generates the registry (`PlanarRegistry/` directory in this
repo) from the git tree. It is a plain git repository that gets pushed to
`https://github.com/BubbleParticles/PlanarRegistry.git`.

### 1.2 First-time setup (once)

1. Create the registry repo on GitHub:
   ```bash
   gh repo create BubbleParticles/PlanarRegistry --public
   ```
2. Generate the registry and publish it:
   ```bash
   julia scripts/register.jl --commit
   cd PlanarRegistry
   git remote add origin https://github.com/BubbleParticles/PlanarRegistry.git
   git push -u origin master
   ```

Users then install Planar with:

```julia
using Pkg
Pkg.Registry.add(RegistrySpec(url="https://github.com/BubbleParticles/PlanarRegistry.git"))
Pkg.add("Planar")          # or Pkg.add(["Planar", "PlanarOptim"])
```

### 1.3 Releasing a new version

1. Bump versions and tag — `scripts/tag.jl` bumps `Planar`'s version, propagates it
   to all dependent projects, commits and tags (`v<version>`):
   ```bash
   julia scripts/tag.jl            # patch bump (default)
   julia scripts/tag.jl --minor    # or --major
   ```
2. Push the tag and branch:
   ```bash
   git push origin master --tags
   ```
3. Regenerate the registry and publish it:
   ```bash
   julia scripts/register.jl --ref v<version> --commit
   cd PlanarRegistry
   git add -A && git commit -m "register v<version>" && git push
   ```
   The registry is additive — old versions stay in `Versions.toml`, so existing
   users keep working after an update.

### 1.4 Registering in the General registry (optional, recommended)

A custom registry is the fast path, but the long-term goal is the General registry
so users only need `Pkg.add("Planar")`. Requirements and steps:

1. **All dependencies need `[compat]` entries.** Compat exists for the internal
   packages; run [CompatHelper](https://github.com/JuliaRegistries/CompatHelper.jl)
   in CI (a `compat` workflow with `CompatHelper` action, triggered on a schedule
   and on PRs) to fill the external ones from the resolved manifest.
2. **Broaden `julia` compat.** Packages currently declare `julia = "1.12"`; General
   prefers wider ranges (e.g. `1.9`–`1.12`). Loosen after CI proves older versions
   work.
3. **License** must be declared (root `LICENSE.md` is MIT; each `Project.toml`
   should carry `license` metadata and the license file must be included in the
   package trees).
4. **Tree hygiene.** The registered tarball is the *tracked* subtree — `Manifest.toml`
   and `LocalPreferences.toml` inside package directories ship in the archive. They
   are inert for installation, but General's `RegistryCI` cleaning pass prefers
   tarballs without them; consider gitignoring/removing them from the package dirs.
5. **Register per package**, in dependency order, with
   [Registrator](https://juliaregistries.github.io/Registrator.jl/stable/):
   open a PR adding each package's subtree (`subdir` set to the package dir), or
   trigger the bot with `@JuliaRegistrator register subdir=PlanarCore`, etc. The
   bot creates the registry entry and tarball URL from the monorepo automatically.
   Order: `PlanarCore` → `StrategyStats` → `Planar` → `FeatureSelection` →
   `DownloadTool` → `Python` → `StrategyTools` → `PlanarOptim` → `PlanarDev`.
6. **UUIDs.** `PlanarCore`'s old UUID (`a1b2c3d4-…`) collided with the registered
   `WildlandFire` package, so it (and FeatureSelection's placeholder) were replaced
   with freshly generated UUIDs (commit `29ab5a27`). Keep the new UUIDs stable from
   here on — they are the packages' permanent identities.

### 1.5 Development inside the repo

Local development is unaffected: each package's `[sources]` section pins internal
deps to sibling directories, and `Pkg.instantiate()` uses the checked-in manifests.
`[sources]` in a *dependency's* Project.toml is ignored by Pkg, so the registry
install (no `[sources]`) resolves internal deps from the registry.

---

## 2. pip distribution (`planar-trader`)

`pip install planar-trader` provides the `planar` CLI, which drives the Planar
Julia engine (backtests, strategy runs) from Python. The PyPI name `planar` is
taken by an unrelated package, hence `planar-trader`.

> Note: native *strategy authoring in Python* (the item #7 milestone) does not
> exist yet — strategies are written in Julia and executed through the CLI. The
> package is built so a future `pyplanar` strategy API can ship inside it.

### 2.1 Building the package

```bash
cd planar-py
uv build            # or: python -m build
# dist/planar_trader-<version>-py3-none-any.whl, dist/planar_trader-<version>.tar.gz
```

### 2.2 Publishing to PyPI

```bash
cd planar-py
uv publish --publish-url https://upload.pypi.org/legacy/   # test: https://test.pypi.org/legacy/
```
or, with a PyPI API token:
```bash
uv publish --token "$(cat ~/.pypi-token)"
```

CI does this automatically: the `.github/workflows/pypi.yml` workflow builds the
package, publishes to TestPyPI on tags matching `py-v*`, and to PyPI on `v*`
tags. Publishing uses PyPI *trusted publishing* (OIDC) — enable it once in the
PyPI project settings ("Publishing" → add the GitHub repository
`BubbleParticles/Planar.jl` as a trusted publisher for the `planar-trader`
project). A `PYPI_API_TOKEN` secret also works if you prefer token auth.

```bash
git tag py-v0.1.0 && git push origin py-v0.1.0   # TestPyPI
git tag v1.7.2 && git push origin v1.7.2         # PyPI (also triggers docker + registry flows)
```

### 2.3 Using the package

```bash
pip install planar-trader
planar init mybot            # create a project, add the registry, Pkg.add("Planar")
cd mybot
planar run MyStrategy --mode sim --exchange binanceusdm --sandbox
planar version
```

`planar init` requires Julia ≥ 1.12 on `PATH`. See `planar-py/README.md` for the
full CLI reference.
