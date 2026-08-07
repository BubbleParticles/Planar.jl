---
name: hotloop-specialized-code
description: "Hot loops must run against specialized code — no per-item closures calling abstractly-typed function arguments or mutating boxed state"
condition: "run_item = function \\(item\\)|step\\(item\\) === :skip|update_stats\\(\\)"
scope: ["tool:edit(*.jl)", "tool:write(*.jl)"]
---

When writing hot loops (tick/OHLCV backtest iteration, per-tick order fills, streaming indicator updates), the loop body must run against specialized code. Routing each iteration through a closure that (a) calls function-typed arguments like `step(item)` or `update_stats()` and (b) captures boxed locals (e.g. `consecutive_errors`, `update_stats`) forces dynamic dispatch and heap traffic on every iteration. Correct patterns: keep the loop body inline so the compiler specializes on concrete types (`update_mode::ExecAction`, concrete `call!`/`ping!` signatures); if a helper is needed, give it concretely typed arguments and put the function barrier at the loop boundary, not per item; apply `@nospecialize` only to non-hot parameters. Before yielding, verify the hot path with `@code_warntype` — no `Any`/`Union{}` in the loop body.