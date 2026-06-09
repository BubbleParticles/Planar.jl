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

15. **Implement the test suite during refactoring, aiming for maximum coverage**: Before starting, search `PlanarDev/test/` for existing test files related to the package being refactored. After migration, create a `test/runtests.jl` with pure unit tests (data conversion, helpers) and mock-HTTP integration tests. Use `Rest.set_http_get!/set_http_post!/set_http_delete!` to mock gateway endpoints — see `Exchanges/test/runtests_fast.jl` for the pattern. The full setup workflow:
    - Create `test/Project.toml` with **no** `name`/`uuid`/`version`/`authors` header (just `[deps]` and optionally `[compat]`)
    - Use `Pkg.develop` for all local transitive deps + the package under test, `Pkg.add` for public test-only deps
    - In `test/runtests.jl`, set up mock HTTP handlers before constructing any exchange — the `else` catch-all branch should return `nothing` for unknown endpoints
    - For endpoint-specific test data (currency tiers, market limits, sandbox mode), add explicit `occursin` branches before the catch-all
    - Seed exchange markets manually (`exc.markets["SYM"] = Dict{String,Any}(...)`) and push types (`push!(exc.types, :swap)`) to avoid gateway calls for market metadata
    - Use the inner constructor `AssetInstance(a, data, exc, margin; limits, precision, fees)` to bypass gateway-dependent outer constructors
    - Verify with `julia --project=<pkg> -e "import Pkg; Pkg.test()"` from the repo root — this catches environment mismatches that direct `include` invocations miss

16. **Coverage requirement: ≥80%, ideally >95%**: Every package must maintain at least 80% line coverage, with a target of >95%. Untested code is a liability — the gateway migration changes the data path (JSON3 vs Python objects, `body=` vs `query=`, `params` dict wrapping), and without coverage, regressions slip through. Use mock-HTTP (`Rest.set_http_get!/set_http_post!`) to test gateway-dependent code paths without spawning a live gateway. Pure unit tests cover data conversion, helper functions, and edge cases. Measure coverage with `julia --project=. -e 'using Pkg; Pkg.add("CoverageTools")'` and the `coverage --run` workflow.

17. **Test via `Pkg.test()` as the canonical invocation**: The standard Julia convention is `julia --project=<pkg> -e 'using Pkg; Pkg.test()'`. Keep the test suite runnable this way — it catches environment mismatches that direct `include` invocations miss. Ensure `test/Project.toml` has no `name`/`uuid`/`version`/`authors` header (those fields cause Pkg to treat the test project as a real package, fail precompilation with "Missing source file", and prevent `Pkg.test()` from succeeding).

18. **Minimize dependencies — upstream packages must not depend on downstream ones**: Keep the dependency graph acyclic with all edges pointing downstream (from foundational to application-level). An upstream package (e.g. `ExchangeTypes`, `Misc`) must never import a downstream package (e.g. `Exchanges`, `Instances`, `Fetch`). A downstream package's `test/Project.toml` must not add extra packages that would create reverse edges — if test-only fixtures or helpers are needed, define them locally in the test file rather than pulling in a downstream package as a test dependency. This prevents circular resolution issues, precompilation failures, and manifests that silently mask import bugs.

19. **Use relative paths for local package dependencies in test Manifests**: When running `Pkg.develop(PackageSpec(path=...))` for a local package in a test environment, pass a relative path (e.g. `"../Foo"` from `Pkg/test/`) rather than an absolute one like `"/project/Foo"`. Absolute paths hardcode the container layout and break when the repository is relocated. Relative paths are resolved from the `test/` directory automatically.

20. **Minimize test deps with `const` aliases or qualified `using`**: When reducing a test package's direct dependencies, use `const Foo = Instances.ParentModule.Bar` aliases or `using Instances.ParentModule.Bar: symbol` instead of `using Bar` to access packages that exist only as transitive deps. Direct `using Bar` in a Pkg.test() environment may fail with "Package not found in current path" because the test environment only guarantees direct deps on LOAD_PATH. Prefer reaching through already-loaded parent modules (e.g. `const HTTP = Instances.Exchanges.ExchangeTypes.CcxtGateway.HTTP`, `using Data.Zarr: ZArray`, `using Data.DataFrames`).

21. **Search for orphan files across ALL included `.jl` files, not just `module.jl`**: When checking if a source file is orphaned, grep for `include("filename")` across every `.jl` file in `src/`, not only `module.jl`. Files can be included from non-root files (e.g. `impl.jl` includes `dispatch.jl`, `load.jl` includes `candles.jl`). A file missing from `module.jl` is not necessarily orphaned if it's included transitively.

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

> For detailed audit findings, bug post-mortems, and historical refactoring notes, see `REFACTOR.md`.