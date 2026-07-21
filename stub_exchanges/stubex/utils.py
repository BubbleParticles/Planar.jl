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


import hashlib

def _canon_seed(seed_val: Any) -> str:
    if seed_val is None:
        return "none"
    if isinstance(seed_val, (tuple, list)):
        return "|".join(_canon_seed(x) for x in seed_val)
    s = str(seed_val).strip()
    # Normalize symbols like 'BTC/USDT:USDT' to 'BTC/USDT'
    if ":" in s:
        s = s.split(":")[0]
    return s.upper()


def deterministic_random(seed_val: Any):
    """Return a deterministic random.Random seeded from a stable hash of seed_val.

    Uses a SHA-256 based seed of the canonicalized seed value so results are
    stable across processes and invocations (unlike Python's built-in hash).
    """
    key = _canon_seed(seed_val)
    # Use first 8 hex chars (32 bits) of SHA256 as the seed integer
    h = int(hashlib.sha256(key.encode("utf-8")).hexdigest()[:8], 16)
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
    """Generate a deterministic balance containing both base and quote currencies when a symbol is provided.

    For a market like "BTC/USDT:USDT" this returns totals for both BTC and USDT so callers
    that look up either currency (base or quote) can find a numeric value.
    """
    r = deterministic_random(getattr(exchange, "id", "default") + (symbol or ""))
    # sensible defaults
    quote_amount = round(10000.0 * (0.5 + r.random()), 8)
    base_amount = round(1.0 * (0.1 + r.random()), 8)

    base = "BTC"
    quote = "USD"
    if symbol:
        try:
            s = str(symbol)
            # strip exchange-specific suffixes like ':USDT'
            if ":" in s:
                s = s.split(":")[0]
            if "/" in s:
                parts = s.split("/")
                if len(parts) >= 2:
                    base, quote = parts[0], parts[1]
                else:
                    base = parts[0]
            else:
                base = s
        except Exception:
            pass

    total = {quote: quote_amount, base: base_amount}
    free = {k: v for k, v in total.items()}
    used = {k: 0.0 for k in total.keys()}

    # Also include per-currency nested mappings alongside the top-level shape
    v = {"total": total, "free": free, "used": used}
    v[base] = {"total": base_amount, "free": base_amount, "used": 0.0}
    v[quote] = {"total": quote_amount, "free": quote_amount, "used": 0.0}
    return v


def generate_order(symbol: str = None, order_type: str = "limit") -> Dict[str, Any]:
    r = deterministic_random(symbol or "order")
    base = 100.0 + r.random() * 100.0
    price = round(base * (1 + (r.random() - 0.5) * 0.02), 8)
    amount = round((1 + r.random()) * 0.1, 8)
    side = "buy" if r.random() > 0.5 else "sell"
    ts = _now_ms()
    filled = 0.0
    status = "open"
    trades = []
    cost = 0.0
    average = None
    # default to a closed (filled) market-like order only when order_type indicates market
    if order_type is not None and str(order_type).lower() == 'market':
        filled = amount
        status = "closed"
        cost = round(price * filled, 8)
        average = price
        trades = [{"id": f"t{ts}", "timestamp": ts, "datetime": datetime.utcfromtimestamp(ts / 1000).isoformat(), "symbol": symbol, "price": price, "amount": filled, "side": side}]
    return {
        "id": f"o{int(time.time()*1000)%1_000_000}",
        "symbol": symbol,
        "type": order_type,
        "side": side,
        "price": price,
        "amount": amount,
        "filled": filled,
        "remaining": round((amount - filled) if amount is not None else 0.0, 8),
        "status": status,
        "timestamp": ts,
        "datetime": datetime.utcfromtimestamp(ts / 1000).isoformat(),
        "cost": cost,
        "average": average,
        "trades": trades,
    }


def generate_leverage_tiers(symbol: str, tiers_count: int = 3) -> List[Dict[str, Any]]:
    """Generate plausible leverage tier definitions for a symbol.

    Returns a list of dicts matching the shape returned by exchanges such as Binance:
    [{"tier": 1, "currency": "BTC", "minNotional": 0.0, "maxNotional": 1e6, "maxLeverage": 100.0, "maintenanceMarginRate": 0.005, "info": {}}, ...]
    """
    r = deterministic_random((symbol, "leverage"))
    s = str(symbol)
    if ":" in s:
        s = s.split(":")[0]
    base = s.split("/")[0] if "/" in s else s
    tiers: List[Dict[str, Any]] = []
    # sensible defaults with increasing notional thresholds and decreasing leverage
    defaults = [
        (1e-8, 2e6, 100.0, 0.005),
        (2e6 + 1e-8, 1e7, 50.0, 0.01),
        (1e7 + 1e-8, 1e9, 20.0, 0.02),
    ]
    for i in range(min(tiers_count, len(defaults))):
        mn, mx, mle, mmr = defaults[i]
        # add a small deterministic jitter so different symbols aren't identical
        jitter = (r.random() - 0.5) * (mx * 1e-6)
        tiers.append(
            {
                "tier": i + 1,
                "currency": base,
                "minNotional": float(round(mn + max(-abs(jitter), 0.0), 8)),
                "maxNotional": float(round(mx + jitter, 8)),
                "maxLeverage": float(mle),
                "maintenanceMarginRate": float(mmr),
                "info": {},
            }
        )
    # If more tiers requested, extend conservatively
    last_max = tiers[-1]["maxNotional"] if tiers else 1e9
    for j in range(len(tiers), tiers_count):
        last_max = last_max * 10
        tiers.append({
            "tier": j + 1,
            "currency": base,
            "minNotional": float(last_max / 10 + 1e-8),
            "maxNotional": float(last_max),
            "maxLeverage": float(max(1.0, 20.0 / (j + 1))),
            "maintenanceMarginRate": float(0.02 * (j + 1)),
            "info": {},
        })
    return tiers


def safe_load_markets(exchange) -> None:
    try:
        if hasattr(exchange, "load_markets"):
            exchange.load_markets()
    except Exception:
        # don't fail on network or other errors when loading markets
        pass
