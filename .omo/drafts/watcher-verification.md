# Watcher Verification Plan — Draft Decisions

**Slug**: `watcher-verification`  
**Intent**: CLEAR  
**Status**: `exploration-complete`  

---

## Exploration Summary

### Watcher System Architecture

**Key components** (from `Watchers/src/module.jl`, `functions.jl`, `defaults.jl`):
- `Watcher{T}` struct manages data fetch/process/flush pipeline
- `buffer::CircularBuffer{BufferEntry(T)}` stores `(time, value)` tuples
- `attrs[:view]` holds processed DataFrame (per-symbol for ccxt_tickers)
- `_exec.errors` tracks errors via `CircularBuffer{Tuple{Any,Vector}}`
- `start!(w)` sets up Rocket.jl fetch pipeline, `stop!(w)` tears it down

**CCXT tickers watcher** (`Watchers/src/impls/ccxt_tickers.jl`):
- Type: `Watcher{Dict{String,CcxtTicker}}`
- Fetch: calls `choosefunc(exc, "Ticker", symbols...)` → returns `Dict{String,CcxtTicker}`
- Process: `_ccxt_tickers_process!` collects buffer by symbol, appends to per-symbol DataFrames
- Filters exact duplicates: `filter(!=(last_val), nts)`

**Gateway** (`Ccxt/src/CcxtGateway/rest.jl`):
- **No response caching** — direct HTTP calls via `HTTP.get/post`
- Injectable HTTP: `_http_get::Ref{Function}`, `set_http_get!(f)` for mocking
- Only cached: `_started_exchanges` (dict of started exchange IDs), `_ccxt_errors` (error names list)

### Test Patterns

**From existing tests** (`Watchers/test/runtests.jl`):
- Use `watcher()` constructor with `start=false` for manual control
- `pushnew!()` for buffer tests
- Missing: error tracking tests, view DataFrame tests, gateway integration tests

**Mock pattern** (`Exchanges/test/runtests_fast.jl`):
```julia
using CcxtGateway.Rest: set_http_get!
set_http_get!((url; kwargs...) -> HTTP.Response(200, JSON3.write(mock_data)))
```

---

## Verification Requirements (User Request)

1. ✅ Buffer populated correctly after `start!(w)` — verify `length(w.buffer) >= 2`
2. ✅ No errors — verify `isempty(Watchers.errors(w))`
3. ✅ Timestamps not duplicated — verify `time[i] != time[i+1]` OR `value[i] != value[i+1]`
4. ✅ Gateway no caching beyond micro-caching — verify via counter + unique values
5. ✅ View DataFrame receives 2+ new rows per symbol — verify `nrow(w.view["SYM"]) >= 2`

---

## Test Plan Structure

**8 Tasks**:
1. Infrastructure setup (HTTP mock imports, helper functions)
2. Buffer population test
3. Error tracking test
4. Timestamp uniqueness test
5. Gateway caching test
6. View DataFrame update test
7. Live integration test (optional, skip if gateway unavailable)
8. Test runner updates (`test/Project.toml`, `@testset` wrapper)

**All tests** wrapped in `@testset "CCXT Watcher Verification"` block.

---

## Approval Gate

**Decision**: Plan complete, awaiting user approval to implement.

**Implementation trigger**: User says "approve" or "implement" or "start work".

**Execution mode**: Tests will be written to `Watchers/test/runtests.jl` — no production code changes.

---

*Draft created: 2026-06-24*  
*Next: Await approval, then write tests*