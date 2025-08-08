---
trigger: always_on
---

When `using` or `import` modules, look for the existing dependencies and try to import those modules or dependencies from those dependencies we already have (in the Project.toml).
Try avoiding `if haskey() ...` in favor of `@lget! ...` (see the macro definition in the Lang package).
Uphold the codebase's uniformity by strictly observing Julia's standard naming conventions for variables and functions.
Make edits as surgical as possible, try to not throw away whole functions when changes need to be made.
When optimizing code, remember that in julia you have to consider hot loops with not well defined types and unnecessary allocations. Function barries help type inference.