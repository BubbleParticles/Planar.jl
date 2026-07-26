---
name: fix-incr-comp-warnings
description: "Never dismiss precompile/build warnings that include 'incremental compilation' or 'unclosed module' — fix root cause instead"
condition: "harmless.*(warnings|output)"
scope: "text"
---

A `detected unclosed module: ... ** incremental compilation may be broken **` warning is NOT harmless. It means a module was loaded but its `end` was never reached — either an error during inclusion or a conditional include that returned early. Investigate and fix the root cause before reporting success. Check the file inclusion at the line indicated by the error trace for the unclosed module.