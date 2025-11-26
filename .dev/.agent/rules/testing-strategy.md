---
trigger: model_decision
description: when running julia commands to run or test strategy fixes
---

don't try `using Strategy`, instead use the `loadstrat!`, read the .startup.jl file in the repository root for example usage.