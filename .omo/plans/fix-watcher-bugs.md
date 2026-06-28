# fix-watcher-bugs - Work Plan

## TL;DR (For humans)

**What you'll get:** 3 CCXT watchers (orderbook, OHLCV candles, average OHLCV) that crash when started now work correctly. 2 API watchers (CoinGecko ticker, CoinPaprika markets) that fail to parse exchange data now handle null/missing fields properly. All verified end-to-end against real exchanges.

**Why this approach:** Each bug was discovered during real integration testing against a live Binance/Bybit gateway, so each fix is immediately verifiable — no guesswork. Fixes are surgical (2-10 lines each) and don't touch watcher business logic.

**What it will NOT do:** Refactor watcher architecture, change CcxtGateway Python code, or fix any bugs beyond the 5 discovered during validation.

**Effort:** Short
**Risk:** Low — fixes are in isolated utility functions; all covered by existing unit tests (155 pass) plus new gateway validation runs.

**Decisions to sanity-check:** (1) `_suffix_to_methods` naming for L1/L2 orderbook methods, (2) whether `fromdict` should be modified vs. pre-processing API responses for CoinGecko/CoinPaprika.

Your next move: **Approve** this plan. Full execution detail follows below.

---

> **TL;DR (machine):** Short effort, low risk. 5 bug fixes across 6 files. Fixes: (1) add L1/L2OrderBook to `_suffix_to_methods`, (2) fix `@py` macro hygiene with `esc()`, (3) fix `buffer_capacity=0`→1, (4) fix CoinGecko `nothing`→Float64 conversion in `fromdict`, (5) fix CoinPaprika Symbol→String key issue. Verify with real gateway + API calls. No architecture changes.

## Scope
### Must have
1. Fix `_suffix_to_methods` in `Ccxt/src/exchange_funcs.jl` to handle L1OrderBook/L2OrderBook suffixes
2. Fix `@py` stub macro in `Watchers/src/impls/impls.jl` to properly escape symbols
3. Fix `buffer_capacity=0` in `Watchers/src/impls/ccxt_average_ohlcv_watcher.jl`
4. Fix CoinGecko parsing in `cg_ticker.jl` to handle `nothing` values for Float64 fields
5. Fix CoinPaprika parsing in `cp_markets.jl` to handle Symbol dict keys
6. Run unit tests (Watchers, Ccxt) after each fix
7. Run end-to-end validation of all fixed watchers against real gateway/APIs

### Must NOT have (guardrails, anti-slop, scope boundaries)
- No refactoring of watcher architecture or business logic
- No changes to CcxtGateway Python code
- No changes to CoinGecko/CoinPaprika API wrapper modules themselves
- No fixing bugs beyond the 5 discovered during validation
- No adding new features or tests beyond what's needed to verify the fixes

## Verification strategy
- **Test decision**: Fixes-first, then verify with existing tests + end-to-end validation
- **Unit tests**: Run `julia --project=Watchers -e 'using Pkg; Pkg.test()'` — 155 existing tests must still pass
- **Ccxt tests**: Run `julia --project=Ccxt -e 'using Pkg; Pkg.test()'` 
- **End-to-end validation**: Run each example file against real CcxtGateway (Binance) or live API (CoinGecko, CoinPaprika), verify buffer populated, no errors, view populated
- **Evidence**: `.omo/evidence/fix-watcher-bugs/` with per-task result logs

## Execution strategy
### Parallel execution waves
- **Wave 1 (all parallel)**: Todos 1, 2, 3, 4, 5 — independent code fixes
- **Wave 2**: Todo 6 — run unit tests after all fixes applied
- **Wave 3**: Todo 7 — end-to-end validation of each fixed watcher
- **Wave 4**: Final verification wave

### Dependency matrix
| Todo | Depends on | Blocks | Can parallelize with |
| --- | --- | --- | --- |
| 1. _suffix_to_methods fix | — | — | 2, 3, 4, 5 |
| 2. @py macro fix | — | — | 1, 3, 4, 5 |
| 3. buffer_capacity fix | — | — | 1, 2, 4, 5 |
| 4. cg_ticker parsing fix | — | — | 1, 2, 3, 5 |
| 5. cp_markets parsing fix | — | — | 1, 2, 3, 4 |
| 6. Unit test run | 1, 2, 3, 4, 5 | — | — |
| 7. E2E validation | 1, 2, 3, 4, 5 | — | 6 |

## Todos

- [x] 1. Add L1OrderBook/L2OrderBook to `_suffix_to_methods`
  What to do / Must NOT do: Add TWO new `elseif` branches to `_suffix_to_methods` in `Ccxt/src/exchange_funcs.jl`. Must NOT change existing branches. Must NOT break the existing test at `Ccxt/test/test_rest_logic.jl:70-76`.
  - `suffix == "L1OrderBook"` → `("fetchL1OrderBooks", "fetchL1OrderBook", "fetchL1OrderBooksWs", "fetchL1OrderBookWs")`
  - `suffix == "L2OrderBook"` → `("fetchL2OrderBooks", "fetchL2OrderBook", "fetchL2OrderBooksWs", "fetchL2OrderBookWs")`
  Parallelization: Wave 1 | Blocked by: none | Blocks: 6, 7
  References: `/Planar.jl/Ccxt/src/exchange_funcs.jl:58-74`, `/Planar.jl/Watchers/src/impls/ccxt_orderbook.jl:18-32`
  Acceptance criteria: `julia --project=Ccxt -e 'using Ccxt; @assert Ccxt._suffix_to_methods("L1OrderBook") == ("fetchL1OrderBooks", "fetchL1OrderBook", "fetchL1OrderBooksWs", "fetchL1OrderBookWs"); @assert Ccxt._suffix_to_methods("L2OrderBook") == ("fetchL2OrderBooks", "fetchL2OrderBook", "fetchL2OrderBooksWs", "fetchL2OrderBookWs")'`
  QA scenarios: (happy) load Ccxt, call _suffix_to_methods for L1OrderBook and L2OrderBook, verify tuples returned. (regression) Call for "Ticker" and verify existing tuple unchanged. Evidence: `.omo/evidence/fix-watcher-bugs/task1-suffix-methods.txt`
  Commit: Y | `fix(Ccxt): Add L1OrderBook/L2OrderBook to _suffix_to_methods`

- [x] 2. Fix `@py` no-op macro hygiene
  What to do / Must NOT do: Change `macro py(expr); expr; end` to `macro py(expr); esc(expr); end` in `Watchers/src/impls/impls.jl`. Must NOT affect other macro definitions in the file. Must NOT change behavior for any other `@py` usage in the codebase (since `esc()` is the correct way to preserve caller scope).
  Parallelization: Wave 1 | Blocked by: none | Blocks: 6, 7
  References: `/Planar.jl/Watchers/src/impls/impls.jl:24-26`, `/Planar.jl/Watchers/src/impls/ccxt_ohlcv_candles.jl:212`
  Acceptance criteria: `julia --project=Watchers -e 'using Watchers.WatchersImpls; ex = Watchers.WatchersImpls.@py([sym, tf_str]); println(ex)'` — should compile without UndefVarError
  QA scenarios: (happy) Load WatchersImpls module. (regression) Run existing Watchers test suite. Evidence: `.omo/evidence/fix-watcher-bugs/task2-py-macro.txt`
  Commit: Y | `fix(Watchers): Fix @py stub macro hygiene with esc()`

- [ ] 3. Fix `buffer_capacity=0` in ccxt_average_ohlcv_watcher
  What to do / Must NOT do: Change `buffer_capacity=0` to `buffer_capacity=1` on line 129 of `ccxt_average_ohlcv_watcher.jl`. Must NOT change any other line. The comment "Average watcher does not buffer" is correct but capacity=1 is the minimum valid value for CircularBuffer.
  Parallelization: Wave 1 | Blocked by: none | Blocks: 6, 7
  References: `/Planar.jl/Watchers/src/impls/ccxt_average_ohlcv_watcher.jl:129`
  Acceptance criteria: `julia --project=Watchers -e 'using Watchers; using Watchers.Fetch.Exchanges: getexchange!; e = getexchange!(:binance; markets=:yes, cache=false, sandbox=false); using Watchers.WatchersImpls: ccxt_average_ohlcv_watcher; w = ccxt_average_ohlcv_watcher([e], ["BTC/USDT"]; timeframe=tf"1m", input_source=:tickers)'` — should NOT throw ArgumentError
  QA scenarios: (happy) Create watcher successfully. (regression) Verify watcher creation with other watchers still works. Evidence: `.omo/evidence/fix-watcher-bugs/task3-buffer-capacity.txt`
  Commit: Y | `fix(Watchers): Fix buffer_capacity=0 → 1 in ccxt_average_ohlcv_watcher`

- [ ] 4. Fix CoinGecko ticker parsing for null Float64 fields
  What to do / Must NOT do: Fix the `fromdict` generated function in `Lang/src/module.jl` to handle `Union{Nothing, T}` fields by using `get(di, key, nothing)` instead of direct indexing, or alternatively pre-process the CoinGecko API response in `cg_ticker.jl` to replace `nothing` with `0.0` for numeric fields. The fix must handle the case where the CoinGecko API returns `null` for fields like `fully_diluted_valuation` that are declared as `Option{Float64}` (= `Union{Nothing, Float64}`) in the `CgTick` NamedTuple.
  
  **Approach (recommended)**: Modify `fromdict` to use `get(di, key, nothing)` with fallback to `nothing` for missing keys, and skip `convert` for `Union{Nothing, T}` fields where the value is `nothing`. This is the generic fix that handles all `Option{T}` fields across the codebase.
  
  Alternative: Pre-process in `cg_ticker.jl` `_fetch!` — replace `nothing` with `0.0` for each market dict before calling `@parsedata`.
  
  Must NOT change the CgTick NamedTuple definition (it's correct as `Option{Float64}`).
  
  Parallelization: Wave 1 | Blocked by: none | Blocks: 6, 7
  References: `/Planar.jl/Watchers/src/impls/cg_ticker.jl:41-58`, `/Planar.jl/Lang/src/module.jl:139-149`
  Acceptance criteria: `julia --project=Watchers -e 'using Watchers.WatchersImpls: cg_ticker_watcher; w = cg_ticker_watcher(["BTC", "ETH"]; interval=Second(360)); Watchers.fetch!(w)'` — should succeed without MethodError(convert, (Float64, nothing))
  QA scenarios: (happy) Fetch CoinGecko ticker data without error. (failure) If CoinGecko API is unavailable, handle gracefully. Evidence: `.omo/evidence/fix-watcher-bugs/task4-cg-ticker.txt`
  Commit: Y | `fix(Watchers): Handle null Float64 fields in CoinGecko ticker parsing`

- [ ] 5. Fix CoinPaprika markets parsing for Symbol keys
  What to do / Must NOT do: In `cp_markets.jl` `_fetch!`, convert Symbol keys in the CoinPaprika API response dict to String keys before calling `fromdict`. Add a helper `_stringify_keys(dict)` that converts all keys to strings.
  
  Alternative: Modify `fromdict` to handle Symbol keys generically in the `kconvfunc` path.
  
  Must NOT change the `CpTick` NamedTuple or the CoinPaprika API wrapper.
  
  Parallelization: Wave 1 | Blocked by: none | Blocks: 6, 7
  References: `/Planar.jl/Watchers/src/impls/cp_markets.jl:24-36`
  Acceptance criteria: `julia --project=Watchers -e 'using Watchers.WatchersImpls: cp_markets_watcher; w = cp_markets_watcher("binance", Minute(3)); Watchers.fetch!(w)'` — should succeed without TypeError(Symbol, ...)
  QA scenarios: (happy) Fetch CoinPaprika markets data without error. (failure) If CoinPaprika API is unavailable, handle gracefully. Evidence: `.omo/evidence/fix-watcher-bugs/task5-cp-markets.txt`
  Commit: Y | `fix(Watchers): Handle Symbol dict keys in CoinPaprika markets parsing`

- [ ] 6. Run unit tests after all fixes
  What to do: Run the complete test suites for Watchers, Ccxt, and Lang packages to ensure no regressions from the 5 fixes.
  Parallelization: Wave 2 | Blocked by: 1, 2, 3, 4, 5 | Blocks: 7
  References: `/Planar.jl/Watchers/test/runtests.jl`, `/Planar.jl/Ccxt/test/runtests.jl`
  Acceptance criteria: All existing tests pass (155 Watchers tests, Ccxt tests, Lang tests). Record pass/fail counts.
  QA scenarios: Run `julia --project=Watchers -e 'using Pkg; Pkg.test()'`, `julia --project=Ccxt -e 'using Pkg; Pkg.test()'`. Evidence: `.omo/evidence/fix-watcher-bugs/task6-unit-tests.txt`
  Commit: N (part of commit strategy grouping)

- [ ] 7. End-to-end validation of all fixed watchers
  What to do / Must NOT do: Run each example file against real CcxtGateway (Binance) or live API (CoinGecko, CoinPaprika). Verify for each watcher: (a) buffer populates, (b) no errors in `w._exec.errors`, (c) view populates correctly. Must NOT require human intervention.
  
  Watchers to validate:
  - 01_tickers.jl (ccxt_tickers_watcher) — already verified working, regression check
  - 02_ohlcv_trades.jl (ccxt_ohlcv_watcher) — already verified working, regression check
  - 03_ohlcv_candles.jl (ccxt_ohlcv_candles_watcher) — was broken by @py macro bug (#2)
  - 04_ohlcv_tickers.jl (ccxt_ohlcv_tickers_watcher) — not tested before, baseline + fix check
  - 05_orderbook.jl (ccxt_orderbook_watcher) — was broken by _suffix_to_methods bug (#1)
  - 06_average_ohlcv.jl (ccxt_average_ohlcv_watcher) — was broken by buffer_capacity bug (#3)
  - 07_cg_ticker.jl (cg_ticker_watcher) — was broken by parsing bug (#4)
  - 08_cg_derivatives.jl (cg_derivatives_watcher) — regression check
  - 09_cp_markets.jl (cp_markets_watcher) — was broken by parsing bug (#5)
  - 10_cp_twitter.jl (cp_twitter_watcher) — regression check
  
  Parallelization: Wave 3 | Blocked by: 6 | Blocks: Final verification
  References: Each example file in `/Planar.jl/examples/watchers/`
  Acceptance criteria: All 10 watchers produce output (buffer, view) without errors. Record results per watcher.
  QA scenarios: Run each example with appropriate timeout. Evidence: `.omo/evidence/fix-watcher-bugs/task7-e2e-validation.txt`
  Commit: N (part of commit strategy grouping)

## Final verification wave
> Runs in parallel after ALL todos. ALL must APPROVE. Surface results and wait for the user's explicit okay before declaring complete.
- [ ] F1. Plan compliance audit — verify only planned files were changed, no scope creep
- [ ] F2. Code quality review — verify changes are minimal and correct
- [ ] F3. Real manual QA — verify the watchers work end-to-end by running example files
- [ ] F4. Scope fidelity — verify Must NOT have items were respected

## Commit strategy
- **Commit 1**: `fix(Ccxt): Add L1OrderBook/L2OrderBook to _suffix_to_methods` (todo 1)
- **Commit 2**: `fix(Watchers): Fix @py stub macro hygiene with esc()` (todo 2)
- **Commit 3**: `fix(Watchers): Fix buffer_capacity=0 → 1 in ccxt_average_ohlcv_watcher` (todo 3)
- **Commit 4**: Combined fix for CoinGecko and CoinPaprika parsing (todos 4, 5)
- Total: 4 atomic commits

## Success criteria
1. All 3 CCXT watchers that failed during validation now work end-to-end against real CcxtGateway
2. All existing unit tests (155 Watchers + Ccxt + Lang) pass with no regressions
3. CoinGecko and CoinPaprika watchers can parse API responses without type conversion errors
4. Each commit is atomic, surgical, and only touches the affected function
