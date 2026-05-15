"""
    Ccxt

Thin Julia wrapper around [ccxt-gateway](https://github.com/bukiped/gulimpub#ccxt-gateway) for
accessing 100+ cryptocurrency exchanges via the [CCXT](https://github.com/ccxt/ccxt) library.

## Architecture

This package provides low-level HTTP/WebSocket communication with the gateway.
Specific CCXT methods (e.g., `fetch_ohlcv`, `fetch_trades`, `fetch_funding_rate`) should be
implemented in downstream packages that depend on Ccxt, not in this package.

## Core Components

- `CcxtGateway.GatewayClient` - HTTP client for gateway communication
- `CcxtGateway.ping`, `CcxtGateway.start_exchange`, `CcxtGateway.stop_exchange` - gateway management
- `CcxtGateway.call_exchange` - generic CCXT method caller
- `CcxtGateway.list_exchanges`, `CcxtGateway.exchange_info` - exchange state queries

## Usage

```julia
using Ccxt.CcxtGateway

client = GatewayClient(; use_ssl=true)
ping(client)  # returns true if gateway is running

start_exchange(client, "binance")
ticker = call_exchange(client, "binance", "fetch_ticker", query=Dict("symbol" => "BTC/USDT"))
stop_exchange(client, "binance")
```

## Python Extension

Python/ccxt bindings are optional and loaded only when `Python` is available.
See `Ccxt/ext/CcxtPythonExt.jl` for details.
"""
module Ccxt

if get(ENV, "JULIA_NOPRECOMP", "") == "all"
    __init__() = begin
        include(joinpath(@__DIR__, "module.jl"))
        @eval _doinit()
    end
else
    occursin(string(@__MODULE__), get(ENV, "JULIA_NOPRECOMP", "")) && __precompile__(false)
    include("module.jl")
    __init__() = _doinit()
    include("precompile.jl")
end

end # module Ccxt