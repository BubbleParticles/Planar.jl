---
name: strategy-planar-source
description: "Strategy Project.toml must include Planar in [sources] when listed in [deps]"
condition: "\\[deps\\][\\s\\S]{0,400}\\bPlanar\\b[\\s\\S]{0,400}\\[sources\\][\\s\\S]{0,400}(?!\\s*Planar\\b)"
scope: ["tool:write(**/user/strategies/*/Project.toml)", "tool:edit(**/user/strategies/*/Project.toml)"]
---

When `Planar` appears in a strategy's `[deps]`, it must also appear in `[sources]` with a local `path` entry (e.g. `Planar = {path = "../../../Planar"}`). Without it, `Pkg.instantiate()` fails with "expected package Planar to be registered" and falls back to direct include, emitting a spurious warning. Either add the `[sources]` entry or use `Pkg.develop` to register the package locally in the strategy env.