# Planar.jl Ergonomics Audit

**Date:** 2026-08-25 · **Scope:** MCP server, precompilation/loading, documentation, strategy dev/debug/monitoring — for AI-model consumers of the framework.

## MCP Server (ccxt-gateway)

1. **Missing strategy scaffolding tool** (S) — `ccxt-gateway/src/ccxt_gateway/mcp_server.py:28-30` (write_strategy helper), tool wrappers at :760-800. AI must hand-construct Julia module boilerplate → syntax-error risk. Add a `scaffold_strategy` tool generating a compilable skeleton from `user/strategies/Template.jl`.
2. **No backtest triggering via MCP** (M) — tools cover write/test/deploy but nothing runs a Sim-mode backtest and returns metrics. Add `backtest_strategy` returning P&L/win-rate as structured data.
3. **Results retrieval opaque** (M) — deploy returns only startup output; no tool to query running-strategy state/trades. Add `get_strategy_status` querying Remote or the strategy instance.
4. **No docs lookup tool** (M) — AI must guess signatures. Add `lookup_docs` backed by Julia `@doc`.
5. **Error messages not actionable** (S) — e.g. mcp_server.py:60 "invalid strategy name" gives no valid-format example. Include examples of valid input.
6. **No Julia-side MCP integration** (L) — grep of `Planar*/**/*.jl` finds no MCP references; server is Python-only. Document how Julia calls the server, or add a lightweight client.

## Precompilation & loading times

7. **Per-package precompile.jl may duplicate work** (M) — each package has its own precompile.jl with overlapping workloads. Consider consolidating top-level precompilation and/or SnoopCompile-generated directives.
8. **CondaPkg resolution at load time** (M) — `.CondaPkg` present; first `using PlanarPython` can trigger env resolution/downloads. Defer until first Python call; document pre-resolution.
9. **Gateway spawn during module init** (M) — `_init()` checks `/tmp/ccxt_gateway.pid` and pings/spawns the daemon on package load (Ccxt module). Lazy-start on first exchange creation instead, with manual start/stop API.

## Documentation

10. **Strategy workflow not documented end-to-end** (M) — docs/ has technical docs but no create→register→test→deploy→monitor guide. Add `docs/strategy-dev.md`.
11. **Docstring coverage incomplete on public API** (L) — spot-checks show many exported functions lack `@doc`. Add docstrings following PlanarCore style.
12. **README lacks AI-assisted development section** (S) — no mention of the MCP interface. Add a section listing tools + example session.

## Strategy development / debugging / monitoring

13. **Manual strategy file placement** (S) — strategies go into `user/strategies/` by convention only. Add `planar new-strategy` command or MCP tool that scaffolds + updates registration.
14. **Debugging affordances scattered** (M) — logging macros (`Planar/src/logmacros.jl`), REPL helpers (`Planar/src/repl.jl`, `dev.jl`) exist but are undiscoverable. Add `docs/debugging.md` with a sample session.
15. **Remote monitoring setup non-obvious** (M) — `Planar/src/Remote/` has no enable/connect tutorial. Add `docs/remote-monitoring.md`.
16. **No hot strategy reload** (M) — editing a live strategy requires restart (MCP Revise sessions aside). Expose/document a `reload!` path using Revise without losing state.

**Total: 16 findings. Quick wins: #5, #12, #13 (S); highest leverage for AI consumers: #2, #3, #4 (structured backtest/status/docs tools).**
