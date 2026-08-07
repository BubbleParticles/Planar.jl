# release-planar

Trigger: user asks to publish or update the Planar Julia registry (`PlanarRegistry`),
release a new version to `Pkg.add("Planar")` users, or publish/update the PyPI
package (`planar-trader`).

Follow-up: after the release, verify with a fresh-environment install
(see Verification below); report the tag and the registry commit.

## Where to run

Run **everything from the `Planar.jl` monorepo root** (the source of truth):

- `scripts/register.jl` reads the git refs and computes tree SHAs from the repo
  you invoke it in, and writes the registry into `PlanarRegistry/` **inside the
  monorepo**. It must run in `Planar.jl`, never anywhere else.
- The `github.com/BubbleParticles/PlanarRegistry.git` repository is only the
  **push target**: `register.jl --commit` git-inits and commits the registry
  directory for you, then you push it with a plain `git push` from
  `Planar.jl/PlanarRegistry/`.

## Julia registry release flow

1. **Bump and tag** (clean working tree required — errors otherwise):
   ```bash
   bash .agents/skills/release-version/release-version.sh --patch   # or --minor/--major
   ```
   This bumps `Planar/Project.toml`, syncs all sub-project manifests, commits,
   and tags `v<version>`. Do NOT remove `recurse_projects` from `scripts/tag.jl`.
2. **Push the tag and branch** — users download tarballs for the tree SHA, so
   the commit must be on GitHub before the registry references it:
   ```bash
   git push origin master --tags
   ```
3. **Regenerate the registry** from the monorepo root:
   ```bash
   julia scripts/register.jl --ref v<version> --commit
   ```
   - `--ref v<version>` pins the tree SHAs to the tagged commit (default: HEAD).
   - `--commit` git-inits the `PlanarRegistry/` dir (if needed) and commits the
     updated registry.
   - Registry is additive: old versions stay in `Versions.toml`, existing users
     keep working.
   - Other flags: `--registry <path>` (output elsewhere), `--repo-url <url>`
     (override the monorepo URL), `--registry-repo <url>` (override the registry
     repo URL).
4. **Publish the registry**:
   ```bash
   cd PlanarRegistry
   git push                       # first time: git remote add origin https://github.com/BubbleParticles/PlanarRegistry.git && git push -u origin master
   cd ..
   ```

Users then install with:
```julia
using Pkg
Pkg.Registry.add(RegistrySpec(url="https://github.com/BubbleParticles/PlanarRegistry.git"))
Pkg.add("Planar")
```

## PyPI release flow (`planar-trader`)

1. **Bump `planar-py/pyproject.toml`** version (keep in sync with the Julia
   release or bump independently).
2. **Run the tests and build before publishing**:
   ```bash
   cd planar-py
   .venv-test/bin/python -m pytest -q          # 8 hermetic tests, no julia needed
   uv build                                     # dist/planar_trader-<v>-py3-none-any.whl + .tar.gz
   ```
3. **Publish** — either path:
   - Manual: `cd planar-py && uv publish` (uses PyPI token/OIDC).
   - CI (`.github/workflows/pypi.yml`): tag `py-v<version>` → TestPyPI, tag
     `v<version>` → PyPI (trusted publishing via OIDC; enabled once in the PyPI
     project settings for `BubbleParticles/Planar.jl`).
     ```bash
     git tag py-v0.1.1 && git push origin py-v0.1.1   # TestPyPI
     git tag v1.7.2 && git push origin v1.7.2         # PyPI
     ```
   - Note: the PyPI distribution name is `planar-trader` (`planar` is taken);
     the CLI is `planar`, import is `planar_trader`.

## Verification

- **Registry**: fresh project, `julia --project=/tmp/x -e 'using Pkg; Pkg.Registry.add(RegistrySpec(url="https://github.com/BubbleParticles/PlanarRegistry.git")); Pkg.add("Planar")'`, then `using Planar` must load.
- **pip**: fresh venv `uv pip install dist/planar_trader-<v>-*.whl` then `planar version` and `planar run --help` must work.

## Constraints

- `scripts/register.jl` runs only in the monorepo (it computes tree SHAs via
  `git rev-parse <ref>:<subdir>`). Never run it from the PlanarRegistry repo.
- Push the tag/branch **before** publishing the registry — Pkg downloads the
  subtree tarball from the pushed tree SHA.
- The registry is append-only; never delete old versions.
- Do NOT regenerate the package UUIDs (`a475c859-e357-4be2-a5e3-43038ab4b158`
  = PlanarCore, `799974c5-219d-476a-ada7-be492421c276` = FeatureSelection) —
  they are permanent identities.
- `PlanarRegistry/` is gitignored in the monorepo; its git history lives in the
  separate registry repo.

## General registry (one-time migration, not part of the update loop)

Registering in the General registry is a separate one-time effort (CompatHelper,
julia-compat widening, licenses, tree hygiene, per-package `@JuliaRegistrator
subdir=` PRs). See `PACKAGING.md` §1.4 for the full checklist.
