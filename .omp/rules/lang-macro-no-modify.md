---
name: lang-macro-no-modify
description: "Never modify core Lang macros (@lget!, @get, @multiget, @kget!) - handle JSON null→nothing at callsites"
condition: "(@lget!|@get|@multiget|@kget!)\\s*\\("
scope: ["tool:edit(Lang/src/*.jl)", "tool:write(Lang/src/*.jl)", "tool:ast_edit(Lang/src/*.jl)"]
---

The core Lang macros (@lget!, @get, @multiget, @kget!) are foundational utilities used throughout the codebase. Do NOT modify them to handle JSON `null` → `nothing` conversion. This conversion must be handled at the callsite (e.g., in `fromdict`, watchers, or API response handlers) where the JSON data originates. Modifying these macros breaks their semantics for all downstream callers and violates the principle of least surprise.