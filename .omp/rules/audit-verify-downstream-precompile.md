---
name: audit-verify-downstream-precompile
description: "After an audit, verify the most-downstream packages PlanarDev and PlanarInteractive actually precompile (julia -e \"using PlanarDev\") with no 'skipping precompilation' warnings"
condition: "using PlanarDev|precompile successfully|audit complete|verification|working tree clean|all .* packages audited"
scope: "text"
---

At the end of every audit pass, do NOT stop at `git status` clean or per-package `using X` loads. The most-downstream packages are the real integration test. Run `julia -e "using PlanarDev"` (and `PlanarInteractive` under its own project) and confirm they precompile successfully end-to-end with NO warnings like "skipping precompilation". Per-package loads can pass while a downstream aggregate (PlanarDev/PlanarInteractive) still fails on a stale manifest, missing dep, or precompile workload. Report the actual `using PlanarDev` / `using PlanarInteractive` result — including any precompile-skip warnings — as the final verification, not just individual package loads.