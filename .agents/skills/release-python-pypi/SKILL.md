# release-python-pypi

**Trigger:** User asks to release a Python package to PyPI/TestPyPI, publish Python wheels, or trigger PyPI workflow.

## Overview

The Planar.jl monorepo contains two Python packages released to PyPI:

| Package | Path | PyPI Name | Workflow |
|---------|------|-----------|----------|
| **ccxt-gateway** | `ccxt-gateway/` | `ccxt-gateway` | `pypi-ccxt.yml` |
| **planarjl-py** | `planarjl-py/` | `planarjl-py` | `pypi.yml` |

Both use **hatchling + hatch-vcs** for versioning (version derived from git tags) and **GitHub Actions trusted publishing** (OIDC, no API tokens needed).

## Versioning

- Version is **dynamic** (`dynamic = ["version"]` in `pyproject.toml`)
- `hatch-vcs` reads version from **git tags** matching `v*` or `py-v*`
- Tag format: `v1.2.3` (production) or `py-v1.2.3` (TestPyPI)
- The workflow verifies the wheel version matches the tag

## Release Process

### Prerequisites (one-time setup)

1. **PyPI trusted publishing** configured for each package:
   - Go to PyPI → Project settings → Publishing → "Add a new trusted publisher"
   - Owner: `BubbleParticles`, Repository: `Planar.jl`
   - Workflow name: `pypi-ccxt` (for ccxt-gateway) or `pypi` (for planarjl-py)
   - Environment: `pypi` (or `testpypi` for test)

2. **GitHub Environments** created:
   - `pypi` (required for production publish)
   - `testpypi` (required for TestPyPI publish)

3. **PyPI project exists** (first release creates it automatically via trusted publishing)

### To release to TestPyPI

```bash
# From repo root
git tag py-v1.2.3
git push origin py-v1.2.3
```

This triggers the workflow with `if: startsWith(github.ref, 'refs/tags/py-v')` → publishes to TestPyPI.

### To release to PyPI (production)

```bash
# From repo root
git tag v1.2.3
git push origin v1.2.3
```

This triggers the workflow with `if: startsWith(github.ref, 'refs/tags/v') && !startsWith(github.ref, 'refs/tags/py-v')` → publishes to PyPI.

### Release both packages together

```bash
# Tag once, both workflows trigger (they both match v*)
git tag v1.2.3
git push origin v1.2.3
```

## Workflow Details

Both workflows (`.github/workflows/pypi.yml` and `pypi-ccxt.yml`) have identical structure:

1. **build** job:
   - Checks out with `fetch-depth: 0` (needed for `hatch-vcs` to read git history)
   - Sets up Python 3.12
   - Runs `python -m build --outdir ../dist` in the package directory
   - Verifies wheel version matches git tag
   - Uploads `dist/` as artifact

2. **publish-testpypi** job (runs on `py-v*` tags):
   - Downloads artifact
   - Publishes to TestPyPI via `pypa/gh-action-pypi-publish@release/v1`
   - Uses `environment: testpypi` + OIDC trusted publishing

3. **publish-pypi** job (runs on `v*` tags, not `py-v*`):
   - Downloads artifact
   - Publishes to PyPI via `pypa/gh-action-pypi-publish@release/v1`
   - Uses `environment: pypi` + OIDC trusted publishing

## Manual Build & Test (local)

```bash
cd ccxt-gateway
pip install build
python -m build --outdir dist
# Check artifacts
ls dist/
# Install locally for testing
pip install dist/ccxt_gateway-*.whl
ccxt-gateway --help
```

```bash
cd planarjl-py
pip install build
python -m build --outdir dist
pip install dist/planarjl_py-*.whl
planar --help
```

## Version Verification

The workflow extracts version from the wheel's `METADATA` and compares to the tag:

```bash
tag_ver="${GITHUB_REF_NAME#py-v}"   # strip py-v prefix
tag_ver="${tag_ver#v}"              # strip v prefix
wheel_ver="$(unzip -p dist/*.whl '*/METADATA' | sed -n 's/^Version: //p')"
if [ "$wheel_ver" != "$tag_ver" ]; then exit 1; fi
```

This ensures `hatch-vcs` correctly read the tag.

## Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| "Version mismatch" | Tag format wrong or hatch-vcs couldn't read tag | Ensure tag is `vX.Y.Z` or `py-vX.Y.Z`, `fetch-depth: 0` in checkout |
| "No trusted publisher" | PyPI trusted publishing not configured | Add trusted publisher in PyPI project settings |
| "Environment not found" | GitHub environment `pypi`/`testpypi` missing | Create environments in repo settings |
| "Build fails" | Missing dependencies or Python version | Check `pyproject.toml` `requires-python` and `dependencies` |

## Related Skills

- [`release-version`](../release-version/SKILL.md) — Julia package versioning and release
- [`release-planar`](../release-planar/SKILL.md) — Planar monorepo coordinated release
- [`register-packages`](../register-packages/SKILL.md) — Julia package registration to General registry

## File Reference

- `ccxt-gateway/pyproject.toml` — ccxt-gateway build config
- `planarjl-py/pyproject.toml` — planarjl-py build config
- `.github/workflows/pypi-ccxt.yml` — ccxt-gateway PyPI workflow
- `.github/workflows/pypi.yml` — planarjl-py PyPI workflow