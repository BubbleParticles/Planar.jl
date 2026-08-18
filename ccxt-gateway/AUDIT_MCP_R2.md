# Round-2 Audit: Planar MCP Strategy Server (`ccxt-gateway/src/ccxt_gateway/mcp_server.py`)

**Supplements** the baseline `ccxt-gateway/AUDIT_MCP.md` (round 1). It does **not**
duplicate it: every round-1 finding is re-validated against the current committed
source with its status (all `still-present`), and the net-new findings round 1
under-covered are listed under **New Bugs / New Ergonomics**.

**Symbols audited (with `file:line` anchors):** `SESSION_MANAGER`
(`mcp_server.py:675`), `SessionManager.start_session` (`mcp_server.py:524`),
`_BOOT_TEMPLATE` (`mcp_server.py:379`), `SessionManager.eval_in_session`
(`mcp_server.py:604`), `SessionManager.revise_in_session` (`mcp_server.py:636`),
and the 8 tools: `write_strategy_tool` (`mcp_server.py:679`),
`test_strategy_tool` (`mcp_server.py:699`), `deploy_strategy_tool`
(`mcp_server.py:717`), `start_session_tool` (`mcp_server.py:752`),
`stop_session_tool` (`mcp_server.py:773`), `list_sessions_tool`
(`mcp_server.py:786`), `eval_in_session_tool` (`mcp_server.py:795`),
`revise_in_session_tool` (`mcp_server.py:814`).

**Re-validation basis:** The working tree is clean — `git status --short` reports no
modifications to `mcp_server.py` (a stray 1-line comment edit from earlier work was
reverted before round 1). Round 2 therefore audits the **same committed code** as
round 1, so none of the round-1 findings can be `fixed` or `no-longer-applies`; they
are all `still-present`. Round 1 was analysis-only and round 2 makes no code changes
either, so this status is expected, not a gap.

**Verification evidence:** `cd ccxt-gateway && .venv/bin/pytest tests/ -q` → **exit 0,
376 passed**. Cited anchors were spot-checked against the current source
(`grep -n "READY" src/ccxt_gateway/mcp_server.py` → `425`, `552`). Capture:
`{SCRATCH}/mcp_tests_r2.log`.

---

## Round-1 findings — re-validation status (all `still-present`)

| ID | Location (current line) | Status | Round-2 note |
|----|------------------------|--------|--------------|
| B1 | `_run` `:134`; `start_new_session=True` `:148`; `except` `:143-157` | still-present | Unchanged. `subprocess.run` still only `Popen.kill()` (direct pid) on `TimeoutExpired`; children survive as orphans. Fix from round 1 stands. |
| B2 | `eval_in_session` `:604-634` | still-present | Unchanged. No lock around the write→read frames. **Amplified (see B11):** two concurrent evals also race their daemon reader threads on one shared `stream.readline()` (`:504-521`), so buffered lines can be consumed cross-call. |
| B3 | `start_session` `:567-568`; `SESSION_MANAGER` `:675`; counter init `:467-471` | still-present | Unchanged. **Amplified:** `list_sessions` iterates `for sid, s in self._sessions.items()` (`:588`) while `start_session` mutates the dict (`:567-568`); concurrent calls can raise `RuntimeError: dictionary changed size during iteration`. |
| B4 | `_get` `:596-601`; `list_sessions` `:586-601`; `stop_session` `:569-582` | still-present | Unchanged. Dead sessions linger. **Amplified (see B10):** a dead-but-registered session crashes the next eval rather than returning a clean error. |
| B5 | `_ensure_bootfile` `:475-483` | still-present | Unchanged. Bootfile temp written once per manager, never unlinked. (A parallel deploy-temp leak is now captured as **B13**.) |
| B6 | `_verdict` `:159-183` | still-present | Unchanged. `ERROR:` (`:179`) and `Test Summary` (`:174`) still over-broad; a *passing* suite that `exit(1)`s trailing code is still mislabeled `fail`. Round-1 fix stands. |
| B7 | `doeval` `:410-422` | still-present | Unchanged. Result carries `sprint(showerror, val)` text only — no exception type / backtrace. Round-1 fix stands. |
| B8 | `deploy_strategy` `:292-358` | still-present | Unchanged. `mode` is recorded in the result (`:339`) but `scripts/run.jl` (cross-boundary) ignores it and launches `Live`. Round-1 caution stands. |
| B9 | `stop_session` `:569-582` + `eval_in_session` `:604-634` | still-present | Unchanged. `QUIT\n` can interleave with an in-flight `EVAL` frame. Round-1 fix (per-session lock) stands. |
| E1 | `start_session_tool` `:752-770` | still-present | Unchanged. `env` exists on `start_session` (`:524-528`) but is unreachable from the tool. Round-1 fix stands. |
| E2 | `test_strategy_tool` `:699-710` | still-present | Unchanged. Only `test_strategy_tool` forwards `julia`; session/deploy tools use `DEFAULT_JULIA` (`:36`). Round-1 fix stands. |
| E3 | `revise_in_session_tool` `:813-828` + `include_string` `:410` | still-present | Docstring now says "reload any **tracked file** whose source changed on disk" (`:817-819`) — partial acknowledgment — but still does **not** show that the file must first be loaded via `Revise.includet`. The `include_string` eval path (`:410`) remains untracked by Revise, so a disk edit is still silently ignored. Round-1 fix (show the `includet` call) stands. |
| E4 | `doeval` `:420` | still-present | Unchanged. `value` is `string(val)` (opaque Julia repr). Round-1 fix stands. |
| E5 | `SessionManager` `:462-568` | still-present | Unchanged. No idle TTL, no `stop_all`. Round-1 fix stands. |
| E6 | `list_sessions` `:586-601` | still-present | Unchanged. Returns `pid`/`project` only; no `alive`/`started_at`. Round-1 fix stands. |
| P1 | `_read_line_blocking` `:493-527`; called `:619`/`:624`/`:628` | still-present | Unchanged. 3 daemon-thread spawns + joins per eval. Round-1 fix stands. |
| P2 | `doeval` `:407-425` | still-present | Unchanged. Fresh pipe + `redirect_stdout` per eval. Round-1 fix stands. |
| P3 | `json_escape` `:379-400`; used `:422` | still-present | Unchanged. Hand-rolled per-codepoint escape + string concat. Round-1 fix stands. |
| P4 | `revise_in_session` `:636-665` | still-present | Unchanged. Two round-trips per revise. Round-1 fix stands. |
| P5 | `_run` `:134-157`; truncation `:255` | still-present | Unchanged. Full output buffered before tail truncation. Round-1 fix stands. |

---

## New Bugs (not in round 1)

### B10 — Dead-session `stdin.write` raises an uncaught `BrokenPipeError`
- **Location:** `eval_in_session` write path `:615-618` (`proc.stdin.write(...)` /
  `proc.stdin.flush()`); the catch tuple at `:631` is
  `(TimeoutError, EOFError, ValueError, RuntimeError, KeyError)`.
- **Trigger:** A session whose Julia process has **already exited** but is still
  registered in `_sessions` (the exact `B4` "dead-but-lingering" case). The next
  eval writes to a broken pipe.
- **Impact:** `proc.stdin.write` / `.flush()` on a dead pipe raises
  `BrokenPipeError` (`ConnectionError` → `OSError`), which is **not** in the caught
  tuple at `:631`. It propagates out of `eval_in_session` and out of
  `eval_in_session_tool` (`:810`, which has no `try`), crashing the MCP tool call
  with an unhandled exception instead of returning the structured
  `{"ok": false, ...}` error the protocol promises. `ValueError` *is* caught
  (covers closed-file `ValueError`), but `BrokenPipeError`/`ConnectionError` is not —
  so the failure mode depends on exactly how the process died.
- **Suggested fix:** Add `OSError` (or the explicit `BrokenPipeError` /
  `ConnectionError`) to the catch tuple at `:631`. Better, wrap the
  `:615-618` write/flush in its own `try/except OSError` that returns a structured
  `{"ok": false, "error": "session pipe broken (process likely exited)"}` and
  proactively reaps the dead entry (ties into `B4`).

### B11 — `eval` timeout does not cancel the in-flight Julia; the session wedges permanently
- **Location:** `eval_in_session` `:619-630` (`_read_line_blocking` with `timeout`);
  `doeval` `:407-418` (`include_string(Main, code)` with no interrupt);
  `_read_line_blocking` daemon thread `:504-521`.
- **Trigger:** An eval that runs longer than `timeout` — e.g. an infinite loop or a
  hung network call inside a strategy the AI client evaluates.
- **Impact:** On timeout, `:631` returns `{"ok": false, ...}`, but the Julia REPL loop
  is **still blocked inside `include_string`** (`:410`) and never returns to its
  `while true` read loop (`:428-440`). Any subsequent `eval_in_session` on the same
  `sid` writes a new `EVAL` frame, but Julia is not reading stdin yet → that eval also
  times out. **The session is permanently unusable after a single over-long eval.**
  Compounding this, the daemon thread that raised `TimeoutError` is still alive
  (`daemon=True`, `:513`) and keeps calling `stream.readline()` (`:510`); when Julia
  eventually prints the *late* `RESULT`/`JSON`/`ENDOFRESULT`, that orphaned thread
  consumes those lines into `box[0]` and they are gone from the stream buffer — so the
  *next* eval's `_read_line_blocking` reads **misaligned** lines (a late `RESULT` as
  its header, or a corrupt JSON), surfacing as wrong `value` or a spurious
  `"unexpected session response"`. This is a concrete data-corruption path on top of
  the wedge.
- **Suggested fix:** On eval timeout, interrupt the Julia side so the loop returns to
  reading: send `proc.send_signal(signal.SIGINT)` (and/or wrap `include_string` in
  Julia with `try ... catch e; if e isa InterruptException ... end` so the REPL loop
  survives and prints a `RESULT`). At minimum, after a timeout treat the session as
  dead and force `stop_session` + require a fresh `start_session`. The orphaned
  reader thread must also be joined/neutralized on timeout so it cannot consume a late
  frame. Distinct from `B9` (shutdown interleave) and `B2` (concurrency) — this is
  about *uncancellable in-Julia work*.

### B12 — Session `stderr` pipe is never drained; 64 KB backpressure can deadlock the REPL
- **Location:** `start_session` `:543-546` (`stderr=subprocess.PIPE`, with no reader
  anywhere); `doeval` `:407-413` redirects **stdout only** (`redirect_stdout()`), so
  eval-time warnings go to the session's `stderr`; the Julia loop reads stdin /
  writes stdout (`:428-440`) but never touches `stderr`.
- **Trigger:** A session whose Julia process emits more than the OS pipe buffer
  (~64 KB on Linux) to `stderr` over its lifetime — precompilation warnings (e.g. the
  first `using Revise`), `@warn` spam from a chatty strategy, deprecation notices.
- **Impact:** `stderr=PIPE` buffers in the kernel; once it fills, Julia's *next*
  `write` to `stderr` **blocks**. Because the REPL loop never drains `stderr`, the
  blocked `write` halts the loop → the next `eval_in_session` times out (B11-style
  wedge) and the session silently deadlocks. `stdout` *is* drained (the readline
  loop), but `stderr` is not read anywhere. The MCP server has no use for session
  `stderr`, so buffering it is pure liability.
- **Suggested fix:** In `start_session` (`:543-546`) pass `stderr=subprocess.DEVNULL`
  (or `stderr=stdout`), since the server does not consume session `stderr`. If session
  diagnostics are wanted, spawn a drainer thread that continuously `read`s
  `proc.stderr` (mirroring the `_read_line_blocking` reader pattern). Either way, do
  not leave an unread `PIPE` attached to a long-lived subprocess.

### B13 — `deploy_strategy` temp config file is written but never deleted (file leak)
- **Location:** `deploy_strategy` `:289-291` (`_write_temp_config` writes
  `.mcp_deploy_tmp.toml`); `:347-349` uses it in the launch command but the path is
  neither returned nor cleaned; `_write_temp_config` `:289-291` performs no `unlink`.
- **Trigger:** Every `deploy_strategy(..., run=True)` call.
- **Impact:** A `.mcp_deploy_tmp.toml` is written into `toml_path.parent` (default
  `/Planar.jl/scripts/`) on every deploy and **leaked on disk**, accumulating across
  deployments. Distinct from `B5`: `B5` is the one-time per-manager bootfile; this is
  a *per-deploy* temp that is never removed. It also pollutes the strategies scripts
  directory with a stale config that could be picked up by a later accidental
  `scripts/run.jl --config` invocation.
- **Suggested fix:** `unlink` the temp config in a `finally` after `_run` returns
  (`:347-349`); or pass the deploy config via `julia -e '...'` / stdin instead of a
  file; or at least return its path and document that the caller owns cleanup.

---

## New Ergonomics (not in round 1)

### E7 — `write_strategy` `description` is accepted but never persisted
- **Location:** `write_strategy` signature `:99` (`description: Optional[str] = None`);
  result dict echoes it at `:130` (`"description": description`), but neither the `.jl`
  file (`:123-128`) nor `deploy_strategy`'s `entry` dict (`:326-332`) ever stores it.
- **Trigger:** A client calls `write_strategy(name, src, description="...")` expecting
  the description to travel with the strategy.
- **Impact:** The `description` is **ephemeral** — returned once and then lost. A
  later `read` of the file or `strategies.toml` carries no description, and
  `deploy_strategy` does not record it either. The parameter implies persistence it
  does not provide; an AI client that relies on it will silently lose metadata.
- **Suggested fix:** Either drop the parameter, or persist it — e.g. write a
  `# description: ...` header comment into the `.jl` file, and include
  `"description"` in the `entry` dict in `deploy_strategy` (`:326-332`) so it lands in
  `strategies.toml`.

### E8 — `write_strategy` defaults to `overwrite=True`, silently clobbering existing strategies
- **Location:** `write_strategy` `:99` (`overwrite: bool = True`).
- **Trigger:** A client calls `write_strategy(name, src)` without `overwrite=False`
  (the natural default call shape).
- **Impact:** A mistyped or reused `name` **silently overwrites** an existing strategy
  file — the result's `"action": "updated"` (`:129`) is the only signal, easy to miss.
  The `FileExistsError` guard exists (`:119-121`) but only fires when the caller opts
  in. For an AI client iterating on strategies, an accidental overwrite destroys prior
  work with no prompt.
- **Suggested fix:** Default `overwrite=False` so updates require an explicit opt-in,
  or return a prominent `warning` field in the result whenever an existing file is
  replaced (`:129`). The round-1 test suite already exercises the `overwrite=False`
  guard, so flipping the default is safe and improves the guard's usefulness.

---

## Performance (round 2 — no net-new)

Round 2 found **no additional performance findings** beyond `P1`–`P5` (re-validated
above, all `still-present`). The only performance-adjacent new observation — the
orphaned daemon reader thread that keeps consuming the stream after a timeout — is
captured under **B11** as the corruption mechanism, not as a standalone perf item.
The round-1 guidance (one reader thread per eval, persistent capture pipe, `JSON3`
encoding instead of hand-rolled `json_escape`, single combined revise round-trip,
rolling tail buffer in `_run`) remains the recommended set.

---

## Improvements (kept — same as round 1, still correct)

- **`include_string(Main, code)` eval model (`:410`).** Intended design: top-level
  bindings persist across calls. Do not move eval into a fresh module.
- **Manual `RESULT`/`ENDOFRESULT` framing (`:369-440`).** Avoids a Julia JSON dep in
  the tiny boot template; robust to startup noise on a *different* stream. Keep, but
  migrate framing + Python reader together if `P3`/`E4` are adopted.
- **`start_new_session=True` in `_run` (`:148`).** Correct and necessary for the `B1`
  group-kill fix; keep and pair with `os.killpg`.

---

*Round-2 audit performed against the committed `ccxt-gateway/src/ccxt_gateway/mcp_server.py`
(pytest suite green, exit 0, 376 passed). No code was modified; all findings are
recommendations. Net-new items vs. round 1: B10, B11, B12, B13, E7, E8.*
