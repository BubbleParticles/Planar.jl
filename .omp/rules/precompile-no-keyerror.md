---
name: precompile-no-keyerror
description: "Never let precompile workloads raise KeyError — guard dict/attrs access during precompilation"
condition: "KeyError|generating_output|JULIA_PRECOMP|precompile\\.jl|__init__|attr\\(.*, :|d\\[:"
scope: ["tool:edit(*.jl)", "tool:write(*.jl)"]
---

During `__init__`/`precompile.jl` workloads (running under `JULIA_PRECOMP` / `Base.generating_output()`), package state is NOT populated — dicts/attrs that are filled at runtime are empty. A bare `d[:key]`, `attr(w, :key)`, or `getproperty` that assumes a key exists will raise `KeyError` and abort precompilation (a hard crash, not a runtime warning).

Fix root cause:
- Guard with `get(dict, :key, default)` or `haskey(dict, :key) ? dict[:key] : fallback`.
- For attrs dicts accessed in precompile (e.g. `attr(w, :last_processed)`), ensure the key is initialized at construction or defaulted at access — AGENTS.md Gotcha #33 requires `:last_processed => nothing` in the attrs dict.
- Wrap optional precompile-only introspection in `try/catch` that logs via `@debug`/`@warn`, never lets the exception escape.

Do NOT silence by rescuing broadly and returning `nothing` silently when the value is actually required at runtime — instead initialize the key where the struct/attrs is created. Verify with a real precompile run (`julia --project=<pkg> -e 'using Pkg; Pkg.precompile()'`), not just `--compiled-modules=no`.