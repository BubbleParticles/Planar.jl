# update-projects

Trigger: dependency updates / resolving manifest conflicts.

Syncs all project dependencies across the monorepo by delegating to `resolve.jl`.

Usage: `update_projects.sh [--precomp --inst --doupdate] [path]`

Direct Julia invocation:
```julia
include("resolve.jl")
update_projects("."; doupdate=false, inst=false, precomp=false)
```

Notes: See `resolve.jl` for flag details.
