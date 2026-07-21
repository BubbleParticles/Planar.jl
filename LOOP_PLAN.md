# EXECUTION LOOP AUDIT: SimMode, PaperMode, LiveMode

## 🔴 CRITICAL (will crash the loop) — ALL FIXED

### ✅ Bug 1: PaperMode — `UndefVarError` in limit order background task
**File:** `PaperMode/src/orders/limit.jl:76-77`
Fixed: `catch` → `catch e` in commit b5894b4.

### ✅ Bug 2: PaperMode — Same pattern in `create_paper_limit_order!`
**File:** `PaperMode/src/orders/limit.jl:126`
Fixed: `catch` → `catch e` in commit b5894b4.

### ✅ Bug 3: SimMode — No exception handling in main backtest loop
**File:** `SimMode/src/backtest.jl:113-123` and `130-142`
Fixed: Both backtest loops wrapped in `try/catch e; @error ... end` in commit b5894b4.

### ✅ Bug 4: LiveMode — `UndefVarError` in OHLCV callback update
**File:** `LiveMode/src/watchers/ohlcv.jl:340-341`
Fixed: `catch` → `catch e` in commit b5894b4.

### ✅ Bug 5: LiveMode — `waitposclose` polling loop unguarded
**File:** `LiveMode/src/positions/utils.jl:448-460`
Fixed: Loop body wrapped in `try/catch e; @error ...; return false` in commit b5894b4.

### ✅ Bug 6: LiveMode — `waittrade` polling loop unguarded
**File:** `LiveMode/src/wait.jl:81-118`
Fixed: Loop body wrapped in `try/catch e; @error ...; return false` in commit b5894b4.

### ✅ Bug 7: PaperMode — Outer `@async while alive[]` loop lacks outer exception handler
**File:** `PaperMode/src/orders/limit.jl:35`
Already had `try` at line 36 (covers isopen at line 38). Verified.

### ✅ Bug 8: LiveMode — `stop_watch_orders!` UndefVarError
**File:** `LiveMode/src/watchers/orders.jl:267`
Fixed: `t.storage` → `task.storage` in commit 3ab2709. `t` was undefined in the loop body.

### ✅ Bug 9: LiveMode — `live_send_order` missing kwarg
**File:** `LiveMode/src/orders/send.jl:258`
Fixed: Added `trailing_trigger_amount=nothing` keyword argument to `live_send_order` signature. The function body referenced this variable but it was never declared as a parameter, causing `UndefVarError`.

### ✅ Bug 10: LiveMode — `_order_kv_hash` drops 2 fields from hash
**File:** `LiveMode/src/watchers/orders.jl:250-252`
Fixed: `p10` was assigned 3 times (status, loss_price, profit_price). Only profit_price survived in the hash. Now uses `p10`, `p11`, `p12`, `p13` for all 4 fields.

### ✅ Bug 11: LiveMode — `waittrade` bare catch swallows InterruptException
**File:** `LiveMode/src/wait.jl:110`
Fixed: bare `catch` → `catch e` with `InterruptException` rethrow.

### ✅ Bug 12: LiveMode — `@sync @async` blocks crash all assets on single failure
**Files:** 
- `LiveMode/src/positions/sync.jl:395` (`live_sync_position!` for `HedgedInstance`)
- `LiveMode/src/positions/sync.jl:466` (`_live_sync_universe_cash!`)
- `LiveMode/src/orders/sync.jl:656` (`live_sync_closed_orders!`)
- `LiveMode/src/orders/sync.jl:673` (`live_sync_open_orders!`)
Fixed: Wrapped each `@async` body in `try/catch e` that rethrows `InterruptException` and logs other errors. Prevents `TaskFailedException` from cascading across unrelated assets.

### ✅ Bug 13: LiveMode — `sync_active_orders!` bare catch swallows InterruptException
**File:** `LiveMode/src/orders/sync.jl:176`
Fixed: bare `catch` → `catch e` with `InterruptException` rethrow.

## Remaining Issues

### ✅ Finding 14: Test infrastructure — absolute paths in test manifests
**Files:** `PaperMode/test/Manifest.toml`, `LiveMode/test/Manifest.toml`
Fixed: All absolute `/project/*` paths replaced with relative `../../PackageName` paths.
`PaperMode/test/Manifest.toml` had 7 absolute paths, `LiveMode/test/Manifest.toml` had 6.
All three packages now pass `Pkg.test()` cleanly.

### ✅ Finding 15: LiveMode — 29 bare `catch` blocks ALL FIXED
**Files:** 14 files in `LiveMode/src/`
All 29 bare `catch` blocks converted to `catch e` with `InterruptException` rethrow.
Previously silently swallowed Ctrl-C. Now properly propagate for clean shutdown.

### 🔴 Finding 19: LiveMode — 34 unprotected `@async` blocks (silent task failures)
**Files:** 15 files in `LiveMode/src/`
Most `@async` blocks lacked any `try/catch`. Tasks that threw exceptions would fail silently
with no logging. Fixed: adhoc/balance, handler, utils (task cleanup, startup wait, stop paths),
watchers/mytrades, watchers/ohlcv, watchers/orders, balance/utils (current_total),
ccxt_functions (cancel/orders/positions fetch), watchers/positions, adhoc/ccxt_functions.

### 🟢 Finding 16: LiveMode `handle_events` loop is well-protected
**File:** `LiveMode/src/handler.jl:103-131`
Both `handle_events` calls are wrapped in `try/catch e`. `_execute_event` also wraps callbacks.

### 🟢 Finding 17: PaperMode `_doping` main loop is well-protected
**File:** `PaperMode/src/module.jl:88-110`
Inner try/catch handles per-iteration exceptions; outer try/catch handles loop-level errors.
`InterruptException` is rethrown for clean shutdown.

### 🟢 Finding 18: LiveMode watcher tasks have proper error handling
**Files:** `LiveMode/src/watchers/balance.jl:373-384`, `LiveMode/src/watchers/positions.jl:294-311`
Both use `@async while isstarted(w); try ... catch e; maybe_backoff!; @debug_backtrace; end; end |> errormonitor`.

## CURRENT STATUS
- **13+ crash bugs**: ALL FIXED across 4 iterations (commits b5894b4, 3ab2709, plus current)
- **30 bare `catch` blocks**: ALL FIXED (InterruptException rethrow) — 1 new bare catch removed
- **34 unprotected `@async` blocks**: ALL FIXED (error handling + logging)
- **9 synchronous wait()/wait() calls without timeout**: ALL FIXED (Iterations 3, 5)
  - New: positions.jl:726 — `wait(t)` → `waitforcond(..., 60s)` + warning
- **2 `@sync @async` blocks without per-task try/catch**: ALL FIXED (Iteration 5)
  - utils.jl:299-301 — `CompositeException` from `InterruptException` retry
  - positions/sync.jl:475-477 — inner `@async` covered by outer try/catch 
- **12+ InterruptException swallows (Finding 24, Iteration 5)**: ALL FIXED
  - 12 catch blocks across 7 files now rethrow InterruptException
  - `LiveMode/src/wait.jl:276` — `wait(w, :process)` → `wait(w, Second(30), :process)`
  - `LiveMode/src/handler.jl:164` — `safewait(cond)` → `waitforcond(cond, Second(1))`
  - `LiveMode/src/handler.jl:210` — `wait(s_task)` → `waitforcond` with 5s timeout
  - `LiveMode/src/handler.jl:218` — `wait(t)` → `waitforcond` with 5s timeout
  - `LiveMode/src/utils.jl:228` — `wait(task)` → `waitforcond` with 1min timeout + kill_task fallback
- **2 unprotected `@async` blocks in PaperMode**: BOTH FIXED
  - `PaperMode/src/positions/call.jl:57` — `@sync @async` position close per-asset
  - `PaperMode/src/module.jl:183` — `@async` doping loop wrapper
- **1 unprotected `@async` block in LiveMode**: FIXED
  - `LiveMode/src/watchers/positions.jl:713` — `@async` finalize task
- **7 InterruptException swallows (Finding 23, Iteration 4)**: ALL FIXED
  - `wait.jl:111` — outer catch in `waittrade(o::Order)`
  - `wait.jl:270` — `waitwatcherupdate` catch
  - `orders/create.jl:173,184` — two `catch err` in order construction
  - `orders/send.jl:274` — `catch err` in response trace
  - `watchers/ohlcv.jl:21,45` — two `catch exception` in propagate loops
- **Test verification**: LiveMode passes, PaperMode 21/21, SimMode 42/42 — ALL PASS
- **Remaining issues**: Pre-existing test infra paths (Finding 14)

## 🔴 Finding 24 (NEW, Iteration 5): Critical runtime bugs — ALL FIXED

### ✅ Finding 24a: `@sync @async` crash — `CompositeException` from InterruptException
**File:** `LiveMode/src/utils.jl:299-301`
The `@sync begin @async stop_all_asset_tasks @async stop_all_strategy_tasks end` block 
wrapped both `@async` tasks without individual try/catch. If both tasks received an
`InterruptException` simultaneously (e.g., during Ctrl-C shutdown), `@sync` wrapped them
in a `CompositeException` which failed the `e isa InterruptException` check at line 304, 
causing the retry loop to `break` with an error instead of `continue`-ing for retry.
**Fix:** Added per-task try/catch with error logging + rethrow. Outer catch now also handles
`CompositeException` containing only `InterruptException`s.

### ✅ Finding 24b: `wait(t)` without timeout in sendrequest! callback
**File:** `LiveMode/src/watchers/positions.jl:726`
`sendrequest!(ctx.s, max_date, () -> wait(t))` — if the finalize task `t` hung (e.g.,
`finalize_flags_and_cash_sync` never completed), the event handler thread would block
forever on `wait(t)`.
**Fix:** Replaced with `waitforcond(() -> istaskdone(t), Second(60))` + warning if timeout.

### ✅ Finding 24c: 12 missing InterruptException rethrows (prevents clean Ctrl-C shutdown)
**Files:** 7 files across SimMode/LiveMode/PaperMode
These catch blocks silently swallowed `InterruptException`:

| # | File | Line | Context |
|---|------|------|---------|
| 1 | `SimMode/src/backtest.jl` | 123 | Backtest loop (progress-bar path) — Ctrl-C continues to next date |
| 2 | `SimMode/src/backtest.jl` | 139 | Backtest loop (simple path) — Ctrl-C continues to next date |
| 3 | `LiveMode/src/utils.jl` | 290 | User watcher stop during `stop_all_tasks` shutdown |
| 4 | `LiveMode/src/handler.jl` | 156 | Event handler initial `handle_events` call |
| 5 | `LiveMode/src/handler.jl` | 168 | Event handler main loop — Ctrl-C silently continues loop |
| 6 | `PaperMode/src/orders/limit.jl` | 126 | `create_paper_limit_order!` — limit order fill task |
| 7 | `PaperMode/src/orders/utils.jl` | 23 | `_basevol` ticker Dict conversion |
| 8 | `PaperMode/src/orders/utils.jl` | 40 | `_basevol` volume Float64 conversion |
| 9 | `LiveMode/src/positions/utils.jl` | 462 | `waitposclose` polling loop |
| 10 | `LiveMode/src/watchers/ohlcv.jl` | 355 | OHLCV callback update watcher restart |
| 11 | `LiveMode/src/watchers/ohlcv.jl` | 360 | Inner retry `start!(w)` |
| 12 | `LiveMode/src/watchers/positions.jl` | 151 | Stall guard per-asset force fetch |
| 13 | `LiveMode/src/watchers/orders.jl` | 571 | `handle_order!` — InterruptException silently logged |
| 14 | `LiveMode/src/watchers/mytrades.jl` | 422 | `handle_trade!` — InterruptException silently logged |

All fixed: `e isa InterruptException && rethrow(e)` added before the log/fallback line.

**Test Results (Iteration 5 — 2026-07-15):**
```
SimMode:  42/42  PASS
PaperMode: 21/21 PASS
LiveMode:  PASS
```

## 🔴 Finding 20 (NEW): Infinite-block `wait()` calls — ALL FIXED
**Files:** 4 files across LiveMode/src/
Five `wait()` calls had no timeout, risking infinite blocking:

| File | Line | Original | Fix | Risk |
|------|------|----------|-----|------|
| `wait.jl` | 276 | `wait(w, :process)` | `wait(w, Second(30), :process)` | Watcher never emits → blocks forever |
| `handler.jl` | 164 | `safewait(cond)` | `waitforcond(cond, Second(1))` | Lost notification → handler stuck |
| `handler.jl` | 210 | `wait(s_task)` | `waitforcond(…, Second(5))` + warn | Handler task not terminating |
| `handler.jl` | 218 | `wait(t)` | `waitforcond(…, Second(5))` + warn | Asset handler task not terminating |
| `utils.jl` | 228 | `wait(task)` | `waitforcond(…, Minute(1))` + kill_task | Strategy task ignoring stop |

The `handler.jl:164` fix is the most important — the event handler's main loop now re-checks every second instead of blocking forever on a lost notification. All `wait(task)` calls now use `waitforcond` polling with fallback logging/warnings instead of infinite blocking.

## 🟡 Finding 21 (NEW): PaperMode unprotected @async blocks — FIXED
**Files:**
- `PaperMode/src/positions/call.jl:56-58` — `@sync` loop over all assets. If one asset's `call!` threw, the entire position close set was aborted via `CompositeException`. Fixed with per-asset try/catch that logs and continues.
- `PaperMode/src/module.jl:183` — `@async with_logger(…) do _doping(s) end` — if `_doping`'s internal error handling was ever bypassed, the silent task failure was invisible. Fixed with outer try/catch.

## 🟡 Finding 22 (NEW): LiveMode watchers/positions.jl:713 unprotected @async — FIXED
**File:** `LiveMode/src/watchers/positions.jl:713`
The `@async begin … end` block (position update finalization: waitforcond + finalize_flags_and_cash_sync) had no try/catch at all — only `errormonitor` for safety. If `finalize_flags_and_cash_sync` threw, the error surfaced as a bare `TaskFailedException` with no context. Fixed with try/catch e logging the exception with backtrace.

## 🔴 Finding 23 (NEW, Iteration 4): 7 remaining InterruptException swallows — ALL FIXED
**Root cause:** Previous InterruptException audit (Finding 15) missed several `catch` blocks
that didn't rethrow `InterruptException`. These were in fallback/catch-all handlers that
would silently swallow Ctrl-C during shutdown.

| # | File | Line | Context |
|---|------|------|---------|
| 1 | `LiveMode/src/wait.jl` | 111 | Outer `catch e` in `waittrade(o::Order)` — missed by Finding 11 |
| 2 | `LiveMode/src/wait.jl` | 270 | `waitwatcherupdate` — shutdown during watcher init swallowed Ctrl-C |
| 3 | `LiveMode/src/orders/create.jl` | 173 | `catch err` in committment fallback |
| 4 | `LiveMode/src/orders/create.jl` | 184 | `catch err` in order construction — `push!(s, ai, o)` failure swallowed |
| 5 | `LiveMode/src/orders/send.jl` | 274 | `catch err` in response trace |
| 6 | `LiveMode/src/watchers/ohlcv.jl` | 21 | `catch exception` in Rocket propagate loop — shutdown during OHLCV callback |
| 7 | `LiveMode/src/watchers/ohlcv.jl` | 45 | `catch exception` in second propagate loop (identical pattern) |

All fixed: `e isa InterruptException && rethrow(e)` added before the log/fallback line in every case.

## Test Results (Iteration 4 — 2026-07-15)
```
SimMode:  42/42  PASS
PaperMode: 21/21 PASS
LiveMode:  test passed (PlanarDev runner, 240 tests)
```
All changes committed with descriptive messages.
