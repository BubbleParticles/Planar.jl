# Strategy Monitoring

Monitoring keeps a strategy healthy across all [execution modes](execution-modes.md). Planar's live infrastructure runs background watchers and tasks that keep local state in sync with the exchange; monitoring is about watching those watchers and reacting when they degrade.

## Watchers

A `Watcher` is an interface over a data feed — OHLCV candles, trades, order books, balances, or positions. Watchers fetch at fixed intervals, process the raw data into a view (usually a `DataFrame`), and optionally flush to storage.

Key functions (full reference in [Watchers](../watchers/watchers.md)):

| Function | Purpose |
|----------|---------|
| `get` | Retrieve the processed view (e.g. a `DataFrame`) |
| `length` | Number of elements in the buffer |
| `last` | Most recent raw buffer value |
| `isstale` | Whether the watcher is degraded (can't fetch new data) |
| `fetch!` | Force an immediate data fetch |
| `flush!` | Force a buffer flush to storage |
| `delete!` / `deleteat!` | Delete watcher data, optionally within a date range |
| `push!` / `pop!` | Add or remove tracked elements (e.g. symbols) |
| `stop` / `start` | Stop and restart the watcher |

### Detecting Stale Watchers

`isstale` is the primary health signal. A watcher that reports stale for several consecutive intervals is likely disconnected from its [exchange](../exchanges.md) or third-party API — check connectivity, rate limits, and API credentials. See [Troubleshooting](../troubleshooting/index.md) for common causes.

## Live Mode Background Tasks

In [live mode](../engine/live.md), the following background tasks keep local state current and are worth monitoring:

- **Balance watcher** - Tracks account balances. In spot trading it updates the strategy's main currency cash and all universe currencies; in derivatives it updates only the main currency.
- **Positions watcher** - Active when margin is used. The contract counts of open positions represent the cash of the long/short `Position` in the `AssetInstance`.
- **Order-event task** - Monitors order events for an asset; starts when an order is placed and stops after a period with no open orders.
- **Trade-event task** - Monitors trade events for an asset; starts and stops with the order-event task.

If an order is placed but no trade event is observed, the order `call!` returns `missing` (created but not yet executed). A persistent absence of events — with the `synced=true` fallback force-fetching updates — suggests the background tasks have stalled.

## Monitoring in Simulation and Paper

- **Simulation**: no background tasks run; the backtest loop is the only consumer of data.
- **Paper**: watchers run against live market data, so treat paper mode as a dry run of the live monitoring setup, including spread and latency checks (see [Paper Mode](execution-modes.md#Paper-Mode)).

## Alerts

Define alert conditions on the signals above:

- `isstale` on any watcher for more than N consecutive intervals
- Balance watcher reporting unexpected currency balances
- No order events within the expected window after order placement

## See Also

- **[Watchers](../watchers/watchers.md)** - Watcher API and implementation interface
- **[Live Trading](../engine/live.md)** - Background tasks in live mode
- **[Execution Modes](execution-modes.md)** - Mode-specific behavior
- **[Data Management](data-management.md)** - Data collection watchers
