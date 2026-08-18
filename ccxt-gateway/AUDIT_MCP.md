# Audit: Planar MCP Strategy Server (`ccxt-gateway/src/ccxt_gateway/mcp_server.py`)

**Scope:** Read-only audit of the shipped server source for bugs, ergonomics, and
performance. The server exposes 8 `@mcp.tool` wrappers backed by a module-level
`SESSION_MANAGER = SessionManager()` (`mcp_server.py:675`), plus three pure
strategy helpers (`write_strategy`, `test_strategy`, `deploy_strategy`).

**Symbols audited (with `file:line` anchors):** `SESSION_MANAGER` (`mcp_server.py:675`),
`SessionManager.start_session` (`mcp_server.py:524`), `_BOOT_TEMPLATE` (`mcp_server.py:379`),
`SessionManager.eval_in_session` (`mcp_server.py:604`), `SessionManager.revise_in_session`
(`mcp_server.py:636`), and the 8 tools: `write_strategy_tool` (`mcp_server.py:679`),
`test_strategy_tool` (`mcp_server.py:699`), `deploy_strategy_tool` (`mcp_server.py:717`),
`start_session_tool` (`mcp_server.py:752`), `stop_session_tool` (`mcp_server.py:773`),
`list_sessions_tool` (`mcp_server.py:786`), `eval_in_session_tool` (`mcp_server.py:795`),
`revise_in_session_tool` (`mcp_server.py:814`).

**Prior-audit check:** No prior MCP-server audit artifact exists in-repo. A repo-wide
search for `AUDIT_*.md` / `*audit*` / `mcp_server` references returned only unrelated
docs (`.kiro/` specs, `.omp/rules/*-audit-*.md`, `prompts/audit-loop.txt`,
`REFACTOR.md`). This report is therefore the **baseline** MCP audit; it does not
duplicate a previous one.

**Verification evidence:** `cd ccxt-gateway && .venv/bin/pytest tests/ -q` → exit 0
(376 passed). Cited lines were spot-checked against the current source (e.g.
`grep -n "READY" src/ccxt_gateway/mcp_server.py` → `425`, `552`). Capture:
`{SCRATCH}/mcp_tests.log`.

---

## Bugs

### B1 — Orphaned subprocesses on `_run` timeout
- **Location:** `_run` (`mcp_server.py:134`), `start_new_session=True` at
  `mcp_server.py:148`; timeout handling at `mcp_server.py:143-157`.
- **Trigger:** Any `test_strategy` / `deploy_strategy(run=True)` whose Julia command
  exceeds `timeout` (default 300s / 60s).
- **Impact:** On `subprocess.TimeoutExpired`, `subprocess.run` calls `Popen.kill()`,
  which is `os.kill(self.pid, SIGKILL)` — it kills **only the direct `julia`
  process**, not its process group. Because `start_new_session=True` makes `julia` a
  group leader, its children (Julia precompilation workers, or any subprocess the
  test/strategy spawns) survive as **orphans**. Repeated timeouts leak Julia
  processes and can exhaust PIDs/file descriptors.
- **Suggested fix:** In the `except subprocess.TimeoutExpired` branch, kill the group:
  `os.killpg(os.getpgid(proc.pid), signal.SIGKILL)` (guarded by a `try/except
  ProcessLookupError`). The group-leader guarantee comes from `start_new_session=True`.

### B2 — Concurrent `eval_in_session` on one session is unsynchronized
- **Location:** `eval_in_session` (`mcp_server.py:604-634`); the wire protocol frames
  are written/read with no lock.
- **Trigger:** Two tool calls (or `eval_in_session` racing `revise_in_session`) issued
  on the **same `session` id** concurrently (the server's stdio MCP transport can
  service parallel requests; an AI client may also pipeline).
- **Impact:** `proc.stdin.write(...)` calls interleave and the three `RESULT`/`JSON`/
  `ENDOFRESULT` lines from one eval can be read by another call's
  `_read_line_blocking` (`mcp_server.py:619-630`). Result: wrong `value`/`printed`
  returned, or a spurious `RuntimeError("unexpected session response")` classified as
  an error (caught at `mcp_server.py:631-634`).
- **Suggested fix:** Add a `threading.Lock` to each `Session` (or one lock on
  `SessionManager`) and hold it across the full write-then-read sequence in
  `eval_in_session`. This also serializes `revise_in_session` (which calls
  `eval_in_session`).

### B3 — `_counter` / `_sessions` mutated without a lock (singleton shared state)
- **Location:** `start_session` (`mcp_server.py:567-568`); the shared
  `SESSION_MANAGER` singleton (`mcp_server.py:675`); counter init at
  `mcp_server.py:467-471`.
- **Trigger:** Concurrent `start_session_tool` calls.
- **Impact:** `self._counter += 1` and `self._sessions[sid] = Session(...)` are not
  atomic; interleaved calls can produce **duplicate session ids** or drop a session
  from the map. Same root cause as B2 (no concurrency control on shared mutable
  state).
- **Suggested fix:** Guard `start_session` (and `stop_session`) with the same lock
  used in B2.

### B4 — Dead/zombie sessions are never detected or reaped
- **Location:** `_get` (`mcp_server.py:596-601`), `list_sessions`
  (`mcp_server.py:586-601`), `stop_session` (`mcp_server.py:569-582`).
- **Trigger:** A Julia session dies in-process (e.g. a `include_string` eval that
  segfaults or is SIGKILLed — see B1) but its id remains in `_sessions`.
- **Impact:** The dead entry lingers; `list_sessions` keeps reporting a pid that is no
  longer alive, and the next `eval_in_session` fails with a generic
  `EOFError`/`RuntimeError` rather than a clear "session dead" signal. No auto-restart.
- **Suggested fix:** In `list_sessions`/`_get`, probe liveness via `proc.poll() is None`
  and drop dead entries; optionally restart on demand. At minimum, surface `alive` in
  `list_sessions` (see E6).

### B5 — Bootfile temp file leaks
- **Location:** `_ensure_bootfile` (`mcp_server.py:475-483`).
- **Trigger:** Every `SessionManager` instantiation writes
  `planar_mcp_boot_*.jl` to the system temp dir and **never unlinks it**. The file is
  shared across all sessions of that manager (`self._bootfile`, `mcp_server.py:467`).
- **Impact:** Temp-file accumulation on long-running servers; one leftover per manager
  lifetime (and the singleton `SESSION_MANAGER` lives for the whole server process).
- **Suggested fix:** `os.unlink(self._bootfile)` in a `close()`/`__del__` or an
  `atexit` handler; or write the boot template into a `TemporaryDirectory` and clean it
  up on teardown.

### B6 — `_verdict` text heuristic misclassifies Julia output
- **Location:** `_verdict` (`mcp_server.py:159-183`).
- **Trigger:** Any run whose stdout/stderr differs from the assumed shape.
- **Impact (three concrete failure modes):**
  1. A *non-test* Julia run that exits non-zero while logging a benign `"ERROR:"`
     string is labeled `"fail"` instead of `"error"` (marker `"ERROR:"` at
     `mcp_server.py:179`).
  2. A *failing* test whose summary lacks the exact substrings (custom test
     harness, localized messages, or a different format) is labeled `"error"`
     instead of `"fail"`.
  3. `"Test Summary"` (`mcp_server.py:174`) is emitted by **passing** suites too, so
     it only discriminates when combined with a non-zero exit — but a *passing* suite
     that then exits non-zero for an unrelated reason (e.g. `exit(1)` in trailing
     code) is mislabeled `"fail"`.
- **Suggested fix:** Key primarily on `returncode` (Julia's `Test` module is
  non-zero on *any* failing assertion) and use the markers only to split `fail` vs
  `error` when `returncode != 0`; tighten the marker list (drop the over-broad
  `"ERROR:"` and `"Test Summary"`; keep `Error During Test`, `Test Failed`,
  `UndefVarError`, `LoadError`, `ParseError`).

### B7 — `doeval` returns only the exception's string, not its class/stack
- **Location:** `doeval` (`mcp_server.py:410-422`), returned via `eval_in_session`
  (`mcp_server.py:631-634`).
- **Trigger:** Any eval that throws.
- **Impact:** The structured result carries `value = sprint(showerror, val)` (text
  only) — no exception *type* and no backtrace. An AI client cannot distinguish a
  `UndefVarError` from an `ArgumentError`, so it can't decide whether to fix the
  strategy, retry, or escalate.
- **Suggested fix:** Enrich the result with `error_type = string(typeof(val))` and an
  optional trimmed backtrace (`stacktrace(catch_backtrace())` captured in Julia), or
  return a small structured object instead of a single string.

### B8 — `deploy_strategy(mode=..., run=True)` records `mode` but launches `Live`
- **Location:** `deploy_strategy` (`mcp_server.py:292-358`) writes `mode` into the
  entry/result; `_write_temp_config` + `scripts/run.jl` (cross-boundary) ignore it.
- **Trigger:** `deploy_strategy_tool(name, exchange, mode="Paper", run=True)`
  (`mcp_server.py:717-740`).
- **Impact:** The launched strategy runs in **`Live`** mode (per plan
  `## Risks` — `scripts/run.jl` hardcodes `Live()`) while the tool result claims
  `mode="Paper"`. That is a dangerous mismatch: the AI client believes it started a
  paper strategy but real orders may be placed.
- **Suggested fix (cross-boundary — noted, not applied here):** Either make
  `scripts/run.jl` honor `mode` from the config, or have `deploy_strategy` refuse
  `run=True` unless it can enforce the requested mode. Until then, the docstring
  should warn that `run=True` always launches `Live`.

### B9 — `stop_session` QUIT can interleave with a concurrent eval
- **Location:** `stop_session` (`mcp_server.py:569-582`) + `eval_in_session`
  (`mcp_server.py:604-634`).
- **Trigger:** `stop_session_tool` issued while an `eval_in_session` is mid-write on
  the same session.
- **Impact:** `QUIT\n` may be written into the middle of an in-flight `EVAL` frame,
  corrupting the next read; if the loop is wedged in a long/infinite Julia eval,
  `QUIT` is only consumed after the eval returns (then `proc.wait(10)` → `proc.kill()`).
  Same root cause as B2.
- **Suggested fix:** Same per-session lock as B2; additionally consider a forced-stop
  path (e.g. a secondary control pipe or `proc.kill()` after a bounded QUIT wait) so a
  hung loop cannot block shutdown.

---

## Ergonomics

### E1 — `start_session_tool` does not expose `env` (or `julia`)
- **Location:** `start_session_tool` (`mcp_server.py:752-770`) vs
  `SessionManager.start_session`, which already supports `env` (`mcp_server.py:524-528`)
  and inherits `julia` from the manager.
- **Trigger:** An AI client wants a Revise-capable session by pinning
  `JULIA_DEPOT_PATH` (the exact pattern the unit test uses:
  `tests/test_mcp_tools.py::test_revise_tool_unavailable_structured_error` sets
  `monkeypatch.setenv("JULIA_DEPOT_PATH", ...)` — it cannot use the `env` argument
  through the tool).
- **Impact:** The `env` capability exists in the Python API but is unreachable from
  MCP; clients must set global env vars (`JULIA_BIN`, `JULIA_DEPOT_PATH`) to scope
  per-session behavior.
- **Suggested fix:** Add `env: Optional[dict[str, str]] = None` (and optionally
  `julia`) to `start_session_tool` and forward to `start_session`.

### E2 — Julia executable selection is inconsistent across tools
- **Location:** `test_strategy_tool` forwards `julia` (`mcp_server.py:699-710`);
  `deploy_strategy_tool` (`mcp_server.py:717-740`), `start_session_tool`,
  `eval_in_session_tool`, `revise_in_session_tool` do not — they always use
  `DEFAULT_JULIA` (`JULIA_BIN` or `"julia"`, `mcp_server.py:36`).
- **Trigger:** A deployment where `julia` is not on `PATH` and `JULIA_BIN` is unset.
- **Impact:** Only `test_strategy` can target a specific Julia; the session tools
  cannot, despite `SessionManager`/`deploy_strategy` accepting a `julia` parameter.
- **Suggested fix:** Expose `julia` uniformly (or document `JULIA_BIN` as the single
  knob and drop the per-tool `julia` for consistency).

### E3 — Revise-reload caveat is undocumented at the tool boundary
- **Location:** `revise_in_session_tool` (`mcp_server.py:813-828`) and
  `revise_in_session` (`mcp_server.py:636-665`); the boot loop uses `include_string`
  (`mcp_server.py:410`), which is **not** tracked by Revise.
- **Trigger:** AI edits a strategy file on disk, then calls `revise_in_session`,
  expecting a reload.
- **Impact:** `Revise.revise()` only reloads files loaded via `Revise.includet` /
  `Revise.track`. Because session eval goes through `include_string`, a disk edit is
  **silently ignored** — the reload is a no-op and the client has no signal.
- **Suggested fix:** Document the `Revise.includet(path)` requirement in the tool
  docstring; additionally, when `Revise.revise()` reports "no changes", return an
  explicit `tracked=false` / `changed=false` hint so the client knows nothing was
  reloaded.

### E4 — `eval_in_session` `value` is an opaque string, not structured
- **Location:** `doeval` returns `string(val)` (`mcp_server.py:420`), surfaced as
  `value` in `eval_in_session` (`mcp_server.py:631-634`).
- **Trigger:** `eval_in_session(sid, "Dict(:a => 1)")` → `value == "Dict(:a => 1)"`.
- **Impact:** Complex Julia results come back as Julia's `string` repr; the AI client
  must brittlely parse Julia syntax to recover structure.
- **Suggested fix:** When the value is JSON-serializable (e.g. `JSON3`/`JSON` is
  available in the session), return it as structured JSON; fall back to `string`
  otherwise. Note: this changes the boot framing, so `_read_line_blocking` must be
  updated in the same change (coordinated edit).

### E5 — No idle-session timeout / cleanup
- **Location:** `SessionManager` lifecycle (`mcp_server.py:462-568`); no TTL, no
  `stop_all`.
- **Trigger:** A client starts a session and forgets to call `stop_session_tool`.
- **Impact:** The Julia process leaks for the server's lifetime; at scale this is a
  meaningful resource drain.
- **Suggested fix:** Optional idle TTL in `SessionManager` (reap sessions not
  evaluated within N seconds) and/or a `stop_all_sessions_tool`.

### E6 — `list_sessions` omits liveness / started-at
- **Location:** `list_sessions` (`mcp_server.py:586-601`).
- **Trigger:** Debugging "why did my eval fail?".
- **Impact:** Returns only `pid`/`project`; a dead session (B4) is indistinguishable
  from a live one.
- **Suggested fix:** Include `alive = proc.poll() is None` and `started_at` (set in
  `start_session`) per entry.

---

## Performance

### P1 — A new daemon thread is spawned per result-line read
- **Location:** `_read_line_blocking` (`mcp_server.py:493-527`); called **three times**
  per eval — header (`mcp_server.py:619`), JSON (`mcp_server.py:624`), trailer
  (`mcp_server.py:628`).
- **Trigger:** Every `eval_in_session` / `revise_in_session`.
- **Impact:** 3 thread creations + joins per eval (→ 6 for a revise). Thread setup/join
  is fixed per-call overhead that dominates for small evals and adds up at high call
  rates.
- **Suggested fix:** Read all three lines inside a **single** thread (one
  `threading.Thread` per eval), or use a persistent per-session reader thread that
  pushes framed results onto a `queue.Queue`.

### P2 — Per-eval `redirect_stdout()` + pipe + full-buffer read in the Julia bootstrap
- **Location:** `doeval` (`mcp_server.py:407-425`).
- **Trigger:** Every eval.
- **Impact:** Each eval creates a fresh pipe pair, redirects `stdout`, evaluates, reads
  **all** captured output into a `String`, then restores — fixed per-call cost that
  could be amortized.
- **Suggested fix:** Keep one persistent capture pipe per session (redirect once at
  startup, drain between evals) instead of create/redirect/read/restore on every call.

### P3 — Hand-rolled `json_escape` char loop in Julia
- **Location:** `json_escape` (`mcp_server.py:379-400`), used to build the result at
  `mcp_server.py:422`; the final JSON is assembled by string concatenation.
- **Trigger:** Every eval with non-trivial `value`/`printed`.
- **Impact:** Codepoint-by-codepoint escaping plus repeated string concatenation is
  O(n) with many small allocations; large outputs (big backtraces, big data printed)
  serialize slowly.
- **Suggested fix:** Build the result with `JSON3.write`/`JSON.json` in Julia (which
  escapes correctly), or return the raw payload and JSON-encode on the Python side —
  eliminating manual escaping. Coordinated with E4/P1 framing changes.

### P4 — `revise_in_session` does two round-trips and re-checks Revise each time
- **Location:** `revise_in_session` (`mcp_server.py:636-665`): one eval to test
  `using Revise`, then a second eval for `Revise.revise()`.
- **Trigger:** Every revise call (2 evals + 6 line reads).
- **Impact:** 2× the eval latency of a single call, for a check that rarely changes
  within a session.
- **Suggested fix:** Combine into one eval —
  `try; using Revise; Revise.revise(); "ok" catch e; "err: " * sprint(showerror, e) end` —
  and cache per-session whether Revise is already loaded.

### P5 — `_run` holds the entire subprocess output in memory before truncating
- **Location:** `_run` (`mcp_server.py:134-157`) returns full `stdout`/`stderr`;
  callers truncate to the **tail** via `(out + err)[-4000:]` (`mcp_server.py:255`) — this
  correctly preserves the Julia failure summary at the end.
- **Trigger:** Large test output.
- **Impact:** The full capture is buffered in memory (and kept by `subprocess.run`)
  even though only the last 4000 chars are used; for very large suites this is
  avoidable memory pressure. (Information loss is *not* a problem — the tail is kept.)
- **Suggested fix:** Stream/pipe output and keep only a rolling tail buffer (e.g.
  `collections.deque(maxlen=4000)`), avoiding the full in-memory copy.

---

## Improvements (deliberately kept — reasons not to change)

- **`include_string(Main, code)` eval model (`mcp_server.py:410`).** This is the
  intended design: evaluating at `Main` keeps top-level bindings (e.g. `x = 1`) alive
  across calls, which is the whole point of a persistent session. Do **not** switch to
  evaluating inside a fresh module — that would break state persistence (AC2 of the
  original feature).
- **Manual `RESULT`/`ENDOFRESULT` framing instead of a JSON-RPC/line protocol.**
  The current framing avoids any Julia JSON dependency in the tiny boot template and
  is robust to a Julia startup message on a *different* stream. Keep it, but if P3/E4
  are adopted, migrate the framing and the Python reader (`_read_line_blocking`,
  `mcp_server.py:493-527`) together.
- **`start_new_session=True` in `_run` (`mcp_server.py:148`).** Correct and necessary
  for B1's group-kill fix; keep it and pair it with `os.killpg`.

---

*Audit performed against `ccxt-gateway/src/ccxt_gateway/mcp_server.py` at the current
`master` (pytest suite green, exit 0). No code was modified; all findings are
recommendations.*
