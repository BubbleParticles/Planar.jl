---
name: julia-no-undeclared-import-warnings
description: "Never leave Julia `imported binding X was undeclared at import time` or `ignoring conflicting import` warnings unaddressed in committed code"
condition: ["was undeclared at import time", "ignoring conflicting import", "conflicts with an existing identifier"]
scope: ["tool:edit(*.jl)", "tool:write(*.jl)"]
---

Julia `using M: sym` / `import M: sym` warnings are real contract bugs, not noise:

- `Imported binding X was undeclared at import time` → the symbol does not exist in `M` at that name. Either the name is wrong, or you imported a macro-generated binding (e.g. `tf` from `@tf_str`) that only exists as a side effect — import the macro (`@tf_str`) instead, and drop the bare binding.
- `ignoring conflicting import` / `conflicts with an existing identifier` → a name you imported already exists in scope (often from another `using`). Rename one side, qualify the call, or drop the redundant import.

Fix at the source: correct the `using`/`import` line so the warning disappears. Do NOT silence it with `@warn` suppression or by ignoring it. Re-run `using <Pkg>` / `Pkg.test()` to confirm the warning is gone before yielding.