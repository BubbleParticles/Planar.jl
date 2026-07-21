---
name: precomp-sideeffect-persistence
description: "Warn when eval/codegen into Main or other closed modules is introduced without guarding for incremental precompilation"
condition: "@eval\\s+Main|breaks incremental compilation|side effects won't be permanent|Evaluation into the closed module|Creating a new global in closed module|__revise_mode__\\s*=\\s*:eval|eval\\(.{0,40}Main"
scope: ["tool:edit(*.jl)", "tool:write(*.jl)", "tool:grep(*.jl)"]
---

Any code that evals into `Main` (or another closed module), defines new globals, or performs side effects during precompilation will NOT persist across the incremental compilation boundary — Julia silently drops it and emits `... breaks incremental compilation` / `side effects won't be permanent`. This surfaces in package source as `@eval Main begin ... end`, `@eval Main using ...`, or `__revise_mode__ = :eval`. Fix: (1) move the side effect to `__init__()` (runs at runtime, allowed), (2) interpolate already-imported bindings (`$Pkg`) instead of `using` inside the eval, or (3) wrap in `if !Base.generating_output()` so it is skipped during precompilation. Never introduce `@eval Main begin using ... end` in package source. Verify with a real precompile run (`julia --project=. -e 'using Pkg; Pkg.precompile()'` without `--compiled-modules=no`).