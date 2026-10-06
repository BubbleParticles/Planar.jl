---
name: no-version-bump-for-am-fixes
description: "Never bump the package version to fix an AutoMerge/Registrator complaint — fix compat bounds, dependencies, or code instead"
condition: "(?i)(\\bversion\\s+bump\\b|\\bbump(?:ing)?\\s+(?:the\\s+)?version\\b|\\bbump\\w*\\s+(?:\\S+\\s+)?to\\s+v?\\d+\\.\\d+(?:\\.\\d+)?)|version\\s*=\\s*\\\\?\"\\d+\\.\\d+(?:\\.\\d+)?\""
question: "Does the output propose or perform a package version bump as the remedy for an AutoMerge, Registrator, or other registry-complaint fix?"
scope: ["text", "tool:edit(**/Project.toml)", "tool:write(**/Project.toml)", "tool:bash(*)"]
---

## Don't bump the version to fix AutoMerge complaints

When AutoMerge or Registrator complains about a registration PR, fix the underlying cause — `[compat]` bounds, dependency constraints, `[sources]` removal, metadata, or code — never the version number.

- A bump creates a new tag, a new Registrator PR, and a fresh ~3-day new-package AutoMerge queue for every failure iteration.
- Bump-as-fix is off-limits in this workflow unless the user explicitly asks for a release. If a published tag forces a change, get explicit user approval first.
- Preferred remedies: widen/tighten `[compat]`, fix the code, register a fixed upstream dependency version, or re-run AutoMerge after an ecosystem-side fix.

Exception: changing `version =` in a Project.toml is legitimate only for a genuine, intentional release.

Note: bash-serialized arguments escape quotes as `\"` — a `version = "0.1.3"` written through sed/heredoc appears as `version = \"0.1.3\"`; the trigger's optional-backslash handles both forms.