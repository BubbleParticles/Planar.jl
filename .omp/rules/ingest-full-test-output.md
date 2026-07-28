---
name: ingest-full-test-output
description: "Read the full raw test output, not just grepped fragments, to catch every warning and error"
condition: "grep.*test_output|tail.*test_output|\\bgrep\\b.*Test\\b"
scope: "tool:bash"
---

When a test run produces output, read the full raw artifact (artifact:// or the complete tee'd file) instead of grepping for summary lines. Gagged fragments hide transient errors, precompilation warnings, and non-fatal exceptions that must be fixed or explicitly acknowledged. If the output is large, read it in sections with `read`, but never filter with grep/tail/head that drops context.