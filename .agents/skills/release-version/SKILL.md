# release-version

Trigger: `user asks to tag a new version, release, or bump the version number`

Bumps the Planar version in `Planar/Project.toml`, syncs all sub-project manifests, commits, and tags.

## Usage

### Via the shell wrapper (simplest, records output)

```bash
bash .agents/skills/release-version/release-version.sh [--major|--minor|--patch]
```

- `--patch` (default): bump patch — `1.6.11 → 1.6.12`
- `--minor`:               bump minor — `1.6.11 → 1.7.0`
- `--major`:               bump major — `1.6.11 → 2.0.0`

### Via Julia directly (use for programmatic or inline invocation)

The underlying function `tag_repo` in `scripts/tag.jl` accepts keyword arguments:

```bash
# Bump minor
julia --project=. -e 'include("scripts/tag.jl"); tag_repo(minor=1, patch=0)'

# Bump patch (default)
julia --project=. -e 'include("scripts/tag.jl"); tag_repo()'

# Bump major
julia --project=. -e 'include("scripts/tag.jl"); tag_repo(major=2, minor=0, patch=0)'
```

Keyword args `major`, `minor`, `patch` override the auto-detected current version.
Only the highest-level arg is needed: `tag_repo(minor=1, patch=0)` bumps minor. `tag_repo(patch=1)` bumps patch.

## Constraints

- **Working directory must be clean** — the script errors if there are uncommitted changes.
- **Do NOT remove `recurse_projects` from `scripts/tag.jl`**: syncing all project manifests is required for correct dependency resolution after a version bump. If `Pkg.resolve()` fails, fix the root cause (stale compat bounds, missing entries in manifests), don't skip the traversal.
- **Excluded from traversal**: `test`, `docs`, `deps`, `.conda`, `.CondaPkg`, `.git`, `user`, `PlanarOptim`, `Plotting` — these contain external packages that may not be resolvable in this workspace.

## After tagging — also create the GitHub release

After running the release script (which creates the `v<version>` tag), create the
corresponding GitHub release so the release page stays in sync:

```bash
gh release create v<version> --repo BubbleParticles/Planar.jl --title "v<version>" --notes "Release notes"
```

Then proceed with the registry and PyPI steps in `release-planar`.
