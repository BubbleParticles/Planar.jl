# Release Planar Skill

Use this skill to create a new release tag for Planar using `scripts/tag.jl`.

## Usage

```bash
# Patch release (default - increments patch version)
julia --project=Planar scripts/tag.jl

# Minor release
julia --project=Planar scripts/tag.jl -- minor

# Major release
julia --project=Planar scripts/tag.jl -- major

# Specific version
julia --project=Planar scripts/tag.jl -- major=2 minor=5 patch=0
```

## What it does

1. **Checks working directory** - fails if there are unstaged changes
2. **Bumps version** in `Planar/Project.toml`:
   - No args → patch+1
   - `minor` → minor+1, patch=0
   - `major` → major+1, minor=0, patch=0
   - Explicit args → set exact version
3. **Updates all local project.toml** recursively via `resolve.jl`'s `recurse_projects`
4. **Commits** with message `vX.Y.Z`
5. **Tags** with `vX.Y.Z`

## Pre-requisites

- Clean working directory (`git status --porcelain` empty)
- Planar project activated
- `resolve.jl` available (provides `recurse_projects`)

## Push the tag

After tagging, push to remote:

```bash
git push origin main --tags
```

## Notes

- The script activates `Planar` project internally
- All local project.toml files are updated (excluding test/docs/deps)
- Uses `git add -u` to stage only tracked files
- Tag format: `v<major>.<minor>.<patch>`