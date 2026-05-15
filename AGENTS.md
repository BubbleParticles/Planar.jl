# Developer Notes

## Getting Started

Before running or developing the bot, or executing the test suite locally, ensure the environment variables from the project's `.envrc` are loaded. The `.envrc` sets critical variables used by tests and the development environment (JULIA_PROJECT, JULIA_LOAD_PATH, JULIA_CONDAPKG_ENV, etc.).

**To load .envrc locally (recommended):**

- Use direnv: run `direnv allow` in the repository root to automatically load .envrc into your shell.
- Or source the file manually: `source .envrc`.

Failing to load .envrc may cause missing package errors during test runs (e.g., packages installed into user/.conda, missing JULIA_PROJECT), unexpected precompilation behavior, or other environment-dependent failures.

Include this check in your developer workflow before running `julia --project=PlanarDev test` or `julia --project=PlanarDev PlanarDev/test/runtests.jl`.

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
   - Ensure outputs match using unit tests
   - Remove `_python` functions only when fully migrated and tested

7. **Use `call_exchange` for CCXT methods**: Do not add specific `fetch_*` functions to CcxtGateway. Downstream packages call them via `call_exchange(client, id, method, query=...)`.

8. **Has cache: always set a TTL**: Any cache added to the Ccxt module must have a TTL. The exchange has dict cache uses 5 minutes.

9. **Mock HTTP in tests**: Use `Rest.set_http_get!/set_http_post!/set_http_delete!` to inject mock HTTP functions. The `Ref{Function}` pattern allows swapping without changing function signatures.

10. **Subprocess crash recovery**: The gateway auto-restarts crashed exchange subprocesses. The Julia side doesn't need retry logic — `call_exchange` will wait for the restart and retry the request.

### Gotchas

1. **Always wrap CcxtGateway calls in try/catch**: The gateway may not be running or may return errors. Always provide Python fallbacks with `_python` suffix.

2. **Type mismatches**: Python returns `Py` objects, CcxtGateway returns JSON. Use `obj["key"]` instead of `obj.key`, and standard Julia types instead of Python types.

3. **Blocking vs async**: Python ccxt has both sync and async versions. HTTP calls to gateway are blocking by default - consider this when migrating code that expects async behavior.

4. **Connection management**: Python ccxt manages exchange connections internally. CcxtGateway requires explicit `start_exchange`/`stop_exchange` calls.

5. **Method availability**: Python's `exchange.has` dictionary tells what methods an exchange supports. CcxtGateway's `exchange_has()` does the same (with TTL caching) - call it before attempting methods.

6. **Null handling**: Python uses `pynull`, `pyNone`, `pynothing`. JSON uses `nothing`, `missing`, or absent keys. Handle both.

7. **Julia function definitions**: Functions in Julia can be defined without the `function` keyword (e.g., `foo(x) = x + 1` or via assignment like `foo = x -> x + 1`). Search for all forms using patterns like `^\s*\w+\s*\(`, `^\s*\w+\s*=`, and `^\s*\w+\s*->`.

8. **JSON3.Object is not Dict**: `JSON3.parse` returns `JSON3.Object`, not `Dict`. Use `Union{Dict, JSON3.Object}` for type assertions, or convert with `Dict{String, Any}(pairs(obj))`.

9. **Gateway must be restarted for Python code changes**: The FastAPI layer may reload with `--reload`, but exchange subprocesses are independent. Restart the full gateway or stop/start the exchange to pick up subprocess changes.

10. **Pidfile for gateway detection**: `/tmp/ccxt_gateway.pid` is written by the gateway on startup and removed on idle-shutdown. This file is used by `using Ccxt` to detect an already-running gateway.