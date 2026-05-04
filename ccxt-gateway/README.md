# ccxt-gateway

High-performance, self-hosted gateway for 100+ cryptocurrency exchanges via CCXT.

## Features

- **High Performance**: Built with FastAPI, uvloop, and orjson for maximum throughput
- **Rock Solid Stability**: Multi-process design with automatic restart on failures
- **Memory Management**: Automatic subprocess restart when memory limits exceeded
- **WebSocket Support**: Proxy CCXT watch* functions via WebSocket connections
- **Auto-Update**: Automatic CCXT version management
- **Unified API**: Single REST and WebSocket API for all supported exchanges

## Quick Start

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/ccxt-gateway.git
cd ccxt-gateway

# Install dependencies
pip install -e ".[server]"
```

### Running

```bash
# Start the gateway
ccxt-gateway

# Or directly with Python
python -m ccxt_gateway.main
```

The gateway will start on `http://0.0.0.0:8000` by default.

### Basic Usage

```bash
# Create a Binance exchange instance
curl -X POST "http://localhost:8000/exchanges/my-binance?exchange_name=binance"

# Get ticker for BTC/USDT
curl "http://localhost:8000/exchanges/my-binance/fetch_ticker?symbol=BTC/USDT"

# Delete the exchange instance
curl -X DELETE "http://localhost:8000/exchanges/my-binance"
```

## Configuration

Configuration is loaded from (in order):
1. Environment variables (prefixed with `CCXT_GATEWAY_`)
2. `.env` file
3. `config/default.yaml`

See `config/default.yaml` for all available options.

## API Documentation

Once running, visit:
- Swagger UI: `http://localhost:8000/docs`
- ReDoc: `http://localhost:8000/redoc`

## Architecture

```
Client -> FastAPI -> ZMQ Broker -> Exchange Subprocess (CCXT)
```

Each exchange runs in its own subprocess, communicating via ZeroMQ for isolation and stability.

## Development

```bash
# Install dev dependencies
pip install -e ".[dev]"

# Run tests
pytest

# Format code
black src/
```

## License

MIT
