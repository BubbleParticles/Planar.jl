# Skills

## [release-planar/](./release-planar/) — `SKILL.md`

Publishes Planar updates: regenerates the custom Julia registry
(`scripts/register.jl`, then push `PlanarRegistry/`) and publishes the
`planarjl-py` PyPI package.

**Usage:** bump+tag with `release-version`, then `julia scripts/register.jl --ref v<version> --commit`
from the monorepo root, push the registry, then `uv publish` or tag-based CI.
See [SKILL.md](./release-planar/SKILL.md) for the full flow and verification.

## [release-version/](./release-version/) — `SKILL.md`

Bumps the Planar version, syncs all project manifests, commits, and tags.

**Usage:** `bash .agents/skills/release-version/release-version.sh [--major|--minor|--patch]`
or `julia -e 'include("scripts/tag.jl"); tag_repo(minor=1, patch=0)'`.
See [SKILL.md](./release-version/SKILL.md) for full details.

**Constraint — DO NOT remove `recurse_projects` from `scripts/tag.jl`:**
The tag script must call `recurse_projects` after bumping the version to sync
all project manifests. If `Pkg.resolve()`/`Pkg.update()` fails (e.g. due to
external packages with conflicting compat bounds), fix the **root cause** —
update stale compat entries, fix manifest versions, or make `_update_project`
respect the `doupdate` flag — rather than removing the recurse_projects call.

## [conventional-commits/](./conventional-commits/SKILL.md) — `SKILL.md`

Formats commit messages according to Conventional Commits spec.

## [daemon-mode/](./daemon-mode/SKILL.md) — `SKILL.md`

Manages a persistent Julia daemon via DaemonMode.jl to avoid startup overhead.

## [purge_compilecache/](./purge_compilecache/SKILL.md) — `SKILL.md`

Clears Julia's compiled cache to resolve precompilation issues.

## [testing-strategy/](./testing-strategy/SKILL.md) — `SKILL.md`

Patterns for running tests efficiently across the monorepo.

## [update_projects/](./update_projects/SKILL.md) — `SKILL.md`

Runs `update_projects()` from resolve.jl to sync all project dependencies.
