---
name: test-selective-execution
description: "Run only targeted tests during development; run full suite only at the end"
condition: "Pkg\\.test\\(|julia.*--project.*Pkg\\.test\\(|include\\(\"runtests\\.jl\\)"
scope: "tool:bash"
---

Run only targeted tests during development (e.g., `julia --project=Package -e 'include("test/specific_test.jl")'` or `julia --project=Package test/specific_test.jl`). Run the full test suite (`Pkg.test()`) ONLY at the very end after all changes are complete. Running full test suites repeatedly wastes significant time.