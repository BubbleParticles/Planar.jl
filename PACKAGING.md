# Packaging & Distribution

Planar is distributed through two channels:

| Channel | Artifact | Users |
|---|---|---|
| Julia registry | `Planar` + 8 companion packages (custom registry, General later) | `Pkg.add("Planar")` |
| PyPI | `planarjl-py` (Python driver for the Julia engine) | `pip install planarjl-py` |

The repository is a monorepo: nine Julia packages live in subdirectories
(`Planar/`, `PlanarCore/`, …) and the Python driver lives in `planarjl-py/`.

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
so users only need `Pkg.add("Planar")`. Status and remaining requirements:

1. **`[compat]` entries — DONE locally, keep fresh with CompatHelper.** Every
   dependency needs an upper-bounded `[compat]` entry (RegistryCI automerge
   rejects unbounded entries: `"0"` alone, `">=3"`). Entries for all external
   deps were filled from the resolved manifests (repo convention: full resolved
   version, e.g. `HTTP = "1.11.0"`), and `.github/workflows/CompatHelper.yml`
   was added (runs nightly, `subdirs = [ ...9 packages... ]`) to keep them in
   sync with new releases. Merge its PRs regularly.
2. **Broaden `julia` compat — PENDING CI proof.** Packages currently declare
   `julia = "1.12"`. General prefers wider ranges (e.g. `1.9`–`1.12`). Loosen
   after CI proves older versions work.
3. **License — DONE.** The project license is **Apache-2.0** (root `LICENSE.md`,
   *not* MIT). RegistryCI automerge requires an OSI-approved license file in the
   top-level directory of each package tree; `LICENSE.md` (Apache text) was
   copied into all 9 package dirs and `license = "Apache-2.0"` added to every
   `Project.toml`.
4. **Package names — collisions resolved by renaming (audited against 14,110
   General packages with the RegistryCI Damerau–Levenshtein checks):**
   - `FeatureSelection` **already exists in General** (JuliaAI/FeatureSelection.jl,
     uuid `33837fe5-…`) — hard collision (distance 0). **Renamed to
     `PlanarFeatureSelection`** (uuid unchanged, `799974c5-…`); min distance to
     any General name is now 6.
   - `Python` failed the similarity check (raw distance 1 to `IPython`).
     **Renamed to `PlanarPython`** (uuid unchanged, `e8cdc95d-…`); min distance
     is now 5 (to `OlivePython`) — no override label needed.
   - All 9 names pass the distance checks (re-verified after the renames).
5. **Tree hygiene.** `Manifest.toml`/`LocalPreferences.toml` inside the registered
   trees are inert for installation and are **not** gated by RegistryCI
   automerge (no tarball/Manifest check exists there). Note: `PlanarCore`'s
   committed `Manifest.toml` was stale (referenced a removed `../Metrics` dev
   path) and was regenerated; regenerate all manifests before the first
   registration so they match their `Project.toml` files. Optionally gitignore
   them for cleaner tarballs.
6. **Register per package**, in dependency order, with
   [Registrator](https://juliaregistries.github.io/Registrator.jl/stable/):
   comment on the commit/PR
   `@JuliaRegistrator register subdir=PlanarCore` (exact monorepo syntax,
   confirmed in the Registrator README) — repeat for each package.
   Order: `PlanarCore` → `PlanarStrategyStats` → `Planar` → `PlanarFeatureSelection` →
   `PlanarDownloadTool` → `PlanarPython` → `PlanarStrategyTools` → `PlanarOptim` → `PlanarDev`.
   Caveat: automerge's "repo URL ends with `/Name.jl.git`" check only matches
   `Planar` (the monorepo is `Planar.jl`); the other packages go through manual
   registry review — normal for monorepo subdir registrations.
7. **UUIDs — DONE, keep stable.** `PlanarCore`'s old UUID (`a1b2c3d4-…`)
   collided with the registered `WildlandFire` package, so it (and
   PlanarFeatureSelection's placeholder) were replaced with freshly generated UUIDs
   (commit `29ab5a27`): PlanarCore `a475c859-e357-4be2-a5e3-43038ab4b158`,
   PlanarFeatureSelection `799974c5-219d-476a-ada7-be492421c276`. They are the
   packages' permanent identities — never regenerate.

### 1.5 Development inside the repo

Local development is unaffected: each package's `[sources]` section pins internal
deps to sibling directories, and `Pkg.instantiate()` uses the checked-in manifests.
`[sources]` in a *dependency's* Project.toml is ignored by Pkg, so the registry
install (no `[sources]`) resolves internal deps from the registry.

---

## 2. pip distribution (`planarjl-py`)

`pip install planarjl-py` provides the `planar` CLI, which drives the Planar
Julia engine (backtests, strategy runs) from Python. The PyPI name `planar` is
taken by an unrelated package, hence `planarjl-py`.

> Note: native *strategy authoring in Python* (the item #7 milestone) does not
> exist yet — strategies are written in Julia and executed through the CLI. The
> package is built so a future `pyplanar` strategy API can ship inside it.

### 2.1 Building the package

```bash
cd planarjl-py
uv build            # or: python -m build
# dist/planarjl_py-<version>-py3-none-any.whl, dist/planarjl_py-<version>.tar.gz
```

### 2.2 Publishing to PyPI

```bash
cd planarjl-py
uv publish --publish-url https://upload.pypi.org/legacy/   # test: https://test.pypi.org/legacy/
```
or, with a PyPI API token:
```bash
uv publish --token "$(cat ~/.pypi-token)"
```

CI does this automatically. Two tag-triggered workflows, one per package —
PyPI allows a trusted publisher configuration (repository + workflow +
environment) on **exactly one** project, so a single workflow cannot publish
both packages:

| Workflow | Package | TestPyPI (`py-v*` tags) | PyPI (`v*` tags) |
|---|---|---|---|
| `pypi.yml` | `planarjl-py` | job `publish-testpypi` (env `testpypi`) | job `publish-pypi` (env `pypi`) |
| `pypi-ccxt.yml` | `ccxt-gateway` | job `publish-testpypi` (env `testpypi`) | job `publish-pypi` (env `pypi`) |

Auth is PyPI *trusted publishing* (OIDC). For each project on each index
("Publishing" → add a pending publisher): GitHub, repository
`BubbleParticles/Planar.jl`, **workflow name = the workflow file from the
table**, environment as in the table — four registrations total. The first
successful upload activates a pending publisher.

Token auth remains as the fallback: repository secrets `PYPI_API_TOKEN` and
`TESTPYPI_API_TOKEN` are still set. To switch a workflow back to tokens, add
`password: ${{ secrets.PYPI_API_TOKEN }}` (resp. `TESTPYPI_API_TOKEN` for the
testpypi job) to the publish step and drop the job's
`permissions: id-token: write`. PyPI and TestPyPI are separate accounts — each
token only works on its own index.

**The tag determines the published version** (both packages derive their version
from the nearest git tag via hatch-vcs; `py-v1.2.3` → version `1.2.3`, `v1.2.3` →
`1.2.3`). **Versions are synced to the Planar Julia release**: use the same
version as the Planar Julia package (currently `1.8.0`, bumped by
`scripts/tag.jl`), so `planarjl-py`, `ccxt-gateway` and `Planar` all carry the
same version. Keep the `ccxt-gateway>=X.Y.Z` dependency floor in
`planarjl-py/pyproject.toml` in step with that version. The tag must be a valid
PEP 440 version — do not reuse a version that was already published to the
target index, PyPI rejects duplicate versions. Untagged builds (e.g. local
`uv build`) get a `X.Y.Z.devN+g<sha>` dev version. Both workflows verify the
built wheel version matches the tag and fail the build on mismatch.

```bash
git tag py-v1.8.0 && git push origin py-v1.8.0   # TestPyPI
git tag v1.8.0 && git push origin v1.8.0         # PyPI (also triggers docker + registry flows)
```

### 2.3 Using the package

```bash
pip install planarjl-py
planar init mybot            # create a project, add the registry, Pkg.add("Planar")
cd mybot
planar run MyStrategy --mode sim --exchange binanceusdm --sandbox
planar version
```

`planar init` requires Julia ≥ 1.12 on `PATH`. See `planarjl-py/README.md` for the
full CLI reference.
