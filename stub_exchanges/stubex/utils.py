"""Utilities to generate stubbed exchange responses.

This module uses ccxt to introspect exchange features and generates
plausible synthetic data for OHLCV, orderbook, fees, funding rates, trades, and balances.
"""

import ccxt
import random
import time
import math
from datetime import datetime, timedelta
from typing import List, Dict, Any, Optional


def instantiate_exchange(name: str):
    """Instantiate a ccxt exchange class by name.

    Raises ValueError if the exchange is unknown.
    """
    name = name.lower()
    if name not in ccxt.exchanges:
        raise ValueError(f"Unknown exchange: {name}")
    ex_cls = getattr(ccxt, name)
    try:
        exch = ex_cls()
    except Exception:
        # Some exchanges may require extra arguments during init; fall back to constructing with no args
        exch = ex_cls({})
    return exch


def deterministic_random(seed_val: Any):
    h = hash(seed_val) & 0xFFFFFFFF
    r = random.Random(h)
    return r


def _now_ms():
    return int(time.time() * 1000)


def generate_ohlcv(symbol: str, since: Optional[int] = None, limit: int = 100, timeframe_minutes: int = 1) -> List[List[Any]]:
    """Generate a simple deterministic OHLCV sequence for symbol.

    Returns a list of [timestamp_ms, open, high, low, close, volume]
    """
    r = deterministic_random(symbol)
    if since is None:
        end = _now_ms()
    else:
        end = int(since)
    timeframe_ms = timeframe_minutes * 60 * 1000
    if since is None:
        start = end - limit * timeframe_ms
    else:
        start = end
        end = start + limit * timeframe_ms
    rows = []
    price = 100.0 + r.random() * 100.0
    for i in range(limit):
        t = start + i * timeframe_ms
        o = price * (1 + (r.random() - 0.5) * 0.01)
        c = o * (1 + (r.random() - 0.5) * 0.02)
        h = max(o, c) * (1 + r.random() * 0.01)
        l = min(o, c) * (1 - r.random() * 0.01)
        vol = max(1e-8, r.random() * 10)
        rows.append([t, round(o, 8), round(h, 8), round(l, 8), round(c, 8), round(vol, 8)])
        price = c
    return rows


def generate_orderbook(symbol: str, depth: int = 20, base_price: Optional[float] = None) -> Dict[str, Any]:
    r = deterministic_random(symbol)
    if base_price is None:
        base_price = 100.0 + r.random() * 100.0
    bids = []
    asks = []
    for i in range(depth):
        p_bid = base_price * (1 - (i + 1) * 0.0005 * (1 + r.random()))
        q_bid = round( (1 + r.random()) * (10 - i%5), 8)
        bids.append([round(p_bid, 8), q_bid])
        p_ask = base_price * (1 + (i + 1) * 0.0005 * (1 + r.random()))
        q_ask = round( (1 + r.random()) * (10 - i%5), 8)
        asks.append([round(p_ask, 8), q_ask])
    return {"bids": bids, "asks": asks, "timestamp": _now_ms(), "nonce": None}


def get_fees(exchange) -> Dict[str, Any]:
    # Try to read fees from exchange if available
    fees = {"maker": None, "taker": None}
    try:
        if hasattr(exchange, "fees") and isinstance(exchange.fees, dict):
            f = exchange.fees
            fees["maker"] = f.get("maker") if f.get("maker") is not None else f.get("taker")
            fees["taker"] = f.get("taker") if f.get("taker") is not None else f.get("maker")
    except Exception:
        pass
    # fallback defaults
    if fees["maker"] is None:
        fees["maker"] = 0.001
    if fees["taker"] is None:
        fees["taker"] = 0.002
    return fees


def generate_funding_rate(symbol: str, exchange=None) -> Dict[str, Any]:
    r = deterministic_random((symbol, getattr(exchange, "id", "")))
    rate = (r.random() - 0.5) * 0.001
    nextFunding = _now_ms() + 8 * 60 * 60 * 1000
    return {"symbol": symbol, "fundingRate": round(rate, 8), "nextFundingTime": nextFunding}


def generate_trades(symbol: str, limit: int = 50) -> List[Dict[str, Any]]:
    r = deterministic_random(symbol)
    trades = []
    base = 100.0 + r.random() * 100.0
    now_ms = _now_ms()
    for i in range(limit):
        t = now_ms - i * 1000
        price = base * (1 + (r.random() - 0.5) * 0.01)
        amount = round((1 + r.random()) * 0.01, 8)
        side = "buy" if r.random() > 0.5 else "sell"
        trades.append({"id": f"t{i}", "timestamp": t, "datetime": datetime.utcfromtimestamp(t / 1000).isoformat(), "symbol": symbol, "price": round(price, 8), "amount": amount, "side": side})
    return trades


def generate_balance(exchange, symbol: Optional[str] = None) -> Dict[str, Any]:
    r = deterministic_random(getattr(exchange, "id", "default") + (symbol or ""))
    base_quote = 10000.0
    base_base = 1.0
    return {"total": {"USD": round(base_quote * (0.5 + r.random()), 8), (symbol or "BTC"): round(base_base * (0.1 + r.random()), 8)}, "used": {}, "free": {}}


def generate_order(symbol: str, order_type: str = "limit") -> Dict[str, Any]:
    r = deterministic_random(symbol)
    base = 100.0 + r.random() * 100.0
    price = round(base * (1 + (r.random() - 0.5) * 0.02), 8)
    amount = round((1 + r.random()) * 0.1, 8)
    side = "buy" if r.random() > 0.5 else "sell"
    return {"id": f"o{int(time.time()*1000)%1_000_000}", "symbol": symbol, "type": order_type, "side": side, "price": price, "amount": amount, "filled": 0.0, "remaining": amount}


def safe_load_markets(exchange) -> None:
    try:
        if hasattr(exchange, "load_markets"):
            exchange.load_markets()
    except Exception:
        # don't fail on network or other errors when loading markets
        pass
