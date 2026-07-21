---
name: jl-precompile-verification
description: "Require precompilation verification after modifying Julia package source files"
condition: "tool:(write|edit)\\(\\\".*\\\\.jl\\\""
scope: ["tool:write(*.jl)", "tool:edit(*.jl)"]
---

After modifying any Julia package source file (*.jl), you MUST verify the package precompiles successfully before considering the task complete. Run:

```bash
julia --project=<pkg> -e 'using <PackageName>'
```

Or for the full dev environment:

```bash
julia --project=PlanarDev -e 'using Pkg; Pkg.precompile()'
```

Failures indicate parse errors, missing imports, or broken precompile workloads that must be fixed immediately. Never assume edits are correct without verification.