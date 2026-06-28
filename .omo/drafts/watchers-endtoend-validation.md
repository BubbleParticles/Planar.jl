---
slug: watchers-endtoend-validation
status: drafting
intent: CLEAR
pending-action: write .omo/plans/watchers-endtoend-validation.md
approach: Run each watcher example file from examples/watchers/, start the watcher, wait for data, verify buffer/view/errors, document results. Uses real gateway or stub exchange.
---

# Draft: watchers-endtoend-validation

## Components (topology ledger)
| id | outcome (one line) | status | evidence path |
|----|-------------------|--------|---------------|
| 01_tickers | CCXT ticker watcher (REST) | pending | examples/watchers/01_tickers.jl |
| 02_ohlcv_trades | CCXT OHLCV from trades watcher | pending | examples/watchers/02_ohlcv_trades.jl |
| 03_ohlcv_candles | CCXT OHLCV candles watcher (WS) | pending | examples/watchers/03_ohlcv_candles.jl |
| 04_ohlcv_tickers | CCXT OHLCV from tickers watcher | pending | examples/watchers/04_ohlcv_tickers.jl |
| 05_orderbook | CCXT orderbook watcher (L1/L2/L3) | pending | examples/watchers/05_orderbook.jl |
| 06_average_ohlcv | Aggregated OHLCV across exchanges | pending | examples/watchers/06_average_ohlcv.jl |
| 07_cg_ticker | CoinGecko ticker watcher | pending | examples/watchers/07_cg_ticker.jl |
| 08_cg_derivatives | CoinGecko derivatives watcher | pending | examples/watchers/08_cg_derivatives.jl |
| 09_cp_markets | CoinPaprika markets watcher | pending | examples/watchers/09_cp_markets.jl |
| 10_cp_twitter | CoinPaprika twitter watcher | pending | examples/watchers/10_cp_twitter.jl |

## Open assumptions (announced defaults)
| assumption | adopted default | rationale | reversible? |
|------------|----------------|-----------|-------------|
| Exchange data source | Use CcxtGateway with binance (real) or PLANAR_USE_STUB_CCXT=1 | Real data best for validation; stub for CI | Yes |
| Timeframe | 1m for ccxt watchers → wait 4 min minimum | Per user spec: 3-4 timeframes | No |
| Timeout per watcher | 5 min (4 min wait + buffer) | Covers 4 timeframes at 1m | Yes |
| Gateway availability | Must have CcxtGateway running on localhost:8999 | Examples require it | N/A |
| Verification automation | bash script launching julia per example | Simple, reproducible | Yes |

## Findings (cited - path:lines)
### Example files structure
- Each example creates a watcher `w` with `start=false`
- Each uses `ccxt_tickers_watcher`, `ccxt_ohlcv_watcher`, etc.
- All require CcxtGateway (Exchange("binance"))
- 02_ohlcv_trades has known issue: "needs exchange markets loaded (stub has none)"

### Watcher verification requirements (from user)
1. Run julia including example file
2. start!(w) after inclusion
3. Ensure no errors during startup
4. Wait until at least 3-4 timeframes (if 1m, wait 4 minutes)
5. Ensure w.buffer is populated
6. Ensure no errors in w._exec.errors
7. Ensure w.view is populated
8. Ensure no warning/error messages to stdout

### Time requirements per watcher
- ccxt_tickers: interval=Second(5) → need ~15-20 sec
- ccxt_ohlcv_watcher: interval=Second(5), timeframe=1m → need 4 min
- ccxt_ohlcv_candles: timeframe=1m, n_jobs=4 → need 4 min
- ccxt_ohlcv_tickers: timeframe=5m → need 20 min
- ccxt_orderbook: interval=Second(1) → need ~10 sec
- ccxt_average_ohlcv: timeframe=1m → need 4 min
- cg_ticker: interval=Minute(5) → need 20 min
- cg_derivatives: unknown interval → assume 5 min
- cp_markets: interval=Minute(3) → need 12 min
- cp_twitter: interval=Minute(5) → need 20 min

## Decisions (with rationale)
1. Test sequentially, not in parallel - avoids gateway rate limits and resource contention
2. Use CcxtGateway with real binance (not stub) for meaningful data - stub has no markets
3. Set JULIA_NUM_THREADS appropriately (from .envrc: nproc-2)
4. Source .envrc before running tests
5. Create automated verification script to check all criteria programmatically
6. Document results per watcher (PASS/FAIL with details)
7. Total estimated time: ~90 minutes for all 10 watchers
8. If gateway unavailable, document as SKIPPED with reason

## Scope IN
- All 10 watcher example files in examples/watchers/
- Automated verification of buffer, view, errors
- Real gateway or stub exchange
- Results documentation

## Scope OUT (Must NOT have)
- Modifying watcher implementations (separate audit plan)
- Fixing bugs found (separate fix plan)
- Unit tests with mocks (separate watcher-verification plan)
- Changes to example files

## Open questions
- What if gateway is not running? (Default: skip with clear message)
- What if binance has rate limits? (Default: accept as environmental constraint)
- Should we test with specific timeframe per watcher or use defaults? (Use defaults from examples)

## Approval gate
status: awaiting-approval