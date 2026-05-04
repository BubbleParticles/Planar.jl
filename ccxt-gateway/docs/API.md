# ccxt-gateway API Documentation

ccxt-gateway is a high-performance self-hosted Python server that exposes REST and WebSocket APIs for 100+ cryptocurrency exchanges via CCXT, with a multi-process architecture for isolation and stability.

## Overview

ccpt-gateway provides:
- **REST API** for synchronous exchange queries (fetch balance, order book, trades, etc.)
- **WebSocket API** for real-time streaming (watch methods like `watch_ticker`, `watch_orders`)
- **Admin API** for process management
- **Auto-Update** for CCXT library updates

## Installation

```bash
# Clone or download the project
cd ccxt-gateway

# Install dependencies
pip install -e .
# Or use uv
uv pip install -e .
```

## Running the Server

```bash
# Default (0.0.0.0:5555)
python -m ccxt_gateway.main

# Custom port
python -m ccxt_gateway.main --host 127.0.0.1 --port 8080

# With custom memory limit (MB)
python -m ccxt_gateway.main --max-rss-mb 1024
```

## Environment Variables

```bash
# Server settings
CCXT_GATEWAY_HOST=0.0.0.0
CCXT_GATEWAY_PORT=5555

# Process manager settings  
CCXT_GATEWAY_MAX_RSS_MB=512
CCXT_GATEWAY_AUTO_RESTART=true
CCXT_GATEWAY_CHECK_INTERVAL=30

# Update settings
CCXT_GATEWAY_CHECK_INTERVAL_HOURS=24
CCXT_GATEWAY_AUTO_UPDATE=false
```

## REST API

Base URL: `http://localhost:5555`

### Exchange Endpoints

#### Start/Stop Exchange

```bash
# Start an exchange
POST /exchanges/{exchange_id}
{
    "exchange_name": "binance",
    "api_key": "your-api-key",
    "secret": "your-secret"
}

# Stop an exchange
DELETE /exchanges/{exchange_id}
```

#### Fetch Methods

```bash
# Fetch balance
GET /exchanges/{exchange_id}/fetch_balance

# Fetch order book
GET /exchanges/{exchange_id}/fetch_order_book?symbol=BTC/USDT

# Fetch tickers
GET /exchanges/{exchange_id}/fetch_tickers

# Fetch ticker
GET /exchanges/{exchange_id}/fetch_ticker?symbol=BTC/USDT

# Fetch trades
GET /exchanges/{exchange_id}/fetch_trades?symbol=BTC/USDT

# Fetch orders
GET /exchanges/{exchange_id}/fetch_orders

# Fetch open orders
GET /exchanges/{exchange_id}/fetch_open_orders?symbol=BTC/USDT

# Create order
POST /exchanges/{exchange_id}/create_order
{
    "symbol": "BTC/USDT",
    "type": "limit",
    "side": "buy",
    "amount": 0.001,
    "price": 50000
}

# Cancel order
DELETE /exchanges/{exchange_id}/cancel_order?order_id=123456

# Withdraw
POST /exchanges/{exchange_id}/withdraw
{
    "code": "BTC",
    "amount": 0.1,
    "address": "your-address",
    "tag": "optional-tag"
}
```

#### Query Parameters

All endpoints support optional parameters:
- `params`: Additional exchange-specific parameters
- `api_key`, `secret`, `password`, `uid`: Credentials (if not set at start)

#### Response Format

```json
{
    "type": "response",
    "id": "request-id",
    "data": {
        "result": {}
    }
}
```

#### Error Response

```json
{
    "type": "response", 
    "id": "request-id",
    "error": "Error message",
    "error_code": "ERROR_CODE"
}
```

## WebSocket API

Connect to: `ws://localhost:5555/ws`

### Messages

#### Subscribe

```json
{
    "type": "subscribe",
    "subscription_id": "unique-id",
    "exchange_id": "binance",
    "method": "watch_ticker",
    "params": {"symbol": "BTC/USDT"}
}
```

#### Unsubscribe

```json
{
    "type": "unsubscribe", 
    "subscription_id": "unique-id"
}
```

#### Responses

```json
// Subscribed confirmation
{
    "type": "subscribed",
    "subscription_id": "unique-id",
    "exchange_id": "binance",
    "method": "watch_ticker"
}

// Ticker update
{
    "type": "update",
    "subscription_id": "unique-id",
    "data": {
        "symbol": "BTC/USDT",
        "last": 50000.00
    }
}

// Error
{
    "type": "error",
    "error": "Error message"
}
```

### Supported Watch Methods

- `watch_ticker` - Real-time ticker updates
- `watch_tickers` - All tickers
- `watch_order_book` - Order book updates
- `watch_trades` - Trade updates
- `watch_orders` - Order updates
- `watch_balance` - Balance updates

## Admin API

Base URL: `http://localhost:5555`

### Process Management

```bash
# Get all exchanges
GET /admin/exchanges

# Response:
{
    "exchanges": {
        "binance": {
            "exchange_id": "binance",
            "exchange_name": "binance", 
            "status": "running",
            "pid": 12345,
            "rss_mb": 45.2,
            "restart_count": 0,
            "started_at": "2024-01-01T00:00:00"
        }
    }
}
```

```bash
# Get exchange details
GET /admin/exchanges/{exchange_id}
```

```bash
# Restart exchange
POST /admin/exchanges/{exchange_id}/restart
```

```bash
# Get server info
GET /admin/info
```

### Memory Management

```bash
# Get current memory usage
GET /admin/memory

# Response:
{
    "total_rss_mb": 256.5,
    "processes": {
        "binance": 45.2,
        "bybit": 38.1
    }
}
```

## Architecture

### Multi-Process Design

```
┌─────────────────────────────────────────┐
│           Main Process                  │
│  ┌─────────────┐  ┌──────────────┐  │
│  │ REST API   │  │ Admin API  │  │
│  ├─────────────┤  ├──────────────┤  │
│  │ WebSocket │  │ ZMQ Router│  │
│  └─────────────┘  └──────────────┘  │
└─────────────────────────────────────┘
              │ ZMQ
              ▼
┌──────────────────────────────────────────────────────────┐
│                   Subprocesses (one per exchange)             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │  binance   │  │   bybit    │  │   okx     │ │
│  │  (CCXT)   │  │  (CCXT)    │  │  (CCXT)    │ │
│  └──────────────┘  └──────────────┘  └──────────────┘ │
└───────────────────────────────────────────────────────
```

### Memory Monitoring

- Each exchange process is monitored individually
- If RSS exceeds `max_rss_mb`, process is restarted
- Automatic restart on process crash

### Update Checking

- Background checker runs every `check_interval_hours`
- Compares installed CCXT version with PyPI
- Optional auto-update via pip

## Error Codes

| Code | Description |
|------|------------|
| `EXCHANGE_NOT_FOUND` | Exchange not started |
| `INVALID_METHOD` | CCXT method not found |
| `METHOD_ERROR` | Error calling CCXT method |
| `TIMEOUT` | Request timed out |
| `EXCHANGE_NOT_STARTED` | Exchange process not running |
| `INVALID_JSON` | Invalid JSON in request |
| `SUBSCRIPTION_NOT_FOUND` | WebSocket subscription not found |
| `INVALID_REQUEST` | Invalid request message |

## Examples

### Python

```python
import requests

# Start exchange
resp = requests.post("http://localhost:5555/exchanges/binance", json={
    "exchange_name": "binance",
    "api_key": "YOUR_KEY",
    "secret": "YOUR_SECRET"
})

# Fetch ticker
resp = requests.get("http://localhost:5555/exchanges/binance/fetch_ticker?symbol=BTC/USDT")
print(resp.json())
```

### JavaScript

```javascript
// Fetch balance
const resp = await fetch('http://localhost:5555/exchanges/binance/fetch_balance');
const data = await resp.json();
console.log(data);

// WebSocket
const ws = new WebSocket('ws://localhost:5555/ws');
ws.onmessage = (e) => console.log(JSON.parse(e.data));
ws.send(JSON.stringify({
    type: 'subscribe',
    subscription_id: 'ticker-btc',
    exchange_id: 'binance',
    method: 'watch_ticker',
    params: { symbol: 'BTC/USDT' }
}));
```

### cURL

```bash
# Start exchange
curl -X POST http://localhost:5555/exchanges/binance \
  -H "Content-Type: application/json" \
  -d '{"exchange_name": "binance"}'

# Fetch ticker
curl http://localhost:5555/exchanges/binance/fetch_ticker?symbol=BTC/USDT
```

## Troubleshooting

### Exchange won't start

- Check API key/secret are valid
- Check network connectivity
- Check exchange supports your region

### Memory issues

- Increase `--max-rss-mb` flag
- Too many subscriptions can cause high memory use

### Timeouts

- Increase timeout in `params`: `{"params": {"timeout": 60000}}`
- Check network latency to exchange

### WebSocket disconnects

- Check server logs for errors
- Ensure client sends periodic pings
- Network may have connection limits