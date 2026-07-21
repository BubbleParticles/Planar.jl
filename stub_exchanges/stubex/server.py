"""FastAPI server that exposes stubbed endpoints mimicking ccxt exchanges.

Usage:
    from stubex import server
    server.run(exchange_name, host='127.0.0.1', port=8000)

Endpoints:
    GET / -> basic info
    GET /has -> exchange.has properties
    GET /ohlcv?symbol=BTC/USDT&since=...&limit=... -> OHLCV array
    GET /orderbook?symbol=BTC/USDT&depth=20 -> orderbook
    GET /fees -> fees
    GET /funding?symbol=BTC/USDT -> funding rate
    GET /trades?symbol=BTC/USDT -> trades
    GET /balance?symbol=BTC -> balance
    GET /orders -> dummy orders
"""

import os
import ccxt
from fastapi import FastAPI, HTTPException
from typing import Optional
from . import utils
import uvicorn

app = FastAPI(title="CCXT Stub Exchange")

# Global exchange instance -- set in run()
EXCHANGE = None
EXCHANGE_NAME = None


@app.get("/")
async def root():
    if EXCHANGE is None:
        return {"ok": False, "msg": "no exchange selected", "available_exchanges": list(ccxt.exchanges)}
    info = {"id": getattr(EXCHANGE, "id", EXCHANGE_NAME), "has": getattr(EXCHANGE, "has", {})}
    return {"ok": True, "exchange": info}


@app.get("/has")
async def has():
    if EXCHANGE is None:
        raise HTTPException(status_code=400, detail="Exchange not configured")
    return {"has": EXCHANGE.has}


@app.get("/ohlcv")
async def ohlcv(symbol: str = "BTC/USDT", since: Optional[int] = None, limit: int = 100, timeframe_minutes: int = 1):
    if EXCHANGE is None:
        raise HTTPException(status_code=400, detail="Exchange not configured")
    data = utils.generate_ohlcv(symbol, since=since, limit=limit, timeframe_minutes=timeframe_minutes)
    return {"symbol": symbol, "since": since, "limit": limit, "data": data}


@app.get("/orderbook")
async def orderbook(symbol: str = "BTC/USDT", depth: int = 20):
    if EXCHANGE is None:
        raise HTTPException(status_code=400, detail="Exchange not configured")
    ob = utils.generate_orderbook(symbol, depth=depth)
    return ob


@app.get("/fees")
async def fees():
    if EXCHANGE is None:
        raise HTTPException(status_code=400, detail="Exchange not configured")
    return {"fees": utils.get_fees(EXCHANGE)}


@app.get("/funding")
async def funding(symbol: str = "BTC/USDT"):
    if EXCHANGE is None:
        raise HTTPException(status_code=400, detail="Exchange not configured")
    return utils.generate_funding_rate(symbol, EXCHANGE)


@app.get("/trades")
async def trades(symbol: str = "BTC/USDT", limit: int = 50):
    if EXCHANGE is None:
        raise HTTPException(status_code=400, detail="Exchange not configured")
    return {"symbol": symbol, "trades": utils.generate_trades(symbol, limit=limit)}


@app.get("/balance")
async def balance(symbol: Optional[str] = None):
    if EXCHANGE is None:
        raise HTTPException(status_code=400, detail="Exchange not configured")
    return utils.generate_balance(EXCHANGE, symbol)


@app.get("/orders")
async def orders(symbol: str = "BTC/USDT", limit: int = 10):
    if EXCHANGE is None:
        raise HTTPException(status_code=400, detail="Exchange not configured")
    return {"orders": [utils.generate_order(symbol) for _ in range(limit)]}


def configure_exchange(name: str):
    global EXCHANGE, EXCHANGE_NAME
    EXCHANGE_NAME = name
    EXCHANGE = utils.instantiate_exchange(name)
    # Try to load markets, but ignore failures (no network required)
    utils.safe_load_markets(EXCHANGE)
    return EXCHANGE


def run(exchange_name: str, host: str = "127.0.0.1", port: int = 8000):
    configure_exchange(exchange_name)
    # Run uvicorn programmatically
    uvicorn.run("stubex.server:app", host=host, port=port, reload=False)


if __name__ == "__main__":
    # Allow running server as a module (python -m stubex.server)
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("exchange", help="Exchange name (from ccxt.exchanges)")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", default=8000, type=int)
    args = parser.parse_args()
    run(args.exchange, host=args.host, port=args.port)
