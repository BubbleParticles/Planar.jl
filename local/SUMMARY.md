# Planar.jl Enhancement Audit — Consolidated Summary

**Date:** 2026-08-25 · Four parallel audits; full reports alongside this file.

| Report | Findings | Headline |
|---|---|---|
| [ergonomics.md](./ergonomics.md) | 16 | MCP lacks backtest/status/docs tools; gateway spawns at module load; no end-to-end strategy-dev guide |
| [performance.md](./performance.md) | 8 ranked + 2 rejected | Row-wise DataFrame access 400× slower than columnar; StaticArrays & Bumper measured NOT worth it |
| [security.md](./security.md) | 2 critical, 4 high, 4 medium, 4 low/info | Live API key tracked in `.env` git history; ccxt-gateway control plane has zero auth on 0.0.0.0 |
| [maintainability.md](./maintainability.md) | 11 | Dead WS copy + orphaned skew.jl; ~93 bare catches; 9 copy-pasted API clients; LiveMode test ratio 0.07× |

## Act now (critical, small effort)

1. **SEC-001**: Rotate the leaked `nvapi-*` key, `git rm --cached .env`, add `.env*` to .gitignore, scrub history.
2. **SEC-002**: Bind ccxt-gateway to `127.0.0.1` by default + add token auth (`config.py:27`, no auth middleware anywhere).
3. **Maintainability F1/F2**: delete dead `_connect_ws_ohlcv!` (`ccxt_ohlcv_candles.jl:455-490`) and orphaned `Simulations/skew.jl` (silent same-signature shadow trap).

## Top value per dimension

- **Ergonomics:** add `backtest_strategy` / `get_strategy_status` / `lookup_docs` MCP tools (findings #2–#4); lazy-start gateway instead of load-time spawn (#9).
- **Performance:** convert hot loops from row-wise DataFrame iteration to column grabs (measured 348 μs → 0.84 μs per 10k-candle pass); type the deferred LiveMode cache values (17×); reject StaticArrays/Bumper (measured slower/negligible).
- **Security:** after SEC-002, fix credential-in-query-string + admin secret echo (SEC-003), umask(0)-before-keygen (SEC-004), Docker build-arg credentials (SEC-006).
- **Maintainability:** mechanical bare-catch → logged-fallback pass over `Ccxt/` (~15 sites); consolidate the 9 Watchers API clients into one ApiClient; unify duplicated zarr save merge; coverage campaign starting with LiveMode/Executors (money paths at 0.07×/0.11×).

## Audit hygiene

Benchmark deps (JET/BenchmarkTools/StaticArrays) added to Planar/PlanarCore projects during measurement were reverted; working tree clean except this `local/` report directory.
