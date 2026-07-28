---
name: no-test-output-filtering
description: "Never filter test output with grep/tail/head; read full output to catch warnings and errors"
condition: "(Pkg\\.test|\\bruntests\\.jl\\b|include.*runtests|test.*suite).*(\\bgrep\\b|\\btail\\b|\\bhead\\b|\\bsed\\b|\\'-E\\'|\\'Test Summary\\')"
scope: "tool:bash"
---

When running tests or test suites (Pkg.test(), runtests.jl, etc.), NEVER pipe the output through grep, tail, head, or any other filter. Hidden warnings (world-age warnings, module loading issues, deprecated function warnings, etc.) provide critical debugging clues. Read the full unfiltered output instead.

If the output is too long for the terminal view, use an output capture mechanism (redirect to a file, or use `tee`) and then read the file, but still present the full output to yourself for inspection. Do not suppress any output lines in commands that verify test success.