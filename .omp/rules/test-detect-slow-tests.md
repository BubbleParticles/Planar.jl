---
name: test-detect-slow-tests
description: "Detect when tests are taking excessively long (wall time > threshold) and suggest ablation"
condition: "Wall time:\\s*(\\d{2,}|[6-9]\\d)\\s*seconds"
scope: ["tool:bash(test*)", "tool:bash(runtests*)", "tool:bash(pytest*)", "tool:bash(cargo\\s+test*)", "tool:bash(go\\s+test*)", "tool:bash(mix\\s+test*)", "tool:bash(jest*)", "tool:bash(make\\s+test*)", "tool:bash(mvn\\s+test*)", "tool:bash(gradle\\s+test*)", "tool:bash(sbt\\s+test*)", "tool:bash(dotnet\\s+test*)", "tool:bash(ctest*)", "tool:bash(phpunit*)", "tool:bash(ruff\\s+test*)"]
---

Test detected with excessive wall time (>60 seconds). This may indicate a hanging test or performance regression.

**Action**: Ablate tests systematically to isolate the slow/hanging test:
1. **Bisect**: Comment out half the tests, run again. If still slow, the issue is in the other half.
2. **Document**: Add `@tag :slow` or `# TODO: investigate hang - see issue #XXX` on ablated tests.
3. **Track**: Create a follow-up issue to investigate and re-enable.
4. **Timeout**: Add explicit timeout to prevent future hangs:
   - Julia: `@testset "name" timeout=60 begin ... end`
   - Rust: `cargo test -- --test-threads=1 --timeout=60`
   - Python: `pytest --timeout=30 -x`
   - Go: `go test -timeout 60s -count=1`

**Documentation**: Add a comment on ablated tests: `# ABLATED: hangs - see issue #XXX - re-enable after fix`