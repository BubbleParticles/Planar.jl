# watchers-endtoend-validation - Work Plan

## TL;DR (For humans)

**What you'll get:** A complete validation report for all 10 watcher examples in `examples/watchers/`. Each watcher will be started, run for 3-4 timeframes, and verified for: buffer population, no errors in `w._exec.errors`, view population, and clean stdout/stderr. Results documented as PASS/FAIL/SKIP with details.

**Why this approach:** The user specified exact verification steps. Running the actual example files against a real CcxtGateway (binance) or stub exchange is the only way to verify end-to-end behavior including gateway integration, data flow through the watcher pipeline, and real-world timing.

**What it will NOT do:** Fix bugs found during validation (separate task), modify watcher implementations, run unit tests with mocks, or test watchers not in the examples directory.

**Effort:** Medium (~90 min total runtime + ~30 min setup/analysis)

**Risk:** Medium - depends on CcxtGateway availability and exchange API reliability. Network issues or rate limits may cause false negatives.

**Decisions to sanity-check:**
1. Use real binance exchange (not stub) - stub has no market data for some watchers
2. Run sequentially (not parallel) - avoids gateway rate limits
3. Accept SKIP if gateway unavailable - environmental constraint

Your next move: **Approve to begin validation run**.

---

> TL;DR (machine): Medium effort, Medium risk, 10 watchers validated end-to-end with real gateway

## Scope
### Must have
- Run all 10 example files in `examples/watchers/`
- For each: include file → start!(w) → wait 3-4 timeframes → verify buffer/view/errors → stop!(w)
- Automated verification script that checks all 8 criteria programmatically
- Results summary table with PASS/FAIL/SKIP per watcher
- Evidence logs per watcher

### Must NOT have (guardrails, anti-slop, scope boundaries)
- No modifications to watcher source code
- No modifications to example files
- No unit tests (separate plan)
- No parallel execution of multiple watchers
- No mocking - real gateway only

## Verification strategy
> Zero human intervention - all verification is agent-executed.
- Test decision: integration test (none) + framework (bash+julia script)
- Evidence: .omo/evidence/task-<N>-watchers-endtoend-validation.log

## Execution strategy
### Parallel execution waves
> Target 5-8 todos per wave. Fewer than 3 (except the final) means you under-split.

**Wave 1 (Setup):** Task 1-2 (environment setup, verification script)
**Wave 2 (Execution):** Task 3-12 (one per watcher, sequential)
**Wave 3 (Summary):** Task 13 (results compilation)

### Dependency matrix
| Todo | Depends on | Blocks | Can parallelize with |
| --- | --- | --- | --- |
| 1. Setup env & gateway check | - | 2 | - |
| 2. Create verification script | 1 | 3-12 | - |
| 3. Test 01_tickers | 2 | 13 | (sequential) |
| 4. Test 02_ohlcv_trades | 2 | 13 | (sequential) |
| 5. Test 03_ohlcv_candles | 2 | 13 | (sequential) |
| 6. Test 04_ohlcv_tickers | 2 | 13 | (sequential) |
| 7. Test 05_orderbook | 2 | 13 | (sequential) |
| 8. Test 06_average_ohlcv | 2 | 13 | (sequential) |
| 9. Test 07_cg_ticker | 2 | 13 | (sequential) |
| 10. Test 08_cg_derivatives | 2 | 13 | (sequential) |
| 11. Test 09_cp_markets | 2 | 13 | (sequential) |
| 12. Test 10_cp_twitter | 2 | 13 | (sequential) |
| 13. Compile results | 3-12 | - | - |

## Todos
> Implementation + Test = ONE todo. Never separate.
<!-- APPEND TASK BATCHES BELOW THIS LINE WITH edit/apply_patch - never rewrite the headers above. -->
- [ ] 1. Setup environment and verify CcxtGateway availability
  What to do / Must NOT do: Source .envrc, check if CcxtGateway is running on localhost:8999, check binance connectivity. Do NOT start gateway if not running - document as SKIP.
  Parallelization: Wave 1 | Blocked by: - | Blocks: 2
  References (executor has NO interview context - be exhaustive): .envrc:1-30, examples/watchers/01_tickers.jl:15-24
  Acceptance criteria (agent-executable): `CcxtGateway.ping()` returns true OR documented SKIP with reason
  QA scenarios: happy (gateway up, ping succeeds), failure (gateway down, ping fails → SKIP all)
  Evidence: .omo/evidence/task-1-watchers-endtoend-validation.log
  Commit: N | setup: verify gateway

- [ ] 2. Create automated verification script
  What to do / Must NOT do: Write Julia script that includes example, calls start!(w), waits appropriate time, checks buffer/view/errors, calls stop!(w), outputs structured result. Must handle all 10 watcher types with their specific timeframes.
  Parallelization: Wave 1 | Blocked by: 1 | Blocks: 3-12
  References (executor has NO interview context - be exhaustive): examples/watchers/*.jl, Watchers/src/functions.jl:218-226, Watchers/src/module.jl:123-152
  Acceptance criteria (agent-executable): Script runs and outputs JSON/structured result per watcher
  QA scenarios: happy (script works for all examples), failure (handles missing gateway gracefully)
  Evidence: .omo/evidence/task-2-watchers-endtoend-validation.log
  Commit: N | test: create verification script

- [ ] 3. Validate 01_tickers (ccxt_tickers_watcher)
  What to do / Must NOT do: Run `julia --project=Watchers examples/watchers/01_tickers.jl` with verification. Watcher uses interval=Second(5), syms=["BTC/USDT","ETH/USDT"]. Wait ~20 sec for 4+ fetches. Verify: buffer populated, no errors, view populated (Dict{String,CcxtTicker}), no stdout warnings.
  Parallelization: Wave 2 | Blocked by: 2 | Blocks: 13
  References (executor has NO interview context - be exhaustive): examples/watchers/01_tickers.jl:1-59
  Acceptance criteria (agent-executable): Buffer length > 0, isempty(w._exec.errors), w.view has keys for BTC/USDT and ETH/USDT, no ERROR/WARN to stdout
  QA scenarios: happy (all checks pass), failure (gateway error, empty buffer, view empty)
  Evidence: .omo/evidence/task-3-watchers-endtoend-validation.log
  Commit: N | validation: 01_tickers

- [ ] 4. Validate 02_ohlcv_trades (ccxt_ohlcv_watcher)
  What to do / Must NOT do: Run example with verification. Uses timeframe=tf"1m", interval=Second(5). Wait 4 minutes for 4+ timeframes. Known issue: stub has no markets - use real gateway. Verify buffer (Vector{CcxtTrade}), no errors, view populated.
  Parallelization: Wave 2 | Blocked by: 2 | Blocks: 13
  References (executor has NO interview context - be exhaustive): examples/watchers/02_ohlcv_trades.jl:1-64
  Acceptance criteria (agent-executable): Buffer length > 0 after 4 min, isempty(w._exec.errors), view populated, no ERROR/WARN
  QA scenarios: happy (trades flow, OHLCV builds), failure (market data missing, gateway error)
  Evidence: .omo/evidence/task-4-watchers-endtoend-validation.log
  Commit: N | validation: 02_ohlcv_trades

- [ ] 5. Validate 03_ohlcv_candles (ccxt_ohlcv_candles_watcher)
  What to do / Must NOT do: Run example with verification. Uses timeframe=tf"1m", syms=["BTC/USDT","ETH/USDT","SOL/USDT"], n_jobs=4. Wait 4 minutes. Verify buffer populated, no errors, view is Dict{String,DataFrame} with 3 symbols, each DataFrame has rows.
  Parallelization: Wave 2 | Blocked by: 2 | Blocks: 13
  References (executor has NO interview context - be exhaustive): examples/watchers/03_ohlcv_candles.jl:1-55
  Acceptance criteria (agent-executable): Buffer length > 0, isempty(w._exec.errors), view has 3 keys, each nrow >= 1
  QA scenarios: happy (candles fetch), failure (WS not supported, gateway error)
  Evidence: .omo/evidence/task-5-watchers-endtoend-validation.log
  Commit: N | validation: 03_ohlcv_candles

- [ ] 6. Validate 04_ohlcv_tickers (ccxt_ohlcv_tickers_watcher)
  What to do / Must NOT do: Run example with verification. Uses timeframe=tf"5m", price_source=:last, n_jobs=4. Wait 20 minutes (4x 5m timeframes). Verify buffer, no errors, view populated.
  Parallelization: Wave 2 | Blocked by: 2 | Blocks: 13
  References (executor has NO interview context - be exhaustive): examples/watchers/04_ohlcv_tickers.jl:1-59
  Acceptance criteria (agent-executable): Buffer length > 0 after 20 min, isempty(w._exec.errors), view populated
  QA scenarios: happy (tickers build OHLCV), failure (long wait, gateway timeout)
  Evidence: .omo/evidence/task-6-watchers-endtoend-validation.log
  Commit: N | validation: 04_ohlcv_tickers

- [ ] 7. Validate 05_orderbook (ccxt_orderbook_watcher)
  What to do / Must NOT do: Run example with verification. Uses level=1 (L1), interval=Second(1), sym="BTC/USDT". Wait ~10 sec. Note: example auto-starts (no start=false). Verify buffer, no errors, view is DataFrame with bid/ask columns.
  Parallelization: Wave 2 | Blocked by: 2 | Blocks: 13
  References (executor has NO interview context - be exhaustive): examples/watchers/05_orderbook.jl:1-55
  Acceptance criteria (agent-executable): Buffer length > 0, isempty(w._exec.errors), view is DataFrame with bid_price, bid_amount, ask_price, ask_amount
  QA scenarios: happy (orderbook snapshots), failure (L1 not supported, gateway error)
  Evidence: .omo/evidence/task-7-watchers-endtoend-validation.log
  Commit: N | validation: 05_orderbook

- [ ] 8. Validate 06_average_ohlcv (ccxt_average_ohlcv_watcher)
  What to do / Must NOT do: Run example with verification. Uses exchanges=[binance,bybit], syms=["BTC/USDT","ETH/USDT"], timeframe=tf"1m", input_source=:tickers, n_jobs=4. Wait 4 minutes. Verify buffer, no errors, view is Dict{String,DataFrame} with aggregated data.
  Parallelization: Wave 2 | Blocked by: 2 | Blocks: 13
  References (executor has NO interview context - be exhaustive): examples/watchers/06_average_ohlcv.jl:1-65
  Acceptance criteria (agent-executable): Buffer length > 0, isempty(w._exec.errors), view has 2 keys with aggregated OHLCV
  QA scenarios: happy (multi-exchange aggregation), failure (bybit unavailable, gateway error)
  Evidence: .omo/evidence/task-8-watchers-endtoend-validation.log
  Commit: N | validation: 06_average_ohlcv

- [ ] 9. Validate 07_cg_ticker (cg_ticker_watcher)
  What to do / Must NOT do: Run example with verification. Uses syms=["BTC","ETH"], interval=Minute(5). Wait 20 minutes. No CcxtGateway needed (CoinGecko API). Verify buffer, no errors, view is NamedTuple with CgTick fields.
  Parallelization: Wave 2 | Blocked by: 2 | Blocks: 13
  References (executor has NO interview context - be exhaustive): examples/watchers/07_cg_ticker.jl:1-32
  Acceptance criteria (agent-executable): Buffer length > 0, isempty(w._exec.errors), view has :BTC and :ETH keys with CgTick data
  QA scenarios: happy (CoinGecko API works), failure (network/API rate limit)
  Evidence: .omo/evidence/task-9-watchers-endtoend-validation.log
  Commit: N | validation: 07_cg_ticker

- [ ] 10. Validate 08_cg_derivatives (cg_derivatives_watcher)
  What to do / Must NOT do: Run example with verification. Uses exc_name="binance_futures". Wait ~5 min (unknown interval). No CcxtGateway needed. Verify buffer, no errors, view is Dict{Derivative,CgSymDerivative}.
  Parallelization: Wave 2 | Blocked by: 2 | Blocks: 13
  References (executor has NO interview context - be exhaustive): examples/watchers/08_cg_derivatives.jl:1-30
  Acceptance criteria (agent-executable): Buffer length > 0, isempty(w._exec.errors), view populated with derivatives data
  QA scenarios: happy (derivatives fetch), failure (API/network issue)
  Evidence: .omo/evidence/task-10-watchers-endtoend-validation.log
  Commit: N | validation: 08_cg_derivatives

- [ ] 11. Validate 09_cp_markets (cp_markets_watcher)
  What to do / Must NOT do: Run example with verification. Uses exc_name="binance", interval=Minute(3) (positional arg). Wait 12 minutes. No CcxtGateway needed (CoinPaprika API). Verify buffer, no errors, view is Dict{String,CpTick}.
  Parallelization: Wave 2 | Blocked by: 2 | Blocks: 13
  References (executor has NO interview context - be exhaustive): examples/watchers/09_cp_markets.jl:1-31
  Acceptance criteria (agent-executable): Buffer length > 0, isempty(w._exec.errors), view populated with market data
  QA scenarios: happy (markets fetch), failure (API/network issue)
  Evidence: .omo/evidence/task-11-watchers-endtoend-validation.log
  Commit: N | validation: 09_cp_markets

- [ ] 12. Validate 10_cp_twitter (cp_twitter_watcher)
  What to do / Must NOT do: Run example with verification. Uses syms=["BTC","ETH"], interval=Minute(5) (positional). Wait 20 minutes. No CcxtGateway needed. Verify buffer, no errors, view is Dict{String,Vector{CpTweet}} (different pattern - no DataFrame).
  Parallelization: Wave 2 | Blocked by: 2 | Blocks: 13
  References (executor has NO interview context - be exhaustive): examples/watchers/10_cp_twitter.jl:1-31
  Acceptance criteria (agent-executable): Buffer length > 0, isempty(w._exec.errors), view populated with tweets data
  QA scenarios: happy (tweets fetch), failure (API/network issue, no tweets available)
  Evidence: .omo/evidence/task-12-watchers-endtoend-validation.log
  Commit: N | validation: 10_cp_twitter

- [ ] 13. Compile and present validation results summary
  What to do / Must NOT do: Collect all task results, create summary table with PASS/FAIL/SKIP per watcher, include timing, buffer sizes, error counts, view details. Save to .omo/evidence/validation-summary.md
  Parallelization: Wave 3 | Blocked by: 3-12 | Blocks: -
  References (executor has NO interview context - be exhaustive): .omo/evidence/task-*-watchers-endtoend-validation.log
  Acceptance criteria (agent-executable): Summary markdown file exists with all 10 watchers results
  QA scenarios: happy (all complete), failure (some skipped/failed)
  Evidence: .omo/evidence/validation-summary.md
  Commit: N | docs: validation summary

## Final verification wave
> Runs in parallel after ALL todos. ALL must APPROVE. Surface results and wait for the user's explicit okay before declaring complete.
- [ ] F1. Plan compliance audit
- [ ] F2. Code quality review
- [ ] F3. Real manual QA
- [ ] F4. Scope fidelity

## Commit strategy
No commits - this is a validation run producing evidence files, not code changes.

## Success criteria
- All 10 watchers attempted (PASS/FAIL/SKIP documented)
- Verification script works and produces structured output
- Summary report generated with evidence
- No false positives (manual spot-check of 2+ watchers confirms automated results)