---
category: "getting-started"
difficulty: "advanced"
topics: [execution-modes, margin-trading, exchanges, data-management, optimization, getting-started, strategy-development, troubleshooting, visualization, configuration]
last_updated: "2025-10-04"---
---

# Running in Live Mode

A [exchange](../[exchanges](../exchanges.md) API defined by the [strategy](../guides/strategy-development.md). This mode executes real trades with actual capital, so proper [configuration](../config.md) and risk management are critical.

## Initial Setup and Configuration

To construct the [strategy](../guides/strategy-development.md), use the same methods as in [paper mode](paper.md), but with additional security considerations:


### API Configuration and Security

#### Exchange API Setup


#### Security Best Practices


### Comprehensive Live Trading Setup

#### Basic Live Trading Configuration


#### Advanced Multi-Asset Live Setup


## How Live Mode Works

When you start live mode, `call!` functions are forwarded to the exchange API to fulfill the request. We set up background tasks to ensure events update the local state in a timely manner. Specifically, we run:

- A `Watcher` to monitor the balance. This runs in both spot (`NoMarginStrategy`) and derivatives (`MarginStrategy`). In the case of spot, the balance updates both the cash of the strategy's main currency and all the currencies in the strategy universe. For derivatives, it is used only to update the main currency.
- A `Watcher` to monitor positions when margin is used (`MarginStrategy`). The number of contracts of the open position represents the cash of the long/short `Position` in the `AssetInstance` (`MarginInstance`). This means that *non-zero balances* of a currency other than the strategy's main currency *won't be considered*.
- A long-running task that monitors all the order events of an asset. The task starts when a new order is requested and stops if there haven't been orders open for a while for the subject asset.
- A long-running task that monitors all trade events of an asset. This task starts and stops along with the order background task.

Similar to other modes, the return value of a `call!` function for creating an order will be:

- A `Trade` if a trade event was observed shortly after the order creation.
- `missing` if the order was successfully created but not immediately executed.
- `nothing` if the order failed to be created, either because of local checks (e.g., not enough cash) or some other exchange error (e.g., API timeout).

### Background Task Management

#### Watcher Configuration


#### Custom Watchers


### Order Execution and State Management

#### Order State Tracking


### Risk Management and Monitoring

#### Real-Time Risk Monitoring


#### Emergency Procedures


## Timeouts and API Management

If you don't want to wait for the order processing, you can pass a custom `waitfor` parameter which limits the amount of time we wait for API responses.

The `synced=true` flag is a last-ditch attempt that _force fetches_ updates from the exchange if no new events have been observed by the background tasks after the waiting period expires (default is `true`).

The local trades history might diverge from the data sourced from the exchange because not all exchanges support endpoints for fetching trades history or events, therefore trades are emulated from diffing order updates.

The local state is *not persisted*. Nothing is saved or loaded from storage. Instead, we sync the most recent history of orders with their respective trades when the strategy starts running. (This behavior might change in the future if need arises.)

### Advanced Timeout Configuration


### API Rate Limiting and Management


### Connection Management and Resilience


### Logging and Alerting



## See Also

- **[Exchanges](../exchanges.md)** - Exchange integration and configuration
- **[Config](../config.md)** - Exchange integration and configuration
- **[Overview](../troubleshooting/index.md)** - Troubleshooting: Troubleshooting and problem resolution
- **[Optimization](../optimization.md)** - Performance optimization techniques
- **[Performance Issues](../troubleshooting/performance-issues.md)** - Troubleshooting: Performance optimization techniques
- **[Data Management](../guides/data-management.md)** - Guide: Data handling and management

## Event Tracing

During live execution events are recorded and flushed to storage (based on the active `ZarrInstance`).
The `EventTrace` can be accessed from an `Exchange` object. When an `Exchange` object is initialized, it creates an `EventTrace` object to store events related to that exchange.

```julia
# Activate Planar project
import Pkg
Pkg.activate("Planar")

try
    using Planar
    @environment!
    
    # Example: Access the event trace from an exchange object
    # Note: This requires proper exchange configuration
    
    println("Example event trace access:")
    println("exc = getexchange!(:binance)")
    println("et = exc._trace")
    
    # Real usage would be:
    # exc = getexchange!(:binance)  # Requires exchange configuration
    # et = exc._trace
    
    println("Event trace object would be available as 'et'")
    
catch e
    @warn "Planar not available: $e"
end
```

### Advanced Event Tracing

#### Comprehensive Event Logging


#### Replaying Events

To replay events in a local [simulation](../guides/execution-modes.md#simulation-mode), use the `replay_from_trace!` function:


This function will reconstruct the state of the strategy based on the events recorded in the trace.

#### Advanced Event Analysis


#### Extracting Events

To extract a subset of events or the last `n` events, use the `trace_tail` function:


#### Event-Based Strategy Optimization

