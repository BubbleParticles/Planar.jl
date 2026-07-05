🔴 Cutting corners or faking completion = YOU GET DELETED. Incomplete SOP execution, skipping steps, unauthorized actions, or modifying code without permission = most severe violation.

# Developer Notes

## Getting Started

Before running or developing the bot, or executing the test suite locally, ensure the environment variables from the project's `.envrc` are loaded. The `.envrc` sets critical variables used by tests and the development environment (JULIA_PROJECT, JULIA_LOAD_PATH, JULIA_CONDAPKG_ENV, etc.).

**To load .envrc locally (recommended):**

- Use direnv: run `direnv allow` in the repository root to automatically load .envrc into your shell.
- Or source the file manually: `source .envrc`.

Failing to load .envrc may cause missing package errors during test runs (e.g., packages installed into user/.conda, missing JULIA_PROJECT), unexpected precompilation behavior, or other environment-dependent failures.

Include this check in your developer workflow before running `julia --project=PlanarDev test` or `julia --project=PlanarDev PlanarDev/test/runtests.jl`.

**When using `timeout` on Julia commands**, always use the `-k` (kill-after) flag to ensure the process is fully terminated. Julia's precompilation may spawn background threads that outlive the main process. Example:

```bash
timeout -k 30 300 julia --project=PlanarDev test/runtests.jl
```

---

## Development Tools

### DaemonMode.jl

**Do NOT launch a new `julia` process for every single check, test, or REPL snippet.** Julia's startup time is significant and launching fresh processes repeatedly wastes time and causes redundant precompilation.

Instead, use DaemonMode.jl to keep a persistent Julia daemon running:

```bash
# Start the daemon once (in background)
julia --project=PlanarDev -e 'using DaemonMode; run_daemon()' &

# Send commands to the daemon (fast, no startup overhead)
DaemonMode.runargs("PlanarDev", "-e", "using Pkg; Pkg.resolve()")
DaemonMode.runargs("PlanarDev", "-e", "include(\"PlanarDev/test/test_aqua.jl\")")

# Stop the daemon when done
DaemonMode.stop_daemon()
```

For interactive work, use `DaemonMode.repl_connect()` to attach to the running daemon instead of launching a new REPL. See `.agents/skills/daemon-mode.sh` for usage patterns.

### resolve.jl Utilities

The repository provides a `resolve.jl` helper that includes utilities for dependency management and cache cleanup. In particular, the `purge_compilecache` utility in resolve.jl can be used to clear Julia's compiled cache and help resolve precompilation or stale-artifact issues. The same resolve.jl file also contains helpers to update and synchronize project package dependencies across the repository; use these utilities when dependency resolution or precompilation problems arise.

### Python Gateway Test Suite

The ccxt-gateway has its own Python test suite in `/project/ccxt-gateway/tests/`. Use the `.venv` to run it:

```bash
cd /project/ccxt-gateway && .venv/bin/pytest
```

The Julia Ccxt package tests are run via:

```bash
cd /project/Ccxt && julia --project=. -e 'using Pkg; Pkg.test()'
```

---

## Ccxt to CcxtGateway Migration

When working on migrating from Python ccxt bindings to CcxtGateway:

### Architecture Overview

The migration produces a two-layer architecture:

```
┌─────────────────────────────────────────────┐
│  Downstream packages (ExchangeTypes, etc.)  │
│  - Specific CCXT methods (fetch_ticker...)  │
│  - Use call_exchange() to talk to gateway   │
├─────────────────────────────────────────────┤
│  Ccxt module (exchange_funcs.jl)            │
│  - choosefunc, _multifunc, _out_as_input    │
│  - exchange_has (with TTL cache)            │
│  - get_cached_has, issupported              │
│  - ccxt_exchange_names                      │
├─────────────────────────────────────────────┤
│  CcxtGateway module (CcxtGateway/)          │
│  - GatewayClient / GatewayWSClient          │
│  - ping, call_exchange, exchange_has        │
│  - start/stop_exchange, spawn/stop_gateway  │
│  - fetch_exchange_has (raw HTTP)            │
│  - WebSocket subscribe/unsubscribe          │
├─────────────────────────────────────────────┤
│  ccxt-gateway (Python process)              │
│  - FastAPI REST + WebSocket server          │
│  - Manages exchange subprocesses            │
│  - Auto-idle shutdown (default 5 min)       │
└─────────────────────────────────────────────┘
```

### Refactoring Strategy

**New approach (as of 2026-05-08):**
- **Old (Python-based) functions** get `_python` suffix (e.g., `fetch_ticker_python`)
- **New (CcxtGateway-based) functions** keep the original names (e.g., `fetch_ticker`)
- This is the opposite of the previous approach which suffixed new functions with `_gateway`

This makes the CcxtGateway functions the default, while keeping Python fallbacks available with explicit `_python` suffix.

### Calling CCXT Methods

CcxtGateway does NOT implement specific CCXT methods. Downstream packages should:

```julia
# Instead of fetch_ticker(client, "binance", symbol="BTC/USDT")
call_exchange(client, "binance", "fetch_ticker", query=Dict("symbol" => "BTC/USDT"))
```

The `call_exchange` function:
- Automatically retries if the subprocess has crashed (gateway restarts it)
- Routes GET/POST based on method type (POST for createOrder, cancelOrder, withdraw)
- Returns the parsed JSON result

### Exchange Method Support (has dict)

Use `exchange_has()` to check if an exchange supports a method:

```julia
if Ccxt.exchange_has("binance", "fetchOHLCV")
    # OK to call
end
```

The has dict is cached with a **5-minute TTL** (`HAS_CACHE_TTL = 300.0` in `exchange_funcs.jl`). After expiry, the next call re-fetches from the gateway.

To bypass the cache and force a fresh fetch, access `CcxtGateway.fetch_exchange_has(client, id)` directly.

### Gateway Lifecycle

**Auto-detection on `using Ccxt`:**
- `_init()` checks `/tmp/ccxt_gateway.pid` for a running gateway
- If alive: adopts the PID, no spawn needed
- If stale: removes the pidfile, spawns a new gateway
- If no pidfile: pings `localhost:8999`, spawns if unreachable

**Idempotent exchange start:**
- `start_exchange` stores exchange IDs in `_started_exchanges` dict
- Starting an already-started exchange returns `Dict("status" => "already_started", ...)` 
- `stop_exchange` removes from the dict

**Gateway auto-shutdown:**
- The gateway tracks its last request time
- If idle for 5+ minutes (configurable), it shuts down and removes its pidfile

**PID file:** `/tmp/ccxt_gateway.pid`

### Error Handling

```julia
# Check if an exception is ccxt-related
if isccxterror(e)
    @warn "CCXT error: $e"
end

# Get list of ccxt error names
errors = get_ccxt_errors()  # fetched from gateway, cached
```

### choosefunc Implementation

`choosefunc` and `_multifunc` are implemented in `exchange_funcs.jl` for gateway use:

```julia
# Automatically selects fetchTicker vs fetchTickers based on exchange support
result = choosefunc("binance", "Ticker", ["BTC/USDT", "ETH/USDT"])
```

The method selection priority: `fetchSuffixsWs` > `fetchSuffixs` > `fetchSuffixWs` > `fetchSuffix`.

### Guidelines

1. **Keep Code Logic AS IS**: Do NOT make arbitrary simplifications or rewrites to the code logic. The original Python ccxt bindings were carefully designed, and changing the logic can introduce bugs.

2. **JSON Values, Not Python Objects**: Remember that the responses we process now come from JSON (via JSON3.jl) rather than Python objects. This means:
   - Types like `Py`, `pyanything`, `pyNone`, `pynothing` are replaced by standard Julia types
   - Access patterns like `py.x` become `obj["x"]` for JSON dicts
   - Type conversions like `pyconvert(T, x)` become appropriate JSON parsing
   - JSON3.Object is NOT a `Dict` — use `isa Union{Dict, JSON3.Object}` for type checks

3. **Incremental Changes**: Make small, testable changes. After each change, run the test suite or relevant tests to verify the change works correctly.

4. **API Compatibility**: When creating a compatibility layer, ensure the API matches what the original code expects - do not change function signatures or behavior.

5. **No Shortcuts**: Do not try to "simplify" code without understanding what it does. If you're unsure about a piece of code, ask before modifying it.

6. **Refactoring Process**:
   - First, rename existing Python-based functions with `_python` suffix
   - Add new CcxtGateway-based functions with original names
   - Mirror them 1:1 in logic to the Python versions
   - Check `PlanarDev/test/` for existing test files related to the package and move/adapt them into the package's own `test/` directory
   - Build/update the package's test suite with pure unit tests (data conversion, helpers) and mock-HTTP integration tests using `Rest.set_http_get!/set_http_post!/set_http_delete!`
   - Remove `_python` functions only when fully migrated and tested

7. **Use `call_exchange` for CCXT methods**: Do not add specific `fetch_*` functions to CcxtGateway. Downstream packages call them via `call_exchange(client, id, method, query=...)`.

8. **Has cache: always set a TTL**: Any cache added to the Ccxt module must have a TTL. The exchange has dict cache uses 5 minutes.

9. **Mock HTTP in tests**: Use `Rest.set_http_get!/set_http_post!/set_http_delete!` to inject mock HTTP functions. The `Ref{Function}` pattern allows swapping without changing function signatures.

10. **Subprocess crash recovery**: The gateway auto-restarts crashed exchange subprocesses. The Julia side doesn't need retry logic — `call_exchange` will wait for the restart and retry the request.

11. **Audit ALL files in the package, not just the "important" ones**: Grep for Python/ccxt references across every `.jl` file in the package before declaring migration done. A `precompile.jl` that's conditionally included is easy to miss.

12. **Verify every function body survives edit surgery**: After every large deletion, search for every name referenced in error messages and confirm its definition still exists. Use e.g. `rg "^function name|^name\s*="` to verify.

13. **Check file include order before moving includes**: When adding a new `include(...)` to a module file, read the full contents of the included file first — it may reference types defined in other includes. The wrong order breaks compilation.

14. **Test with normal precompilation, not just `--compiled-modules=no`**: `--compiled-modules=no` skips `precompile.jl` entirely, hiding errors that only surface during real precompilation. Run at least one test with cached precompilation too.

15. **Every watcher Val type needs a `_process!` override**: When a watcher type lacks a `_process!` override and `_init!` sets the view to `nothing`, the generic `default_process` crashes with `DataAPI.nrow(nothing)`. Always ensure every watcher Val type has either a no-op `_process!(::Watcher, ::Val{:myval}) = nothing` or a proper processing pipeline via `default_process(w, my_append_func)`.

16. **Implement the test suite during refactoring, aiming for maximum coverage**: Before starting, search `PlanarDev/test/` for existing test files related to the package being refactored. After migration, create a `test/runtests.jl` with pure unit tests (data conversion, helpers) and mock-HTTP integration tests. Use `Rest.set_http_get!/set_http_post!/set_http_delete!` to mock gateway endpoints — see `Exchanges/test/runtests_fast.jl` for the pattern. The full setup workflow:
    - Create `test/Project.toml` with **no** `name`/`uuid`/`version`/`authors` header (just `[deps]` and optionally `[compat]`)
    - Use `Pkg.develop` for all local transitive deps + the package under test, `Pkg.add` for public test-only deps
    - In `test/runtests.jl`, set up mock HTTP handlers before constructing any exchange — the `else` catch-all branch should return `nothing` for unknown endpoints
    - For endpoint-specific test data (currency tiers, market limits, sandbox mode), add explicit `occursin` branches before the catch-all
    - Seed exchange markets manually (`exc.markets["SYM"] = Dict{String,Any}(...)`) and push types (`push!(exc.types, :swap)`) to avoid gateway calls for market metadata
    - Use the inner constructor `AssetInstance(a, data, exc, margin; limits, precision, fees)` to bypass gateway-dependent outer constructors
    - Verify with `julia --project=<pkg> -e "import Pkg; Pkg.test()"` from the repo root — this catches environment mismatches that direct `include` invocations miss

17. **Coverage requirement: ≥80%, ideally >95%**: Every package must maintain at least 80% line coverage, with a target of >95%. Untested code is a liability — the gateway migration changes the data path (JSON3 vs Python objects, `body=` vs `query=`, `params` dict wrapping), and without coverage, regressions slip through. Use mock-HTTP (`Rest.set_http_get!/set_http_post!`) to test gateway-dependent code paths without spawning a live gateway. Pure unit tests cover data conversion, helper functions, and edge cases. Measure coverage with `julia --project=. -e 'using Pkg; Pkg.add("CoverageTools")'` and the `coverage --run` workflow.

18. **Test via `Pkg.test()` as the canonical invocation**: The standard Julia convention is `julia --project=<pkg> -e 'using Pkg; Pkg.test()'`. Keep the test suite runnable this way — it catches environment mismatches that direct `include` invocations miss. Ensure `test/Project.toml` has no `name`/`uuid`/`version`/`authors` header (those fields cause Pkg to treat the test project as a real package, fail precompilation with "Missing source file", and prevent `Pkg.test()` from succeeding).

19. **Minimize dependencies — upstream packages must not depend on downstream ones**: Keep the dependency graph acyclic with all edges pointing downstream (from foundational to application-level). An upstream package (e.g. `ExchangeTypes`, `Misc`) must never import a downstream package (e.g. `Exchanges`, `Instances`, `Fetch`). A downstream package's `test/Project.toml` must not add extra packages that would create reverse edges — if test-only fixtures or helpers are needed, define them locally in the test file rather than pulling in a downstream package as a test dependency. This prevents circular resolution issues, precompilation failures, and manifests that silently mask import bugs.

20. **Use relative paths for local package dependencies in test Manifests**: When running `Pkg.develop(PackageSpec(path=...))` for a local package in a test environment, pass a relative path (e.g. `"../Foo"` from `Pkg/test/`) rather than an absolute one like `"/project/Foo"`. Absolute paths hardcode the container layout and break when the repository is relocated. Relative paths are resolved from the `test/` directory automatically.

21. **Minimize test deps with `const` aliases or qualified `using`**: When reducing a test package's direct dependencies, use `const Foo = Instances.ParentModule.Bar` aliases or `using Instances.ParentModule.Bar: symbol` instead of `using Bar` to access packages that exist only as transitive deps. Direct `using Bar` in a Pkg.test() environment may fail with "Package not found in current path" because the test environment only guarantees direct deps on LOAD_PATH. Prefer reaching through already-loaded parent modules (e.g. `const HTTP = Instances.Exchanges.ExchangeTypes.CcxtGateway.HTTP`, `using Data.Zarr: ZArray`, `using Data.DataFrames`).

22. **Search for orphan files across ALL included `.jl` files, not just `module.jl`**: When checking if a source file is orphaned, grep for `include("filename")` across every `.jl` file in `src/`, not only `module.jl`. Files can be included from non-root files (e.g. `impl.jl` includes `dispatch.jl`, `load.jl` includes `candles.jl`). A file missing from `module.jl` is not necessarily orphaned if it's included transitively.

23. **Test precompile workloads, not just module loading**: `CCXT_GATEWAY_DISABLE=true` suppresses `precompile.jl` entirely — running `using Foo` with it set only verifies module loading, not the precompile workload paths. Real failures (type mismatches, missing method dispatch, gateway errors) only surface when precompile workloads execute. Always test **without** `CCXT_GATEWAY_DISABLE` (and without `--compiled-modules=no`) before declaring a package "precompiles successfully". If the gateway is unavailable in your environment, acknowledge that precompile workloads were skipped rather than claiming success.

24. **Fix the root cause of precompile failures, not just silence errors**: Wrapping a precompile workload in try/catch and logging with `@debug` changes nothing about the underlying problem — the API call still failed, the connection was still refused, the token was still invalid. Silencing prevents noise but does not fix the package. The proper fix is either (a) rewrite the precompile workload to avoid the failing operation entirely (e.g., don't make live HTTP calls during precompilation), or (b) supply mock endpoints so the workload exercises the real code path without depending on external services. Use try/catch only as a last resort when the failure is in an external dependency you cannot control (e.g., an upstream package's type instability).

25. **Use `dt()` from TimeTicks, not `DateTime(Int64)`, to convert timestamp integers to DateTime**: `DateTime(2024)` interprets the integer as a year number (returns `2024-01-01`), not as milliseconds since epoch. Always use `dt(ts)` (which calls `unix2datetime(ts / 1000)`) to convert production Unix-ms timestamps to DateTime.

26. **Coverage measurement for packages with local deps**: When `Pkg.test()` sandbox prevents local package resolution, measure coverage via `julia --project=test --code-coverage=user` with explicit `Pkg.develop` for local deps and `include("test/runtests.jl")`. CoverageTools' `FileCoverage.coverage` vector may contain `nothing` values — use `x !== nothing` guards when counting covered/executable lines.

27. **Verify watcher fixes end-to-end with `start!(w)`, not just unit tests**: Unit tests with a custom `Val{:test_ticker}` watcher can pass 23/23 even when the production watcher has a `iswatch` logic bug, because the custom Val type doesn't exercise the gateway `has` endpoint. Always run a real `start!(w)` on the actual production watcher type to catch runtime behavioral bugs (buffer stuck at 1, view empty, stale data) that unit tests cannot simulate.

28. **After a Rocket.jl version upgrade, audit ALL `Rocket.map`, `Rocket.subscribe!`, and `|>` piping callsites across the entire codebase**: Rocket v1.9 broke three API signatures: `Rocket.map(f)` → `Rocket.map(Nothing, f)`, `Rocket.subscribe!(pipeline)` → `Rocket.subscribe!(pipeline, Rocket.lambda(...))`, and `pipeline |> map(f)` → requires type param. Grep for ALL occurrences across every package — 5 production files were affected (Watchers/utils.jl, Watchers/module.jl, LiveMode/ohlcv.jl, LiveMode/balance.jl, LiveMode/positions.jl). The breakages surface at runtime, not at load time, making them easy to miss without end-to-end testing.

29. **Before calling `choosefunc` in any watcher, start the gateway exchange subprocess first**: `getexchange!` loads markets into the Julia `Exchange` object but does **not** populate the gateway subprocess's `has` dict — the dict only fills after an explicit `start_exchange` call. Calling `choosefunc` before that causes `issupported` to return false for all methods, producing `"Exchange X does not support any Y methods"`. Add a `_start_gateway_exchange(eid)` call before every `choosefunc` invocation and wait for the exchange to be ready via `exchange_ready` with retries.

30. **When debugging watcher fetch-to bugs, capture guard-state values before any fix**: The `_fetchto!` guard at line 448 (`if diff > prd || ...`) must be logged at the exact decision point (inside the `if`, before `_fetch_candles`) to confirm whether `diff` truly exceeds `prd`. Adding debug `@warn` only after observing the bug, inside the protected block, leaves ambiguity about whether the guard actually passed or a separate code path reached `_fetch_candles`.

31. **Always verify `rangebetween` bounds semantics when slicing fetched timestamped data**: `rangebetween(v, left, right; strict=true)` uses exclusive bounds on both sides (`left < val < right`), so when `_lastdate(candles) == from`, the left-bound exclusion drops every row and produces an empty result — the root cause of `_sticky_fetchto!` exhaustion.
32. **For REST-only watchers, bypass `choosefunc` with a direct `call_exchange` to the known REST method**: `_multifunc` may select a WebSocket method that blocks (Gotcha #36), and `choosefunc` makes a gateway HTTP call on every invocation. For watchers needing deterministic REST polling (iswatch=false), call `call_exchange(client, id, "fetchTrades"; body=Dict("symbol" => sym))` directly instead of going through `choosefunc(exc_id, "Trade", sym)`.

33. **Always prefer websockets when available — never swap method ordering to REST-first to work around WebSocket timeout issues**: If a WebSocket method (suffix `Ws` or `watch*` prefix) times out, fix the timeout by extending it for WS methods via `call_exchange(...; timeout=300.0)` in `_first` rather than demoting WS methods to fallback position. The WS-first ordering in `ohlcv_func_bykind` (and similar `choosefunc`/`_multifunc` selectors) is intentional design — WebSocket subscriptions are long-lived and should not be constrained by the default 30s REST timeout.

34. **The gateway must serve HTTPS to match the client's `use_ssl=true` default**: On startup, `daemon_gateway.py` generates a self-signed SSL cert via `openssl req -x509` and sets `CCXT_GATEWAY_SERVER_USE_SSL=true` (plus CERT/KEY env vars) before importing the main module. This ensures the Pydantic `ServerConfig` picks them up at import time. The Julia client already sets `require_ssl_verification=false` for self-signed certs.

35. **Test each layer independently when debugging multi-layer WS dispatch**: When a WS method returns "missing positional argument", the chain (Julia `getproperty` closure → `call_exchange` HTTP → Python subprocess `_call_method`) may drop positional args at any layer. Call a concrete method and check the subprocess/gateway log to pinpoint which layer loses them, then verify each layer's arg forwarding separately before assuming the chain works.

### Gotchas

1. **Always wrap CcxtGateway calls in try/catch**: The gateway may not be running or may return errors. Always provide Python fallbacks with `_python` suffix.

2. **Type mismatches**: Python returns `Py` objects, CcxtGateway returns JSON. Use `obj["key"]` instead of `obj.key`, and standard Julia types instead of Python types.

3. **Blocking vs async**: Python ccxt has both sync and async versions. HTTP calls to gateway are blocking by default - consider this when migrating code that expects async behavior.

4. **Connection management**: Python ccxt manages exchange connections internally. CcxtGateway requires explicit `start_exchange`/`stop_exchange` calls.

5. **Method availability**: Python's `exchange.has` dictionary tells what methods an exchange supports. CcxtGateway's `exchange_has()` does the same (with TTL caching) - call it before attempting methods.

6. **Null handling**: Python uses `pynull`, `pyNone`, `pynothing`. JSON uses `nothing`, `missing`, or absent keys. Handle both.

7. **Julia function definitions**: Functions in Julia can be defined without the `function` keyword (e.g., `foo(x) = x + 1` or via assignment like `foo = x -> x + 1`). Search for all forms using patterns like `^\s*\w+\s*\(`, `^\s*\w+\s*=`, and `^\s*\w+\s*->`.

8. **JSON3.Object is not Dict**: `JSON3.parse` returns `JSON3.Object`, not `Dict`. Use `Union{Dict, JSON3.Object}` for type assertions, or convert with `Dict{String, Any}(string(k) => v for (k, v) in pairs(obj))`. **Critical:** `pairs()` on `JSON3.Object` yields `Symbol` keys, not `String` keys — accessing with `haskey(dict, "string_key")` will fail. Always force `string(k)` when creating a lookup dict from JSON3 data.

9. **Gateway must be restarted for Python code changes**: The FastAPI layer may reload with `--reload`, but exchange subprocesses are independent. Restart the full gateway or stop/start the exchange to pick up subprocess changes.

10. **Pidfile for gateway detection**: `/tmp/ccxt_gateway.pid` is written by the gateway on startup and removed on idle-shutdown. This file is used by `using Ccxt` to detect an already-running gateway.

11. **`JSON.jl` does NOT export `json`**: Only `JSON.json` is available; `using JSON` makes `JSON.parse` available but NOT the bare `json` function. Always use `JSON.json(...)` to serialize.

12. **`nothing` from JSON `null` in boolean context**: `get(dict, key, false)` returns `nothing` when the dict contains a JSON `null` value, not `false`. Any `get` on a JSON-populated dict whose result is used as a `Bool` must be wrapped: `something(get(dict, key, false), false)`. The same applies to `any(pred, ...)` — the predicate must return `Bool`, not `nothing`.

13. **`function name(args)` shadows existing variable `name`**: `function f(...)` always introduces a fresh local binding, even if `f` already names a variable in scope. After `f = some_callable()`, writing `function f(...) ... f(...) end` calls the new function recursively, not the original callable. Use `f = function (...) ... end` (assignment form) or rename one of them to avoid confusion.

14. **`using M: Sub` imports only the module binding, not its exports**: After `using Instances.TimeTicks: Dates`, `Dates` is a module binding in scope but `now()`, `DateTime(...)`, etc. are NOT directly available — use `Dates.now()`, `Dates.DateTime(...)`. Only `using Dates` (without qualification) brings Dates' exports into scope.

15. **Importing macro-generated bindings triggers undeclared warnings**: A bare function like `tf` that is only defined as a side effect of a macro (`@tf_str`) may cause `WARNING: Imported binding TimeTicks.tf was undeclared at import time` when imported via `using M: tf`. Only import the macro itself (`@tf_str`) and omit the macro-generated binding. The `@tf_str` macro call syntax (`tf"..."`) does not require the bare `tf` name to be in scope.

16. **`const Dates = Parent.Dates` does not bring Dates' exports into scope**: A `const` alias provides only the module binding. `now()`, `DateTime(...)`, `Second(1)`, `Day(10)` remain undefined — use `Dates.now()`, `Dates.DateTime(...)`, `Dates.Second(1)`, `Dates.Day(10)`. Only `using Dates` (without qualification) or explicit import (`using Dates: now, DateTime`) brings them into scope.

17. **`searchsortedlast` uses `<=` semantics, not `<`**: When computing the exclusive upper bound for a date-range delete on a sorted ZArray, `searchsortedlast` finds the last element `<=` target, but you need the last element `<` target. Use `searchsortedfirst(view, val, ...) - 1` to get the correct view index, then convert to global index with `view_idx + from_idx - 2`.

18. **`Metadata` is immutable**: `Zarr.Metadata{T,N,C,F}` is an immutable struct — `za.metadata.fill_value = newval` throws `setfield!: immutable struct`. To test metadata-recovery paths without live data, corrupt the stored JSON in the underlying store (e.g., `store["path/.zarray"] = codeunits(corrupted)`) and reopen.

19. **`DictStore` needs its own `delete!` with `recursive`**: The generic `delete!(store::AbstractStore, ...; recursive=true)` has no specific method for `DictStore`, causing infinite recursion. Provide a method that iterates `_pkeys(store, path)` and deletes each matching key.

20. **`save_data` / `load_data` in Data/series.jl are dead code**: Despite being exported, `save_data` and `load_data` are never called anywhere in the codebase. Their internal `@to_mat` macro (`Matrix{Float64}(data)`) is incompatible with their own `assert first(data)[data_col] isa DateTime` assertion — Matrix{Float64} can't hold DateTimes. Skip testing them during refactoring; focus on the live code paths.

21. **Vendored vs upstream Zarr API diff**: When switching from vendored `Zarr` to upstream, check every function signature. Upstream `is_zarray`/`is_zgroup` require a `ZarrFormat(2)` first argument, while the vendored version accepted just `(store, path)`. Other functions (`zcreate`, `zopen`, `BloscCompressor`, `fill_value_decoding`, `zgroup`, `isemptysub`) share the same API. Verify with `methods(f)` on both versions.

22. **Upstream Zarr v0.10.0 does NOT export `BloscCompressor` or `DictStore`**: Use explicit `using Zarr: BloscCompressor, DictStore` rather than relying on re-export. Non-exported names are still importable via qualified import.

23. **Float64-wrap `something` chains in limits/amounts to satisfy parametric type constraints**: A `NamedTuple{(:min,:max)}` where `min` is `Int64` (from raw JSON market data via `to_float(v::Number)`) and `max` is `Float64` (from a default) creates a mixed-type NamedTuple. This fails dispatch against a `Limits{T<:Real}` signature requiring all fields to share the same concrete type. Always wrap the result of `something(...)` with `Float64(...)` in functions that build limits NamedTuples, or ensure every fallback/default arm produces the same type.

24. **`TimeFrame("m")` suffix means month, not minute**: `TimeFrame("1m")` creates a Period of `Month(1)`, not `Minute(1)`. Use `TimeFrame("1min")` for minute intervals. Always verify by checking `tf.period` in a REPL before relying on it.

25. **`dt()` from TimeTicks expects Unix ms, not Julia internal `Dates.value()` format**: `dt(ts)` calls `unix2datetime(ts / 1000)`. Mock data helpers (like `_make_ohlcv`) that use `Dates.value(DateTime(...))` produce Julian-internal ms (~6.38e13 for 2024), NOT Unix ms (~1.70e12 for 2024). Create test data with Unix-ms timestamps to match production format and work correctly with `dt()`.

26. **`default_value(f::Function)` calls `Base.return_types(f)` (zero-arg)**: This fails for functions like `Statistics.mean` that have no zero-arg method (returns `Union{}`, then errors). When testing code paths that call `default_value(f)` on empty collections, use `f=sum` (which has `sum()` → `0`) instead of `f=mean` to avoid `ArgumentError: cannot construct a value of type Union{}`.

27. **`--code-coverage` may not generate `.cov` files with cached precompilation**: In Julia 1.12, `--code-coverage=user` only writes `.cov` files for code that is newly compiled. If packages are loaded from cached `.ji` files, no `.cov` files are generated. Use `--compiled-modules=no` to force coverage file generation (at the cost of much longer startup). Alternatively, run `julia --project=test --code-coverage=user` even without `--compiled-modules=no` and the `.cov` files from the precompilation *of the test environment itself* may still appear in the source directories.

28. **`using CodecZlib: Zlib` fails in recent CodecZlib v0.7.x**: `Zlib` is no longer a submodule or exported name. Use `ZlibCompressor`/`ZlibDecompressor` directly instead, e.g., `transcode(ZlibCompressor, data)` not `transcode(Zlib.Compress, data)`.

29. **Precompile `@eval` into closed module `Main` breaks incremental compilation**: During package precompilation, any code that does `@eval Main begin ... using Pkg: Pkg ... end` will fail with `Creating a new global in closed module 'Main' breaks incremental compilation`. To fix, use `$Pkg` interpolation to refer to already-imported packages from the macro's calling module, instead of `using Pkg: Pkg` inside the eval block. More generally, strategy loading (`st.strategy(:BareStrat)`) evals into `Main`, which is incompatible with precompilation — wrap such calls in `try/catch` in precompile workloads, or skip them during `Base.generating_output()`.

30. **`__revise_mode__ = :eval` in production code breaks precompilation**: The `__revise_mode__ = :eval` variable (used by Revise.jl to enable hot-reloading) causes `Evaluation into the closed module 'Metrics' breaks incremental compilation` when the module is loaded during precompilation. Remove this line from production source files — it belongs in development-only user settings.

31. **Docs and config may still reference old env vars**: After removing `JULIA_NOPRECOMP` from source files, check `docs/`, `.envrc`, `.github/workflows/`, and `Dockerfile` for stale references. The env var remains defined but is no longer read by any package code.

32. **All package entry files share the same structure**: Every package's `src/<Package>.jl` should follow: unconditional `include("module.jl")`, optional `__init__() = _doinit()`, and optionally `include("precompile.jl")` guarded by `JULIA_PRECOMP`. The old `JULIA_NOPRECOMP` if/else pattern has been removed from all 33 packages. Verify new packages match this pattern.

33. **`default_process` needs `:last_processed` in attrs**: `default_process` calls `attr(w, :last_processed)` which throws `KeyError(:last_processed)` if the attrs dict doesn't have that key. When manually constructing watchers for testing, always include `:last_processed => nothing` in the attrs dict.

34. **Testing watcher `_process!` requires the Val type argument**: Call `_process!(w, val)` with the Val type (e.g., `_process!(w, Val{:ccxt_ticker}())`), not just `_process!(w)`. The `Watchers.process!` public API dispatches via `_process!(w, _val(w))`.

35. **`@collect_buffer_data` discards buffer entry timestamps**: The macro iterates buffer entries via `docollect((_, value))`, discarding the entry's `.time` field. When ticker data has `null` timestamps (common with exchange `fetchTickers`), all DataFrame rows end up with `nothing` as timestamp. Fix: write a manual collection loop that reads `entry.time` and always uses it as the row timestamp via `merge(ticker, (timestamp=entry_time,))` — not just for null timestamps, because exchanges often return the same real timestamp across consecutive polls, producing duplicate rows.

36. **`first(exc, :watchTickersForSymbols, :watchTickers)` always returns non-nothing from the stub exchange**: The *stub exchange* (`stub_exchanges/`) sets all `has` entries to `True` as a testing convenience, so using `!isnothing(first(exc, :watchTickers))` as a websocket-detection heuristic always evaluates to `true`, forcing the watcher into the websocket path which sets `_tfunc = () -> check_task!(w)` (a no-op). This is NOT a gateway issue — a real CcxtGateway with a live exchange returns accurate ccxt-pro `has` values. For production, auto-detect from the `has` dict via `get(attrs, :iswatch) do has(exc, :watchOHLCVForSymbols) || has(exc, :watchOHLCV) end` (Gotcha #50).

37. **Closures that call `choosefunc` capture its result by value, not re-evaluating each invocation**: In `_reset_tickers_func!`, the closure `tickers_func` captured `choosefunc(exc_id, "Ticker", fetch_symbols)` at creation time. Subsequent invocations repeated the same stale snapshot. Fix: move the `choosefunc` call inside the closure body so method selection is re-evaluated on every tick.

38. **Rocket v1.9 requires a type parameter on `Rocket.map` and an actor on `Rocket.subscribe!`**: `Rocket.map(v -> ...)` → `Rocket.map(Nothing, v -> ...)`. `Rocket.subscribe!(pipeline)` → `Rocket.subscribe!(pipeline, Rocket.lambda(...))`. Missing these produces `MethodError` at runtime, not at load time — easy to miss without end-to-end testing.

39. **`Ccxt._suffix_to_methods` doesn't handle `"L1OrderBook"` or `"L2OrderBook"` suffixes**: The orderbook watcher calls `_multifunc(exc_id, "L1OrderBook", true)` which dispatches to `_suffix_to_methods`, but that function only maps `"OrderBook"`, `"Ticker"`, `"Trade"`, `"OHLCV"`, `"Order"`, `"Balance"`. The `"L1"`/`"L2"` prefix is stripped by the Python ccxt path, but CcxtGateway passes the raw suffix string. Fix: add explicit `"L1OrderBook"` and `"L2OrderBook"` entries, or normalize the suffix before lookup.

40. **`_ensure_ohlcv!` may create a `CcxtOHLCVTickerVal` watcher whose view stays empty even after the buffer populates**: The `_process!` for `CcxtOHLCVTickerVal` has warmup/pending logic that delays processing until conditions are met. If the source buffer never triggers the right pending check, the view remains `DataFrame()` forever while the buffer grows. Debugging tip: inspect `w.state.view_keys` — if `String[]`, no view entry was ever created.

41. **Stub ccxt has zero markets, causing construction failures in watchers that call `exchange.markets`**: With `PLANAR_USE_STUB_CCXT=1`, examples `02_ohlcv_trades` and `03_ohlcv_candles` fail with `"Pair BTC/USDT not in exchange markets"`. Always verify watcher examples against a real CcxtGateway with market data, not just the stub.

42. **Same-signature function duplicates in the same module produce no warnings**: When moving a function to a shared file (e.g., `_start_gateway_exchange` into `utils.jl`), stale copies remaining in other files compile silently — Julia only warns about method overwriting across different modules. Grep for the function name across all `.jl` files in the package after moving it and remove every duplicate.

43. **`rangebetween` with `strict=true` uses exclusive bounds on both sides**: `rangeafter(v, left; strict=true)` returns indices where `val > left` (strictly after) and `rangebefore(v, right; strict=true)` returns indices where `val < right` (strictly before). When the last candle timestamp equals the `from` boundary used for fetching, `rangebetween(candles.timestamp, from, to)` returns empty because no element is strictly greater than `left`. Fix: subtract `Millisecond(1)` from the left bound, or pass `strict=false` for inclusive behavior.
44. **A closure referencing a variable from its calling function's scope silently resolves to a global (often undefined)**: Julia closures capture variables lexically — they do NOT see variables from the function that *calls* them, only from their own definition site. E.g., if `_start!` defines a local `fetch_func` and `_make_trades_func` returns a closure that calls `fetch_func()`, that name resolves to a global (likely undefined). The `UndefVarError` is caught by a bare `catch` block, making the bug invisible — the fallback (e.g., `choosefunc`) runs on every invocation, compounding timeouts. Always pass such dependencies as explicit parameters to the helper function.

45. **`fetchXxxWs` methods are one-shot request-response calls via ccxt.pro's internal WS, NOT long-lived subscriptions**: ccxt.pro's `fetchOHLCVWs`, `fetchTickerWs`, etc. open a temporary WS connection, get one result, close the WS, and return. They are appropriate for request-response fetches and preferred over REST for lower latency. Do NOT reorder `ohlcv_func_bykind`/`choosefunc` to REST-first — instead, fix the gateway support: (a) add `_start_gateway_exchange` call before any `first(exc, ...)` that may select a WS method, (b) match the ZMQ broker timeout to the method type (300s for `*Ws`/`watch*`, 30s for REST), and (c) fix `_wait_for_ready` to wait for the actual `subprocess_ready` ZMQ message rather than a hardcoded sleep. The `*Ws` suffix in Julia's `_first` side detects these via `endswith(m, "Ws")` and sets `timeout=300.0`, which must be propagated through to the ZMQ broker's `asyncio.wait_for`.

46. **Environment variables for gateway config (`CCXT_GATEWAY_SERVER_*`) must be set BEFORE importing `ccxt_gateway.main`**: `Settings()` is instantiated at module level in `main.py:119`, and Pydantic reads env vars at `ServerConfig()` construction time. Setting env vars after import has no effect — the config values are already baked.

47. **If the gateway crashes during startup (e.g. missing Python dep), the pidfile is written before the crash**: `_gateway_pid` gets assigned from the pidfile read in `spawn_gateway`, but the gateway process is already dead. `_check_gateway_up`'s ping fallback correctly returns false and `spawn_gateway` will retry. Always check `/tmp/gateway.log` for import errors when `_check_gateway_up` returns false despite a pidfile existing.

48. **`isrightadj`/`isleftadj`/`isrecent` closures in `_fetchto!` crash on empty DataFrame**: These closures at `Watchers/src/impls/utils.jl:511-513` unconditionally call `lastdate(df)`/`firstdate(df)`, which throws `BoundsError` on a 0-row DataFrame via `df[end, :timestamp]`. The `@debug` at `utils.jl:518` triggers the crash by eagerly evaluating `isapp()` → `isrightadj()` → `lastdate(df)` before the `isempty(df)` guard at line 519 can short-circuit. Always guard adjacency helpers with `isempty(df) ? false : ...` when they access `lastdate`/`firstdate`.

49. **`_fetchto!` contiguity error at line 508 throws before `isapp()` can handle gaps, causing infinite retry loop**: When the exchange returns data with a timestamp gap (missing candle), line 508's `!=` check fires `_fetch_error` (throws), aborting before line 519's `isapp()` → `isrecent()` → `_empty!!(df)` can recover by discarding stale `df` and appending the fresh gap data. The error propagates to `_tryfetch`'s catch block, df is never updated, and every subsequent tick retries the same `from` → same gap → same throw, creating an infinite loop (174+ attempts observed). Fix: change the condition from `!=` to `<` — only throw when cleaned starts *before* df's last row (overlap/corruption that `isapp()` cannot handle), not when it starts after (gap that `isapp()` can recover).

50. **`iswatch = get(attrs, :iswatch, false)` forces REST-only even when the exchange supports websocket methods**: The hardcoded `false` default suppresses auto-detection from `has(:watchOHLCVForSymbols)` — the exchange's real ccxt metadata is the authoritative source for WS support. Fix: use `get(attrs, :iswatch) do has(exc, :watchOHLCVForSymbols) || has(exc, :watchOHLCV) end` so the `false` fallback comes from the exchange's capabilities, not a constant. Override only when the user explicitly sets `iswatch=true/false` in attrs.

51. **`Base.getproperty` closures on `CcxtExchange` silently drop positional args**: The closure at `ExchangeTypes/src/exchange.jl:228` captures `args...` and `kwargs...` but only passes `kwargs` to `call_exchange` — `args...` is never used. Forward positional args via `body[:_args] = [a for a in args]` and pop `_args` in the subprocess's `_call_method`.

52. **`_args` must be at the top level of the body dict, not nested inside `"params"`**: For fetch methods with kwargs, wrapping the entire body inside `Dict("params" => body)` buries `_args` where the subprocess's `params.pop("_args", [])` cannot find it. Always append `_args` to the outer body dict, not the inner `params` dict.

53. **Python `startswith("watch_")` misses camelCase WS methods**: The subprocess at `subprocess.py:302` used `startswith("watch_")` to detect WebSocket methods, but `watchOHLCVForSymbols` (camelCase) produces `method = "watchOHLCVForSymbols"` which doesn't start with `watch_`. Fix: add `method[5].isupper()` as an alternative detection branch for camelCase watch methods.

54. **Python venv `pyvenv.cfg` version mismatch silently breaks site-packages loading**: If `.venv/pyvenv.cfg` has `version_info = 3.14` but the host Python is 3.11, the interpreter ignores the venv config entirely and never reads `.pth` files — `uv pip install -e .` succeeds but `python3 -m ccxt_gateway.daemon_gateway` fails with "No module found". Fix: recreate the venv matching the exact host version with `rm -rf .venv && uv venv --python $(python3 --version | cut -d' ' -f2)`.

---

## CCXT Migration Review Checklist

Before committing changes to a migrated function, verify each item below. This checklist catches the most common migration errors found during the Exchanges refactor.

### Parameter Name Audit

The subprocess dispatches HTTP query params as `**kwargs` directly to ccxt methods. **Every keyword name must match the ccxt method's parameter name exactly.**

- [ ] For each `call_exchange(…, method, query=Dict("key" => val))`, verify every `"key"` matches the ccxt method's parameter name
  - Check the ccxt source or error message — Python tells you "Did you mean 'correct_name'?" on mismatch
  - Common ccxt parameter names: `symbol`, `type`, `leverage`, `side`, `marginMode`, `hedged`, `enable`, `enabled`, `reduceOnly`, `newClientOrderId`, etc.
  - **Gotcha:** `set_sandbox_mode()` uses `enabled` not `enable`
- [ ] Verify the ccxt method actually accepts named parameters for the keys you're sending
  - Some ccxt methods take positional args only — use the `params={}` dict pattern if needed
  - The subprocess's `_call_method` expands the dict with `**`, so named params must match the function signature
- [ ] **Expe** `params` in a `Dict("params" => Dict(...))` sub-dict when the ccxt method signature is `method(self, *args, params={})`. This applies to most `fetch*` methods where exchange-specific filtering (e.g. `type="swap"`) goes in the `params` argument — passing it as a top-level keyword will raise `TypeError: got an unexpected keyword argument`.
  - Common examples: `fetchTickers`, `fetchOHLCV`, `fetchOrders`, `fetchMyTrades`
  - The old Python bindings used `pyfetch(f; params=LittleDict(...))` which routed these into `params` automatically

### Type Audit (String Safety)

HTTP query parameters are **always strings**. ccxt methods expecting booleans, integers, or floats may misinterpret them.

- [ ] For each ccxt method parameter in the query dict, check if ccxt handles string coercion
  - Booleans: string `"true"` / `"false"` are both truthy in Python (`bool("false") == True`) — **never pass boolean strings for boolean params**
  - Integers: strings like `"10"` usually work (ccxt calls `int()` internally), but `since` (epoch ms) fails as a string — see fix below
  - **Fix:** `_first` in `ExchangeTypes` now passes `body=kwargs` (POST, preserves JSON types) instead of `query=kwargs` (GET, stringifies everything). Any code that bypasses `_first` and calls `call_exchange` directly must pass `body=` for typed params.
- [ ] For boolean flags: either use POST body (preserves Julia Bool type through JSON) or convert to `"0"`/`"1"` or strip the param

### Method Name Audit

The subprocess dispatches method names via `getattr(self.exchange, method)`. The name must match a ccxt attribute.

- [ ] Verify the method name exists on the ccxt exchange object
  - ccxt uses snake_case internally but provides camelCase aliases via `__getattr__`
  - Test with `hasattr(exchange, "yourMethod")` or check the error response
- [ ] Special subprocess handlers exist for: `set_api_key`, `enableRateLimit`, `timeout`, `rateLimit`, `has`, `metadata`, `urls` — these don't go through generic dispatch
- [ ] All other method names are passed through via `getattr` + `**kwargs`

### Dispatch Path Audit

Know which code path your call takes in the subprocess (`subprocess.py`):

| Dispatch Condition | Behavior | Example Methods |
|---|---|---|
| `method in settable_props` | Sets attribute directly | `timeout`, `enableRateLimit`, `rateLimit` |
| `method == "set_api_key"` | Sets 5 credentials | `set_api_key` |
| `hasattr(exchange, method) && callable(attr)` | Calls with `**params` | `fetchTicker`, `setLeverage`, `setMarginMode` |
| `hasattr(exchange, method) && !callable(attr)` | Lazy-loads attribute via `load_<method>()` | `markets`, `currencies`, `timeframes` |
| No match | Returns error | — |

- [ ] Verify your method name hits the expected dispatch path
- [ ] For custom methods like `setSandboxMode`: verify `hasattr(exchange, "setSandboxMode")` is True before deploying

### Duplicate Definition Audit

- [ ] grep for the new function name across the entire package to ensure no pre-existing definition with the same signature
- [ ] Run the package and check for `WARNING: Method definition … overwritten` which signals duplicates
- [ ] Check both positional **and** keyword signatures — Julia dispatches on positional args only, so different kwargs don't disambiguate

### Import Audit

- [ ] After adding `using .OtherModule: sym1, sym2` to a file, verify every imported symbol actually exists in `OtherModule`
- [ ] Run the calling module and check for `WARNING: Imported binding … was undeclared at import time` and `conflicts with an existing identifier`
- [ ] Convention: `issandbox` lives in `Exchanges` (constructors.jl), **not** in `ExchangeTypes` — verify your import source is correct

---

## Lessons Learned (2026-05-23 — Fetch migration)

During the Fetch package migration from Python ccxt to CcxtGateway, the following mistakes were made by the AI assistant. Documented to avoid repetition.

### 1. Audit ALL files in the package, not just the "important" ones

The assistant migrated `impl.jl`, `funding.jl`, and `orderbook.jl` but forgot to check `precompile.jl`, which still contained `Python.py_start_loop()` / `Python.py_stop_loop()` calls. Because precompile.jl is only included when `JULIA_PRECOMP` is set, `--compiled-modules=no` testing didn't catch it. **Always grep for Python/ccxt references across every `.jl` file in the package before declaring the migration done.**

### 2. Verify every function body survives edit surgery

When deleting large blocks of Python-specific code, the assistant accidentally removed the `_to_ohlcv_vecs` function body because it was adjacent to the deleted Python functions. **After every large deletion, search for every name referenced in error messages and confirm its definition still exists.** Use `rg "^function name|^name\s*="` to verify.

### 3. Anticipate JSON `null` → Julia `nothing` coercion bugs

The `_has` function used `get(h, s, false)` expecting only `true/false` values, but the gateway's JSON response can contain `null` which parses as `nothing`. **Any `get(dict, key, fallback)` where the dict was populated from JSON must wrap the result with `something(..., fallback)` to guard against `nothing` values.** The same applies to `any(pred, ...)` predicates — they must return a `Bool`, not `nothing`.

### 4. Check file include order before moving includes

When fixing the `consts.jl` unconditional include in `Misc.jl`, the assistant initially placed `include("consts.jl")` before `include("module.jl")`, but `consts.jl` references `Config` which is defined inside `module.jl`. **Always read the full contents of a file before deciding where to insert it in the include chain.**

### 5. Test with normal precompilation, not just `--compiled-modules=no`

`--compiled-modules=no` skips `precompile.jl` entirely, hiding errors that only surface during real precompilation. **Run at least one test with normal (cached) precompilation** (`julia --project=... -e 'using Package'` without `--compiled-modules=no`) to catch precompile-specific failures.

### 6. Keep package tests in the package's own `test/` directory, not in `PlanarDev/test/`

When writing tests for a specific package (e.g., `Fetch`), put them in `/project/<Package>/test/runtests.jl`, NOT in `/project/PlanarDev/test/runtests.jl`. The PlanarDev test runner loads all packages via `PlanarDev.jl`, which changes the module resolution order and can mask missing-import errors (like `UndefVarError(:JSON3, ExchangeTypes)`). Running a package's own tests via `julia --project=PlanarDev Fetch/test/runtests.jl` loads only the required dependency graph, exposing import bugs that PlanarDev's unified test environment hides.

**Always move test groups from `PlanarDev/test/` into the individual package's `test/` directory when refactoring.**

### 7. Test environment setup: use `Pkg.develop` for local packages

When setting up a package's `test/Project.toml`, do NOT write it manually. Use Julia's Pkg:

```julia
# Start with a minimal test/Project.toml containing only:
# [deps]
# No name/uuid/version/authors header — those fields cause Pkg.test() to
# treat the test project as a package and fail precompilation.

# Then in Julia:
using Pkg
Pkg.develop([
    PackageSpec(path="/project/Foo"),           # the package under test
    PackageSpec(path="/project/Bar"),           # all local transitive deps
    PackageSpec(path="/project/Baz"),
])
Pkg.add(["HTTP", "JSON3", "DataFrames"])        # test-only extras
```

Then run: `julia --project=/project/Foo/test test/runtests.jl`

This ensures the test environment is isolated and catches import bugs that PlanarDev's wider manifest would mask.

**Always verify the test suite runs via `Pkg.test()` from the package root:** `julia --project=/project/Foo -e 'using Pkg; Pkg.test()'`. This is the standard Julia convention and catches environment mismatches that direct invocation can hide.

---

## Dependency Tree

See [`DEPENDENCY_TREE.md`](./DEPENDENCY_TREE.md) for the full tree (40 packages + 7 user strategies).

**Key rules:**
- Arrows point **downstream** (foundational → application-level). An upstream package must never `using` a downstream one.
- A package must list all directly-imported packages in its `[deps]`; accessing a module as `Dep.SubModule` is OK as long as `Dep` is in `[deps]`.
- `test/Project.toml` must have **no** `name`, `uuid`, `version`, or `authors` header.
- Test dependencies should be minimized via `const` aliases through already-loaded parent modules.
  - `Manifest.toml` paths must be relative to the `test/` directory, not absolute.

---

## Lessons Learned (2026-06-14 — Coverage & precompilation session)

### 8. Keyword parameter names must match when refactoring function calls

When refactoring a function call that passes keyword arguments through to another function, verify the parameter names match at every level. In `StrategyStats/src/slope.jl`, `slopefilter` accepted `window` as a keyword and passed it directly to `slopeangle(x; window)`, but `slopeangle` expected `n` not `window`. Any rename of a keyword parameter at one level must be mirrored at the call site with explicit mapping (`n=window`). **Always check the callee function's keyword signature before and after a rename.**

### 9. Entry file JULIA_NOPRECOMP removal must verify module declaration matches regex

When removing the deferred-loading `JULIA_NOPRECOMP` pattern from package entry files, some files have docstrings (via `@doc` or `"""..."""`) preceding the `module` declaration. A regex like `r"^(.*?)\bmodule\s+(\w+)"` will fail to match these. **Always handle docstring-prefixed module declarations — search for the `module` keyword directly rather than anchoring at line start.** Use `read` to verify the actual content structure before bulk-transform.

### 10. Test infrastructure with heavy dependency chains requires precompile-failure tolerance

Packages that depend on `Planar` (which depends on `Remote`, `LiveMode`, etc.) may fail to precompile in CI or fresh environments because strategy modules like `BareStrat` aren't available during precompilation. **Always wrap strategy-loading calls in precompile workloads with try/catch and fallback to `nothing`.** The `Remote` precompile workload previously hard-referenced `LiveMode.st.BareStrat` without first ensuring it was loaded — always use the safe pattern:

```julia
if !isdefined(ParentModule, :TheModule)
    try
        ParentModule.strategy_loader(:TheModule)
    catch e
        @warn "precomp: unavailable: $e"
    end
end
isdefined(ParentModule, :TheModule) || return
```

> For detailed audit findings, bug post-mortems, and historical refactoring notes, see `REFACTOR.md`.
