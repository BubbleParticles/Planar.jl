Stub Exchanges
===============

This small ancillary package provides a CLI and a FastAPI server that mimics a CCXT-supported exchange API for local testing.

Quickstart
---------

1. Create and activate a virtualenv from the repository root:

    python3 -m venv stub_exchanges/venv
    source stub_exchanges/venv/bin/activate

2. Install requirements:

    pip install -r stub_exchanges/requirements.txt

3. Run the stub server for an exchange (e.g., binance):

    python stub_exchanges/cli.py --exchange binance --host 127.0.0.1 --port 9000

Endpoints
---------

- GET / -> basic info
- GET /has -> exchange.has
- GET /ohlcv?symbol=BTC/USDT&limit=100
- GET /orderbook?symbol=BTC/USDT&depth=20
- GET /fees
- GET /funding?symbol=BTC/USDT
- GET /trades?symbol=BTC/USDT
- GET /balance?symbol=BTC
- GET /orders?symbol=BTC/USDT

Notes
-----

The server uses ccxt.exchanges and ccxt exchange classes only for introspection (exchange.has, exchange.fees). All returned data is synthetic and deterministic based on the symbol and exchange name to make tests reproducible.
