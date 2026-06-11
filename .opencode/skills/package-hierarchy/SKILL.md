---
name: package-hierarchy
description: Use when asked to show the package dependency hierarchy, architecture overview, or dependency tree of the repository. Prints all first-party Julia packages with their tiers and local dependencies, excluding user strategies.
---

# Package Hierarchy

Returns a tiered dependency hierarchy of all first-party Julia packages in the repository, excluding user strategies (`user/`), vendored packages (`vendor/`), and internal helpers (`deps/`, `docs/`).

## Usage

From the repository root:

```bash
# Indented text output (default)
julia .opencode/skills/package-hierarchy/package-hierarchy.jl

# Graphviz DOT format (for rendering with graphviz)
julia .opencode/skills/package-hierarchy/package-hierarchy.jl --dot | dot -Tpng -o deps.png

# Specify a different repo root
julia .opencode/skills/package-hierarchy/package-hierarchy.jl /path/to/repo
```

## What it includes

All directories with a `Project.toml` containing a `name` field, EXCEPT:

- `user/` — user strategies (e.g. `BBWithOpt`, `BollingerBands`, `SimpleStrategy`, etc.)
- `vendor/` — third-party vendored packages
- `deps/` — internal dependency helpers
- `docs/` — documentation projects
- Hidden directories (`.` prefix)

## Output format

Packages are grouped into tiers:

- **Tier 1**: Foundation packages with no local dependencies
- **Tier N+1**: Packages whose all local dependencies are in tiers ≤ N

Each tier lists packages and their local dependency names. External/public dependencies are omitted.
