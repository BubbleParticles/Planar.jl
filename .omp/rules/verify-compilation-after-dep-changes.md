---
name: verify-compilation-after-dep-changes
description: "After auditing deps and concluding any are unused, verify the package compiles before reporting"
condition: "unused.*dep|not.*actually.*used|dead.?weight|isn't.?needed|orphaned.*never.*load"
scope: ["thinking", "text", "tool:grep(*/Project.toml)", "tool:grep(*module*.jl)", "tool:read(*/Project.toml)"]
---

After analyzing dependencies and concluding any are unused or unnecessary, you MUST verify the package compiles before reporting your conclusion. Run `julia --project=<pkg> -e 'using <Package>'` to confirm the package loads without errors. An import in source without the package in `[deps]` fails at compile time; a removal of a still-referenced dep also fails. Always compile-check — a wrong conclusion about a dep misleads the user and wastes their time.