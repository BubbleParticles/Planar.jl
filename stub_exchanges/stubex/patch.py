"""Patch ccxt exchange instances to return deterministic stub data.

This module monkey-patches a ccxt exchange instance (async or sync) by
binding coroutine-based stub functions to common ccxt methods used by
Planar (ohlcv, orderbook, trades, balances, orders, positions, create/cancel).

It uses stubex.utils deterministic generators to produce plausible data.
"""

import types
import time
from typing import Any

from . import utils


def _to_minutes(timeframe: str) -> int:
    try:
        if isinstance(timeframe, str):
            timeframe = timeframe.strip()
            if timeframe.endswith("m"):
                return int(timeframe[:-1])
            if timeframe.endswith("h"):
                return int(timeframe[:-1]) * 60
            if timeframe.endswith("d"):
                return int(timeframe[:-1]) * 60 * 24
        return int(timeframe)
    except Exception:
        return 1


def _now_ms() -> int:
    return int(time.time() * 1000)


def _make_position(symbol: str, exchange=None):
    """Return a minimal ccxt-style position dict for the given symbol."""
    now = _now_ms()
    return {
        "symbol": symbol,
        "contracts": 0.0,
        "entryPrice": 0.0,
        "unrealizedPnl": 0.0,
        "leverage": 1.0,
        "markPrice": 0.0,
        "lastPrice": 0.0,
        "liquidationPrice": 0.0,
        "initialMargin": 0.0,
        "maintenanceMargin": 0.0,
        "timestamp": now,
        "datetime": None,
        "id": None,
        "contractSize": 1.0,
        "marginMode": None,
        "marginRatio": 0.0,
        "hedged": False,
        "percentage": 0.0,
    }


# ASYNC STUB FUNCTIONS
async def fetch_ohlcv(self, symbol, timeframe="1m", since=None, limit=100, params=None):
    tf = _to_minutes(timeframe)
    lim = limit if limit is not None else 100
    return utils.generate_ohlcv(symbol, since, lim, tf)


async def fetch_order_book(self, symbol, limit=None, params=None):
    depth = limit if limit is not None else 20
    return utils.generate_orderbook(symbol, depth)


async def fetch_trades(self, symbol, since=None, limit=50, params=None):
    lim = limit if limit is not None else 50
    return utils.generate_trades(symbol, lim)


async def fetch_my_trades(self, symbol=None, since=None, limit=50, params=None):
    # reuse generate_trades
    if symbol is None:
        # no symbol specified, return empty list
        return []
    return await fetch_trades(self, symbol, since, limit, params)


async def fetch_balance(self, params=None):
    return utils.generate_balance(self, None)


async def create_order(self, symbol, type, side, amount, price=None, params=None):
    return utils.generate_order(symbol, order_type=type)


async def cancel_order(self, id, symbol=None, params=None):
    return {"id": id, "status": "canceled"}


async def fetch_orders(self, symbol=None, since=None, limit=None, params=None):
    # return an empty list by default
    return []


async def fetch_open_orders(self, symbol=None, since=None, limit=None, params=None):
    return []


async def fetch_positions(self, symbols=None, params=None):
    # Accept both a list of symbols or None.
    if symbols is None:
        return []
    out = []
    try:
        # symbols may be a python list or tuple
        for s in symbols:
            out.append(_make_position(s, self))
    except Exception:
        # fallback: single symbol
        try:
            out.append(_make_position(symbols, self))
        except Exception:
            pass
    return out


def _bind(inst, name, func):
    """Bind function `func` as attribute `name` on `inst` using MethodType."""
    try:
        bound = types.MethodType(func, inst)
        setattr(inst, name, bound)
    except Exception:
        try:
            # last resort: set as plain attribute
            setattr(inst, name, func)
        except Exception:
            pass


def patch_exchange(exchange, exch_name: str = None):
    """Patch a ccxt exchange instance in-place to provide stubbed method implementations.

    exchange: the Python ccxt exchange instance (async or sync)
    exch_name: optional exchange id string used for deterministic seeds (ignored currently)
    """
    try:
        # streaming/watch stub implementations
        async def watch_balance(self, *args, **kwargs):
            # ccxt.watchBalance usually returns a balance snapshot when awaited
            symbol = None
            if len(args) > 0:
                symbol = args[0]
            try:
                return utils.generate_balance(self, symbol)
            except Exception:
                return utils.generate_balance(self, None)

        async def watch_positions(self, symbols=None, params=None):
            if symbols is None:
                return []
            out = []
            try:
                for s in symbols:
                    out.append(_make_position(s, self))
            except Exception:
                try:
                    out.append(_make_position(symbols, self))
                except Exception:
                    pass
            return out

        async def watch_order_book(self, symbol, limit=None, params=None):
            depth = limit if limit is not None else 20
            return utils.generate_orderbook(symbol, depth)

        async def watch_trades(self, symbol, since=None, limit=50, params=None):
            lim = limit if limit is not None else 50
            return utils.generate_trades(symbol, lim)

        async def watch_ticker(self, symbol, params=None):
            ohlcv = utils.generate_ohlcv(symbol, None, 1, 1)
            if not ohlcv:
                return {}
            last = ohlcv[-1]
            return {
                "symbol": symbol,
                "timestamp": last[0],
                "datetime": None,
                "high": last[2],
                "low": last[3],
                "bid": last[4],
                "ask": last[4],
                "vwap": None,
                "open": last[1],
                "close": last[4],
                "last": last[4],
                "previousClose": None,
                "change": None,
                "percentage": None,
                "average": None,
                "baseVolume": last[5],
                "quoteVolume": None,
            }

        # map of canonical names -> function object (async functions)
        mappings = [
            ("fetch_ohlcv", fetch_ohlcv),
            ("fetchOHLCV", fetch_ohlcv),
            ("fetch_order_book", fetch_order_book),
            ("fetchOrderBook", fetch_order_book),
            ("fetch_trades", fetch_trades),
            ("fetchTrades", fetch_trades),
            ("fetch_my_trades", fetch_my_trades),
            ("fetchMyTrades", fetch_my_trades),
            ("fetch_balance", fetch_balance),
            ("fetchBalance", fetch_balance),
            ("create_order", create_order),
            ("createOrder", create_order),
            ("cancel_order", cancel_order),
            ("cancelOrder", cancel_order),
            ("fetch_orders", fetch_orders),
            ("fetchOrders", fetch_orders),
            ("fetch_open_orders", fetch_open_orders),
            ("fetchOpenOrders", fetch_open_orders),
            ("fetch_positions", fetch_positions),
            ("fetchPositions", fetch_positions),
            ("watch_balance", watch_balance),
            ("watchBalance", watch_balance),
            ("watch_positions", watch_positions),
            ("watchPositions", watch_positions),
            ("watch_order_book", watch_order_book),
            ("watchOrderBook", watch_order_book),
            ("watch_trades", watch_trades),
            ("watchTrades", watch_trades),
            ("watch_ticker", watch_ticker),
            ("watchTicker", watch_ticker),
            ("loadMarkets", fetch_orders),
        ]

        # Bind all mappings
        for (nm, fn) in mappings:
            try:
                _bind(exchange, nm, fn)
            except Exception:
                # ignore
                pass

        # Also try patching the exchange class to override methods implemented as descriptors
        try:
            ex_cls = type(exchange)
            for (nm, fn) in mappings:
                try:
                    setattr(ex_cls, nm, fn)
                except Exception:
                    pass
        except Exception:
            pass

        # Provide a minimal async loadMarkets implementation to avoid network calls
        async def _load_markets(self, reload=False):
            # minimal fields expected by Planar's loadmarkets! flow
            try:
                self.markets = {}
                self.markets_by_id = {}
                self.symbols = []
                self.currencies = {}
            except Exception:
                pass
            return None

        _bind(exchange, "loadMarkets", _load_markets)
        _bind(exchange, "load_markets", _load_markets)

        # Try set has flags so ccxt feature detection picks them up
        try:
            if hasattr(exchange, "has") and exchange.has is not None:
                for (nm, _) in mappings:
                    try:
                        # some exchanges expect snake_case keys in `has`
                        exchange.has[nm] = True
                    except Exception:
                        pass
        except Exception:
            pass

        # Provide dummy credentials to avoid AuthenticationError for exchanges that require them
        try:
            try:
                if not hasattr(exchange, "apiKey") or exchange.apiKey is None:
                    exchange.apiKey = "stub"
            except Exception:
                pass
            try:
                if not hasattr(exchange, "secret") or exchange.secret is None:
                    exchange.secret = "stub"
            except Exception:
                pass
            # some exchanges may check for password or uid
            try:
                if not hasattr(exchange, "password"):
                    exchange.password = "stub"
            except Exception:
                pass
        except Exception:
            pass

        # Attempt to wrap original watch* methods to catch AuthenticationError and return stub data
        try:
            import asyncio
            from ccxt.base.errors import AuthenticationError

            def _make_wrapper(orig, nm):
                if asyncio.iscoroutinefunction(orig):
                    async def awrap(*args, **kwargs):
                        try:
                            return await orig(*args, **kwargs)
                        except Exception as e:
                            # On authentication errors return fallback stub
                            try:
                                if isinstance(e, AuthenticationError) or e.__class__.__name__ == 'AuthenticationError':
                                    ln = nm.lower()
                                    if 'balance' in ln:
                                        return utils.generate_balance(exchange, None)
                                    if 'position' in ln:
                                        # args may contain symbols list
                                        symbols = None
                                        if len(args) > 0:
                                            symbols = args[0]
                                        if symbols is None:
                                            return []
                                        out = []
                                        try:
                                            for s in symbols:
                                                out.append(_make_position(s, exchange))
                                        except Exception:
                                            try:
                                                out.append(_make_position(symbols, exchange))
                                            except Exception:
                                                pass
                                        return out
                                    if 'order' in ln and 'book' in ln:
                                        symbol = args[0] if len(args) > 0 else None
                                        depth = kwargs.get('limit', None)
                                        return utils.generate_orderbook(symbol, depth if depth is not None else 20)
                                    if 'trade' in ln:
                                        symbol = args[0] if len(args) > 0 else None
                                        lim = kwargs.get('limit', 50)
                                        return utils.generate_trades(symbol, lim)
                                    if 'ticker' in ln:
                                        symbol = args[0] if len(args) > 0 else None
                                        ohlcv = utils.generate_ohlcv(symbol, None, 1, 1)
                                        if not ohlcv:
                                            return {}
                                        last = ohlcv[-1]
                                        return {
                                            'symbol': symbol,
                                            'timestamp': last[0],
                                            'datetime': None,
                                            'high': last[2],
                                            'low': last[3],
                                            'bid': last[4],
                                            'ask': last[4],
                                            'open': last[1],
                                            'close': last[4],
                                            'last': last[4],
                                            'baseVolume': last[5],
                                        }
                            except Exception:
                                pass
                            raise
                    return awrap
                else:
                    def swrap(*args, **kwargs):
                        try:
                            return orig(*args, **kwargs)
                        except Exception as e:
                            try:
                                if isinstance(e, AuthenticationError) or e.__class__.__name__ == 'AuthenticationError':
                                    ln = nm.lower()
                                    if 'balance' in ln:
                                        return utils.generate_balance(exchange, None)
                                    if 'position' in ln:
                                        return []
                                    if 'order' in ln and 'book' in ln:
                                        symbol = args[0] if len(args) > 0 else None
                                        depth = kwargs.get('limit', None)
                                        return utils.generate_orderbook(symbol, depth if depth is not None else 20)
                                    if 'trade' in ln:
                                        symbol = args[0] if len(args) > 0 else None
                                        lim = kwargs.get('limit', 50)
                                        return utils.generate_trades(symbol, lim)
                                    if 'ticker' in ln:
                                        symbol = args[0] if len(args) > 0 else None
                                        ohlcv = utils.generate_ohlcv(symbol, None, 1, 1)
                                        if not ohlcv:
                                            return {}
                                        last = ohlcv[-1]
                                        return {
                                            'symbol': symbol,
                                            'timestamp': last[0],
                                            'datetime': None,
                                            'high': last[2],
                                            'low': last[3],
                                            'bid': last[4],
                                            'ask': last[4],
                                            'open': last[1],
                                            'close': last[4],
                                            'last': last[4],
                                            'baseVolume': last[5],
                                        }
                            except Exception:
                                pass
                            raise
                    return swrap

            for (nm, fn) in mappings:
                try:
                    orig = getattr(exchange, nm, None)
                    if orig is not None:
                        wrapper = _make_wrapper(orig, nm)
                        try:
                            bound = types.MethodType(wrapper, exchange)
                            setattr(exchange, nm, bound)
                        except Exception:
                            try:
                                setattr(exchange, nm, wrapper)
                            except Exception:
                                pass
                except Exception:
                    pass
        except Exception:
            pass
    except Exception:
        # swallow errors - patcher is best-effort
        pass
