# MCP AI Guide

Session lifecycle, tool reference, strategy overwrite semantics, and Revise `includet` requirement.

## Session lifecycle
- `start_session_tool(project, env, julia)` returns `session` id, `pid`, `project`, `alive`, `started_at`.
- `eval_in_session_tool(session, code, timeout)` returns `ok`, `value`, `printed`, `error_type`, `backtrace`.
- `revise_in_session_tool` uses single eval `using Revise; Revise.revise()` (P4).
- `list_sessions_tool` includes liveness. Dead sessions are pruned.
- Idle timeout `PLANAR_SESSION_IDLE_TIMEOUT` default 3600s; `reap_idle_sessions` runs on start.

## Overwrite semantics
`write_strategy_tool` defaults `overwrite=false`; requires explicit opt-in. `description` persisted as `# description:` header.

## Revise caveat (E3)
File must be loaded via `Revise.includet(path)` to be tracked; `include_string` eval is not tracked.
