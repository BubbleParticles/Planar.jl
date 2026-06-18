# Plan: Refactor Watchers.jl + LiveMode Async to Rocket.jl

## TODOs

### Phase 1 — Watchers Core
- [x] 1. Add Rocket.jl dependency to Watchers/Project.toml
- [x] 2. Rewrite module.jl: Beacon→Subject, _timer!→interval observable, _schedule_fetch→reactive pipeline, Watcher struct gains subscriptions dict
- [x] 3. Rewrite functions.jl: start!/stop!→subscribe!/unsubscribe!, wait→take(1) pattern, flush!/process!→Subject push, close→cleanup subscriptions
- [x] 4. Run Watchers/test/runtests.jl to verify core still works

### Phase 2 — WatchersImpls
- [ ] 5. Rewrite impls/utils.jl: WatcherHandler2→Subject actor, new_handler_task→Rocket pipeline, remove Condition buffer notify
- [ ] 6. Rewrite ccxt_tickers.jl: _reset_tickers_func!→subscribe pipeline, _start!/_stop!→subscribe/unsubscribe
- [ ] 7. Rewrite ccxt_ohlcv_trades.jl: watch handler→actor, remove @async
- [ ] 8. Rewrite ccxt_ohlcv_tickers.jl: same
- [ ] 9. Rewrite ccxt_ohlcv_candles.jl: same, maybe_schedule_resync!→actor
- [ ] 10. Rewrite ccxt_orderbook.jl: interval→subscribe
- [ ] 11. Run Watchers/test/runtests.jl

### Phase 3 — LiveMode Watchers
- [ ] 12. Rewrite ohlcv.jl: propagate_loop→Subject subscription
- [ ] 13. Rewrite balance.jl: _balance_task!→interval subscribe, stall_guard→timer subscribe, buffer→Subject
- [ ] 14. Rewrite positions.jl: same pattern
- [ ] 15. Rewrite orders.jl + mytrades.jl: watch loops→Rocket actor pipelines
- [ ] 16. Remove dead stubs: stream_handler/start_handler!/stop_handler! from utils files
- [ ] 17. Run PlanarDev tests (critical live paths)

### Final Verification Wave
- [ ] 18. Watchers test suite passes (73+ tests)
- [ ] 19. PlanarDev/test/runtests.jl basic loading works
- [ ] 20. Tag commit `rocket-watchers-complete`

---

## Goal

Replace every `Timer`/`@async`/`@spawn`/`Condition`/`safewait`/`safenotify` pattern in Watchers.jl, WatchersImpls, and LiveMode watchers with Rocket.jl reactive streams (`interval`, `Subject`, `subscribe!`, actors).

## Why Rocket.jl

- `interval(d)` / `timer(0, d)` replaces `Timer(f, 0; interval=d)` — composable, cancellable
- `Subject{T}` replaces `Threads.Condition` — push-based, multicast, no polling
- `subscribe!(observable, actor)` replaces `@async while isstarted(w)` — declarative lifecycle
- `Actor` / `map` / `filter` compose fetch→process→flush pipelines without manual task management
- `unsubscribe!()` / `Actor.complete!()` replaces stop/kill

## Architecture

```
Timer/@async/@spawn/Condition       →     Rocket.jl observable/subject/actor
─────────────────────────────────         ─────────────────────────────────
Watcher._timer::Timer                    → fetch_interval::IntervalObservable
Watcher.beacon::Beacon                   → fetch_subject::Subject, process_subject::Subject, flush_subject::Subject
_schedule_fetch → _fetch_task → @spawn   → fetch_interval |> map(_fetch!) |> subscribe!(actor)
_schedule_fetch timeout logic            → timeout operator or merge(timer(d), fetch_result)
new_handler_task / WatcherHandler2       → Subject + actor pipeline
handler_task!/check_task!/stop_handler   → subscribe!/unsubscribe!
propagate_loop (LiveMode)                → process_subject |> subscribe!(propagate!)
stall_guard tasks                        → timer(60) |> filter(stalled) |> subscribe!(force_fetch)
buffer+Condition notify                  → Subject
```

## Files to Modify (in dependency order)

### Phase 1 — Watchers Core (`Watchers/src/`)

| File | What changes |
|------|-------------|
| `Project.toml` | Add `Rocket` dependency |
| `module.jl` | Replace `_timer!` with Rocket interval; replace `_schedule_fetch` / `_fetch_task` / `_tryfetch` with reactive pipeline; replace `Beacon` (3×Threads.Condition) with 3×Subject; rewrite `_watcher` constructor |
| `functions.jl` | Replace `fetch!`, `flush!`, `process!`, `stop!`, `start!`, `wait`, `close` to use Rocket subscribe/unsubscribe instead of Timer open/close + Condition safewait/safenotify |
| `defaults.jl` | Replace `_flush!` / `_load!` / `_fetch!` / `_process!` default dispatchers — minimal changes (these are callbacks, not async) |
| `errors.jl` | No changes needed (pure error logging) |

### Phase 2 — WatchersImpls (`Watchers/src/impls/`)

| File | What changes |
|------|-------------|
| `utils.jl` | Replace `new_handler_task` / `WatcherHandler2` / `handler_task!` / `check_task!` / `stop_handler_task!` with Rocket actor pipeline; replace `buffer_notify::Condition` + `buffer::Vector` with `Subject{Any}` |
| `ccxt_tickers.jl` | Replace `handler_task!` / `@async process!(w)` / `check_task!` with Rocket actor; `_reset_tickers_func!` uses `interval(d) \|> map(fetch) \|> subscribe!(actor)` |
| `ccxt_ohlcv_trades.jl` | Replace watch-mode handler (init_func, corogen_func, wrapper_func) with Rocket actor; replace `_start!`/`_stop!` subscribe/unsubscribe |
| `ccxt_ohlcv_tickers.jl` | Same pattern: `_reset_tickers_func!` → subscribe; `_process!` async task list → actor |
| `ccxt_ohlcv_candles.jl` | Same pattern: `_reset_candles_func!` → subscribe; `maybe_schedule_resync!` @async → actor; `init_tasks` Set{Task} → actor |
| `ccxt_orderbook.jl` | Simplest impl — just use interval |> map(fetch) |> subscribe |
| `ccxt_average_ohlcv_watcher.jl` | Apply same pattern |

### Phase 3 — LiveMode Watchers (`LiveMode/src/watchers/`)

| File | What changes |
|------|-------------|
| `ohlcv.jl` | Replace `propagate_loop` (2 variants) with `process_subject |> subscribe!(propagate!)`; replace `addpropagatetask!` with add_subscription |
| `balance.jl` | Replace `_balance_task!(@async while isstarted(w))` with interval |> subscribe; replace `_balance_setup_stall_guard!` with timer(60) |> filter(stalled) |> subscribe; replace `buf_notify::Condition` + `buf` with Subject |
| `positions.jl` | Same as balance: replace `_positions_task!` @async loop with interval |> subscribe; replace stall guard; replace buf notify with Subject |
| `orders.jl` | Replace @async watch loops with Rocket actors; replace buf+Condition with Subjects |
| `mytrades.jl` | Same as orders |
| `utils.jl` | Remove stub `stream_handler`/`start_handler!`/`stop_handler!` (no longer needed) |

## Detailed Step-by-Step

### Step 1: Add Rocket.jl dependency

```bash
cd /project/Watchers && julia --project=. -e 'using Pkg; Pkg.add("Rocket")'
```

### Step 2: Rewrite Watcher struct async core (`module.jl`)

#### 2a. Replace Beacon (3×Threads.Condition) with Subjects

```julia
# Before
const Beacon = NamedTuple{(:fetch, :process, :flush), NTuple{3, Threads.Condition}}
# After
const Beacon = NamedTuple{(:fetch, :process, :flush), NTuple{3, Rocket.Subject{Dict{Symbol,Any}}}}
```

Actually, the Subject type parameter depends on what payload we push. The beacon items are just notification signals (no payload needed, or we can push the watcher state):

```julia
# As Subjects (can carry payload, but we mostly just signal):
const Beacon = NamedTuple{(:fetch, :process, :flush), Tuple{Rocket.Subject{DateTime}, Rocket.Subject{DateTime}, Rocket.Subject{DateTime}}}
```

Initially just use `Subject{Any}()` — they're lightweight.

#### 2b. Replace `_timer!` with interval observable

```julia
# Before
function _timer!(w)
    if !isnothing(w._timer)
        close(w._timer)
    end
    timer_fetch_callback(_) = _schedule_fetch(w, w.interval.timeout, w._exec.threads)
    interval = round(w.interval.fetch, Second, RoundUp).value
    w._timer = Timer(timer_fetch_callback, 0; interval)
end

# After (conceptual)
const FETCH_SCHEDULER = Ref{Union{Nothing, Rocket.Scheduler}}()

function _setup_fetch_pipeline!(w)
    # Create interval observable that ticks at the fetch interval
    interval_ms = round(w.interval.fetch, Second, RoundUp).value * 1000
    obs = Rocket.interval(interval_ms, scheduler=FETCH_SCHEDULER[]) 
    # Pipe through the fetch function
    pipeline = obs |> Rocket.map(_ -> _fetch_pipeline_step(w))
    # Subscribe
    subscription = Rocket.subscribe!(pipeline, Rocket.Actor(
        on_next = result -> _handle_fetch_result(w, result),
        on_error = err -> logerror(w, err),
    ))
    w._subscription = subscription
end
```

#### 2c. Replace `_schedule_fetch` / `_fetch_task` / `_tryfetch` reactive pipeline

The core loop becomes:

```
interval
  |> map(_tryfetch_or_skip_if_locked)
  |> map(handle_result -> process/flush)
  |> subscribe!(actor)
```

The timeout logic from `_schedule_fetch` (the `@async let slept... while waiting[]... safenotify(task.donenotify)` pattern) can be done with `Rocket.timeout()` operator:

```julia
interval
  |> map(_ -> _tryfetch(w))
  |> timeout(w.interval.timeout)  # emits TimeoutError if fetch takes too long
  |> subscribe!(actor)
```

### Step 3: Rewrite functions.jl

Replace:
- `fetch!(w; reset, kwargs)` — instead of `_schedule_fetch` + manual timeout/retry, trigger the Subject and wait for result
- `flush!(w; force, sync)` — instead of `@async lock... _flush!` + `safenotify`, push to flush Subject
- `process!(w)` — instead of `@logerror` + `@lock` + `_process!` + `safenotify`, push to process Subject
- `stop!(w)` / `start!(w)` — instead of Timer close/open, `unsubscribe!` / `subscribe!`
- `wait(w, b)` — instead of `safewait(beacon)`, use `Rocket.next!(subject)` or subscribe + take(1)
- `Base.close(w)` — cleanup subscription instead of trylock + close + stop

### Step 4: Rewrite `impls/utils.jl` — `WatcherHandler2` → Rocket actor

Current pattern:
```julia
struct WatcherHandler2
    init_func::Function
    corogen_func::Function
    wrapper_func::Function
    buffer_notify::Condition
    buffer::Vector{Any}
    state::Option{StreamHandler}
    task::Option{Task}
    process_tasks::Task[]
end
```

Replace with:
```julia
struct WatcherHandler2
    init_func::Function
    corogen_func::Function
    wrapper_func::Function
    subject::Rocket.Subject{Any}       # replaces buffer+Condition
    subscription::Rocket.Subscription  # replaces task
end
```

The `new_handler_task` becomes:
```julia
function new_handler_task(w; init_func, corogen_func, wrapper_func=identity, if_func=!isnothing)
    subject = Rocket.Subject{Any}()
    # Init pipeline
    init_obs = Rocket.from(init_func)
    # Watch pipeline from subject (pushes from the gateway stream)
    pipeline = subject
        |> Rocket.map(wrapper_func)
        |> Rocket.filter(if_func)
        |> Rocket.map(v -> _dopush!(w, v))
    subscription = Rocket.subscribe!(pipeline, actor)
    return WatcherHandler2(init_func, corogen_func, wrapper_func, subject, subscription)
end
```

### Step 5: Rewrite each ccxt_* watcher impl

Each impl follows the same pattern:
1. `_start!` sets up the reactive pipeline and subscribes
2. `_stop!` unsubscribes
3. `_fetch!` pushes data to the Subject (or the interval does it automatically)
4. Remove all manual `@async`/`@spawn`/`Condition`/`sleep` patterns

### Step 6: Rewrite LiveMode watchers

Replace propagate loops with Subject subscriptions:
```julia
# Before
propagate_loop(s, ai, w) = begin
    while true
        safewait(w.beacon.process)
        propagate_ohlcv!(ai.data)
    end
end

# After
function setup_propagate!(s, ai, w)
    pipeline = w.beacon.process
        |> Rocket.map(_ -> propagate_ohlcv!(ai.data))
    return Rocket.subscribe!(pipeline)
end
```

Replace balance/positions task loops with interval subscriptions:
```julia
# Before
_balance_task!(w) = @async while isstarted(w)
    f(w)
    safenotify(w.beacon.fetch)
end

# After
function _balance_setup!(w)
    interval = Rocket.interval(1000)  # 1 second
    pipeline = interval |> Rocket.map(_ -> _balance_step(w))
    w._subscriptions[:balance] = Rocket.subscribe!(pipeline)
end
```

### Step 7: Remove dead stubs

- Remove `stream_handler` / `start_handler!` / `stop_handler!` from `LiveMode/src/watchers/utils.jl` and `Watchers/src/impls/utils.jl`
- Remove `py` macro from impls.jl
- Remove `StreamHandler` struct from utils.jl

## Test Strategy

1. **After Phase 1**: Run `Watchers/test/runtests.jl` (73 tests) — should all pass with new async core
2. **After Phase 2**: Same test suite + manual check that watchers start/stop/process correctly
3. **After Phase 3**: Run `PlanarDev/test/runtests.jl` focusing on live-related tests

## Rollback Plan

Each phase is a single coherent commit. If Phase 1 breaks, revert the commit.
Phase 2 depends on Phase 1, Phase 3 depends on Phase 2.
Tag the commit before Phase 1 as `before-rocket-watchers`.

## Risk Assessment

| Risk | Mitigation |
|------|-----------|
| Rocket.jl introduces precompilation overhead | Add to precompile.jl workloads |
| Rocket Scheduler thread model conflicts | Use `Rocket.get_default_scheduler()`; test with both `default_scheduler()` and `AsapScheduler()` |
| Subject subscription lifecycle mismanaged | Use `finalizer(w -> unsubscribe!(w._subscription), w)` in Watcher constructor |
| Race conditions during subscribe/unsubscribe | Rocket handles teardown atomically |
| LiveMode concurrent tests flaky | Increase timeouts; use `@async` wrappers around subscribe for back-compat |

## Approximate LOC

| Component | Current | After | Delta |
|-----------|---------|-------|-------|
| Watchers core (module.jl + functions.jl) | 625 | ~450 | -175 |
| WatchersImpls utils.jl | 693 | ~500 | -193 |
| LiveMode watchers (all) | ~2,300 | ~1,800 | -500 |
| **Total** | **~3,600** | **~2,750** | **~-850** |
