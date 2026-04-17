"""Patch ccxt exchange instances to return deterministic stub data.

This module monkey-patches a ccxt exchange instance (async or sync) by
binding coroutine-based stub functions to common ccxt methods used by
Planar (ohlcv, orderbook, trades, balances, orders, positions, create/cancel).

It uses stubex.utils deterministic generators to produce plausible data.
"""

import types
import time
import os
from typing import Any
import asyncio

from . import utils

_debug = os.environ.get('STUBEX_DEBUG', '') != ''


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
    """Return a minimal ccxt-style position dict for the given symbol.

    The stub produces an "open" position with small non-zero notional so LiveMode
    can synchronize cash/positions without falling back to `freecash` shims.
    """
    now = _now_ms()
    sym_str = None
    try:
        sym_str = str(symbol) if symbol is not None else None
    except Exception:
        sym_str = symbol
    # try to derive a reasonable last price from generated ohlcv
    price = None
    try:
        if sym_str:
            ohlcv = utils.generate_ohlcv(sym_str, None, 1, 1)
            if ohlcv and len(ohlcv) > 0:
                price = float(ohlcv[-1][4])
    except Exception:
        price = None
    if price is None:
        price = 100.0
    # produce a tiny open position so that sync logic sets cash on the position
    contracts = 1.0
    contract_size = 1.0
    notional = round(abs(contracts * price * contract_size), 8)
    # assume no leverage (leverage 1) so collateral == notional
    leverage = 1.0
    collateral = notional
    initial_margin = round(max(0.0, collateral * 0.9), 8)
    maintenance_margin = round(max(0.0, collateral * 0.05), 8)

    return {
        "symbol": sym_str,
        "contracts": float(contracts),
        "entryPrice": float(price),
        "unrealizedPnl": 0.0,
        "leverage": float(leverage),
        "markPrice": float(price),
        "lastPrice": float(price),
        "liquidationPrice": 0.0,
        "initialMargin": float(initial_margin),
        "maintenanceMargin": float(maintenance_margin),
        "collateral": float(collateral),
        "notional": float(notional),
        "timestamp": now,
        "lastUpdateTimestamp": now,
        "datetime": None,
        "id": None,
        "contractSize": float(contract_size),
        "marginMode": None,
        "marginRatio": 0.0,
        "side": "long",
        "hedged": False,
        "percentage": 0.0,
        "additionalMargin": 0.0,
    }


# ASYNC STUB FUNCTIONS
async def fetch_ohlcv(self, *args, **kwargs):
    # signature compatibility: accept (symbol, timeframe, since, limit, params) or kwargs
    try:
        symbol = args[0] if len(args) > 0 else kwargs.get('symbol', None)
        timeframe = args[1] if len(args) > 1 else kwargs.get('timeframe', "1m")
        since = args[2] if len(args) > 2 else kwargs.get('since', None)
        limit = args[3] if len(args) > 3 else kwargs.get('limit', 100)
        tf = _to_minutes(timeframe)
        lim = limit if limit is not None else 100
        return utils.generate_ohlcv(symbol, since, lim, tf)
    except Exception:
        return []


async def fetch_order_book(self, *args, **kwargs):
    try:
        symbol = args[0] if len(args) > 0 else kwargs.get('symbol', None)
        limit = args[1] if len(args) > 1 else kwargs.get('limit', None)
        depth = limit if limit is not None else 20
        return utils.generate_orderbook(symbol, depth)
    except Exception:
        return {"bids": [], "asks": [], "timestamp": _now_ms(), "nonce": None}


async def fetch_trades(self, *args, **kwargs):
    try:
        symbol = args[0] if len(args) > 0 else kwargs.get('symbol', None)
        since = args[1] if len(args) > 1 else kwargs.get('since', None)
        limit = args[2] if len(args) > 2 else kwargs.get('limit', 50)
        lim = limit if limit is not None else 50
        return utils.generate_trades(symbol, lim)
    except Exception:
        return []


async def fetch_tickers(self, *args, **kwargs):
    """Return a dict of tickers keyed by symbol (best-effort stub).

    Accepts optional `type` parameter as either positional or kwarg. If the
    exchange instance exposes `.symbols` use that list, otherwise fall back to
    a small common set used in tests.
    """
    try:
        _type = args[0] if len(args) > 0 else kwargs.get('type', None)
        syms = []
        try:
            if hasattr(self, 'symbols') and self.symbols:
                syms = list(self.symbols)
        except Exception:
            syms = []
        if not syms:
            syms = ['BTC/USDT:USDT', 'ETH/USDT:USDT', 'SOL/USDT:USDT']
        out = {}
        for s in syms:
            ohlcv = utils.generate_ohlcv(s, None, 1, 1)
            if not ohlcv:
                continue
            last = ohlcv[-1]
            out[s] = {
                'symbol': s,
                'timestamp': last[0],
                'datetime': None,
                'high': last[2],
                'low': last[3],
                'bid': last[4],
                'ask': last[4],
                'vwap': None,
                'open': last[1],
                'close': last[4],
                'last': last[4],
                'previousClose': None,
                'change': None,
                'percentage': None,
                'average': None,
                'baseVolume': last[5],
                'quoteVolume': None,
            }
        return out
    except Exception:
        return {}


async def fetch_my_trades(self, *args, **kwargs):
    # Flexible signature handling to avoid "multiple values for argument" errors
    try:
        symbol = None
        since = None
        limit = kwargs.get('limit', 50)
        params = kwargs.get('params', None)

        # Helper to test symbol-like values
        def _is_symbol_like(v):
            try:
                if isinstance(v, str) and "/" in v:
                    return True
                sv = str(v)
                return "/" in sv
            except Exception:
                return False

        # Search for a symbol-like candidate in positional args
        for a in args:
            try:
                if _is_symbol_like(a):
                    symbol = str(a)
                    break
            except Exception:
                continue

        # Keyword overrides
        if 'symbol' in kwargs and _is_symbol_like(kwargs.get('symbol')):
            symbol = str(kwargs.get('symbol'))
        if 'since' in kwargs:
            since = kwargs.get('since')
        if 'params' in kwargs:
            params = kwargs.get('params')

        trades = []
        # If we have a symbol-like argument, first check the internal trade buffer
        if symbol is not None:
            try:
                tb = getattr(self, "_stub_trade_buffer", None)
                if isinstance(tb, dict) and symbol in tb and tb[symbol]:
                    try:
                        buf_trades = list(tb.get(symbol, []))
                        # clear buffer entries after returning
                        try:
                            tb[symbol] = []
                        except Exception:
                            pass
                        # ensure order fields exist
                        try:
                            for t in buf_trades:
                                if isinstance(t, dict):
                                    if 'order' not in t:
                                        t['order'] = None
                                    if 'orderId' not in t:
                                        t['orderId'] = None
                        except Exception:
                            pass
                        if _debug:
                            try:
                                print(f"stubex.fetch_my_trades: returning buffered trades for symbol={symbol} count={len(buf_trades)}")
                            except Exception:
                                pass
                        return buf_trades
                    except Exception:
                        pass
            except Exception:
                pass

            trades = await fetch_trades(self, symbol, since, limit, params)
            try:
                trades = list(trades) if trades is not None else []
            except Exception:
                pass
            # Ensure all returned trades have order/orderId keys (may be None)
            try:
                for t in trades:
                    try:
                        if isinstance(t, dict):
                            if 'order' not in t:
                                t['order'] = None
                            if 'orderId' not in t:
                                t['orderId'] = None
                    except Exception:
                        pass
            except Exception:
                pass
            # Attach pending order info as trades when present for this symbol
            try:
                ro = getattr(self, "_stub_recent_orders", None)
                if _debug:
                    try:
                        print(f"stubex.fetch_my_trades called: symbol={symbol} pending={ro}")
                    except Exception:
                        pass
                if isinstance(ro, dict) and symbol in ro and ro[symbol]:
                    if _debug:
                        try:
                            print(f"stubex.fetch_my_trades: attaching {len(ro[symbol])} pending orders for {symbol}")
                        except Exception:
                            pass
                    synths = []
                    for ordinfo in list(ro.get(symbol, [])):
                        # skip orders already returned
                        try:
                            if ordinfo.get('_returned'):
                                continue
                        except Exception:
                            pass
                        ts = _now_ms()
                        price = ordinfo.get("price") if ordinfo.get("price") is not None else (trades[0].get("price") if trades else 100.0)
                        amt = ordinfo.get("amount") if ordinfo.get("amount") is not None else 0.0
                        side = ordinfo.get("side", None)
                        # Ensure order id is a non-empty string to avoid None -> Julia Nothing conversions
                        o_id = ordinfo.get("id")
                        if o_id is None:
                            o_id = f"o{_now_ms()}"
                            try:
                                ordinfo['id'] = o_id
                            except Exception:
                                pass
                        o_str = str(o_id)
                        tr = {"id": f"t{ts}", "timestamp": ts, "datetime": None, "symbol": symbol, "price": round(float(price),8) if price is not None else None, "amount": amt, "side": side, "order": o_str, "orderId": o_str, "clientOrderId": o_str}
                        try:
                            synths.append(tr)
                        except Exception:
                            synths = synths + [tr]
                        if _debug:
                            try:
                                print(f"stubex.fetch_my_trades: synthesized trade for order={o_str} symbol={symbol} price={price} amt={amt}")
                            except Exception:
                                pass
                        try:
                            ordinfo['_returned'] = True
                        except Exception:
                            pass
                    # Return only synthesized trades for pending orders to ensure order ids are present
                    return synths
            except Exception:
                pass
            return trades

        # No symbol-like argument found. Attempt to attach pending orders across all known symbols
        try:
            # First, check for any buffered trades produced during create_order
            tb = getattr(self, "_stub_trade_buffer", None)
            if isinstance(tb, dict):
                buf_out = []
                for sym, lst in list(tb.items()):
                    if not lst:
                        continue
                    for t in list(lst):
                        buf_out.append(t)
                    # clear per-symbol buffer
                    try:
                        tb[sym] = []
                    except Exception:
                        pass
                if buf_out:
                    if _debug:
                        try:
                            print(f"stubex.fetch_my_trades: returning buffered aggregated trades for symbols={list(tb.keys())}")
                        except Exception:
                            pass
                    return buf_out
        except Exception:
            pass
        try:
            ro = getattr(self, "_stub_recent_orders", None)
            if isinstance(ro, dict) and ro:
                out_trades = []
                # For each symbol with pending orders, only return synthesized trades (with order ids)
                for sym, lst in list(ro.items()):
                    if not lst:
                        continue
                    synths = []
                    for ordinfo in list(lst):
                        # skip orders already returned
                        try:
                            if ordinfo.get('_returned'):
                                continue
                        except Exception:
                            pass
                        ts = _now_ms()
                        # try to get a sensible price
                        price = ordinfo.get("price") if ordinfo.get("price") is not None else None
                        if price is None:
                            try:
                                sample_trades = utils.generate_trades(sym, 1) or []
                                price = sample_trades[0].get("price") if sample_trades else 100.0
                            except Exception:
                                price = 100.0
                        amt = ordinfo.get("amount") if ordinfo.get("amount") is not None else 0.0
                        side = ordinfo.get("side", None)
                        o_id = ordinfo.get("id")
                        if o_id is None:
                            o_id = f"o{_now_ms()}"
                            try:
                                ordinfo['id'] = o_id
                            except Exception:
                                pass
                        o_str = str(o_id)
                        tr = {"id": f"t{ts}", "timestamp": ts, "datetime": None, "symbol": sym, "price": round(float(price),8) if price is not None else None, "amount": amt, "side": side, "order": o_str, "orderId": o_str, "clientOrderId": o_str}
                        try:
                            synths.append(tr)
                        except Exception:
                            synths = synths + [tr]
                        if _debug:
                            try:
                                print(f"stubex.fetch_my_trades: synthesized trade for order={o_str} symbol={sym} price={price} amt={amt}")
                            except Exception:
                                pass
                        try:
                            ordinfo['_returned'] = True
                        except Exception:
                            pass
                    out_trades.extend(synths)
                if _debug:
                    try:
                        print(f"stubex.fetch_my_trades: returning aggregated trades for symbols={list(ro.keys())}")
                    except Exception:
                        pass
                return out_trades
        except Exception:
            pass

        # As a last resort, see if any positional arg has a 'symbol' attribute we can use
        try:
            for a in args:
                try:
                    maybe_sym = getattr(a, "symbol", None)
                    if _is_symbol_like(maybe_sym):
                        trades = await fetch_trades(self, str(maybe_sym), since, limit, params)
                        try:
                            tlist = list(trades) if trades is not None else []
                        except Exception:
                            tlist = trades or []
                        # ensure order/orderId keys exist
                        try:
                            for t in tlist:
                                try:
                                    if isinstance(t, dict):
                                        if 'order' not in t:
                                            t['order'] = None
                                        if 'orderId' not in t:
                                            t['orderId'] = None
                                except Exception:
                                    pass
                        except Exception:
                            pass
                        return tlist
                except Exception:
                    continue
        except Exception:
            pass

        return []
    except Exception:
        return []


async def fetch_balance(self, *args, **kwargs):
    # Accept flexible args/kwargs from Julia wrappers (which may pass context params)
    try:
        # ccxt API: fetch_balance(params=None)
        # Some callers may pass positional context args; ignore them and use params if provided
        params = None
        if len(args) > 0:
            # If first arg is a dict-like params, treat it as params
            params = args[0]
        if 'params' in kwargs:
            params = kwargs.get('params')
        return utils.generate_balance(self, params)
    except Exception:
        return utils.generate_balance(self, None)


async def fetch_currencies(self, *args, **kwargs):
    try:
        # If exchange already has a currencies mapping, prefer and return it
        if hasattr(self, 'currencies') and isinstance(self.currencies, dict) and self.currencies:
            return self.currencies
        # Attempt to derive currency codes from known symbols
        syms = []
        try:
            if hasattr(self, 'symbols') and self.symbols:
                syms = list(self.symbols)
        except Exception:
            syms = []
        codes = set()
        for s in syms:
            try:
                if isinstance(s, str) and '/' in s:
                    base, quote = s.split('/', 1)
                    if ':' in quote:
                        quote = quote.split(':')[0]
                    codes.add(base)
                    codes.add(quote)
                else:
                    codes.add(str(s))
            except Exception:
                pass
        if not codes:
            for c in ['BTC','USD','USDT','ETH','SOL']:
                codes.add(c)
        out = {}
        for c in codes:
            out[c] = {
                'id': c,
                'code': c,
                'name': c,
                'precision': 8,
                'active': True,
                'type': 'crypto',
                'fee': 0.0,
                'limits': {'amount': {'min': 0.0, 'max': None}, 'withdraw': {'min': 0.0, 'max': None}}
            }
        return out
    except Exception:
        return {}


async def create_order(self, *args, **kwargs):
    # Robustly handle multiple calling conventions (sometimes `self` appears in args)
    try:
        off = 0
        if len(args) > 0:
            a0 = args[0]
            try:
                # ccxt exchange instances expose an `id` and `has` attribute
                if hasattr(a0, "id") and hasattr(a0, "has"):
                    off = 1
            except Exception:
                pass
        if _debug:
            try:
                print(f"stubex.create_order called: args_len={len(args)} off={off} a0_repr={repr(args[0]) if len(args)>0 else None}")
                try:
                    print("  args:", args)
                except Exception:
                    pass
                try:
                    print("  kwargs:", kwargs)
                except Exception:
                    pass
                try:
                    print("  price_kw:", kwargs.get('price', None), " amount_kw:", kwargs.get('amount', None), " params_kw:", kwargs.get('params', None))
                except Exception:
                    pass
            except Exception:
                pass
        symbol = args[off] if len(args) > off else kwargs.get('symbol', None)
        order_type = args[off + 1] if len(args) > off + 1 else kwargs.get('type', kwargs.get('order_type', None))
        side = args[off + 2] if len(args) > off + 2 else kwargs.get('side', None)
        amount = args[off + 3] if len(args) > off + 3 else kwargs.get('amount', None)
        price = args[off + 4] if len(args) > off + 4 else kwargs.get('price', None)

        # Prefer a plain string symbol for deterministic behaviour
        try:
            symbol_str = str(symbol) if symbol is not None else None
            # If symbol looks like an exchange object, drop it
            if symbol_str is not None and (symbol_str.startswith("<") or ("ccxt" in symbol_str and "exchange" in symbol_str)):
                symbol_str = None
        except Exception:
            symbol_str = None

        ord = utils.generate_order(symbol_str or None, order_type=str(order_type) if order_type is not None else None)

        # Honor requested amount when provided
        if amount is not None:
            try:
                ord['amount'] = float(amount)
            except Exception:
                ord['amount'] = amount

        # Try to determine a sensible price when none provided: prefer explicit price, then last market price
        last_price = None
        try:
            if symbol_str:
                ohlcv = utils.generate_ohlcv(symbol_str, None, 1, 1)
                if ohlcv:
                    last_price = float(ohlcv[-1][4])
        except Exception:
            last_price = None

        # Normalize provided price (if any); if missing, prefer last_price
        price_provided = None
        if price is not None:
            try:
                price_provided = float(price)
            except Exception:
                price_provided = price

        # Heuristic: attempt to recover price from kwargs['params'] or positional numeric args
        if price_provided is None:
            try:
                pparams = kwargs.get('params', None)
                if isinstance(pparams, dict) and pparams:
                    pv = pparams.get('price', None) or pparams.get('limit_price', None) or pparams.get('price_limit', None)
                    if pv is not None:
                        try:
                            price_provided = float(pv)
                        except Exception:
                            price_provided = pv
            except Exception:
                pass
        if price_provided is None:
            # scan positional args for numeric candidates (amount, price)
            try:
                numeric_args = []
                for a in args:
                    try:
                        # attempt float conversion for any numeric-like object
                        numeric_args.append(float(a))
                    except Exception:
                        # fallback: if arg is iterable, try to extract numeric-like members
                        try:
                            if isinstance(a, (list, tuple)) and len(a) > 0:
                                for e in a:
                                    try:
                                        numeric_args.append(float(e))
                                    except Exception:
                                        pass
                        except Exception:
                            pass
                if len(numeric_args) >= 2:
                    # assume last numeric is price, previous is amount
                    if ord.get('amount', None) is None:
                        try:
                            ord['amount'] = numeric_args[-2]
                        except Exception:
                            pass
                    price_provided = numeric_args[-1]
            except Exception:
                pass

        price_to_use = price_provided if price_provided is not None else (last_price if last_price is not None else ord.get('price', None))
        if price_to_use is not None:
            try:
                ord['price'] = float(price_to_use)
            except Exception:
                ord['price'] = price_to_use

        ord_amount = ord.get('amount', None)
        filled = 0.0
        trades = []
        cost = ord.get('cost', 0.0)
        average = ord.get('average', None)

        ot = str(order_type).lower() if order_type is not None else (str(ord.get('type', '')).lower() if ord.get('type') else '')
        side_str = str(side).lower() if side is not None else (str(ord.get('side', '')).lower() if ord.get('side') else '')

        # Determine last market price again if needed
        if last_price is None:
            try:
                if symbol_str:
                    ohlcv = utils.generate_ohlcv(symbol_str, None, 1, 1)
                    if ohlcv:
                        last_price = float(ohlcv[-1][4])
            except Exception:
                last_price = None

        # Use ord['price'] as the canonical price when available
        canonical_price = ord.get('price', last_price)

        if ot == 'market':
            try:
                filled = float(ord_amount) if ord_amount is not None else 0.0
            except Exception:
                filled = 0.0
            if filled > 0:
                ts = _now_ms()
                price_used = canonical_price if canonical_price is not None else 0.0
                trades = [{"id": f"t{ts}", "timestamp": ts, "datetime": None, "symbol": symbol_str, "price": price_used, "amount": filled, "side": side_str}]
                try:
                    cost = float(price_used) * filled
                except Exception:
                    cost = 0.0
                average = price_used
        elif ot == 'limit':
            # If price crosses last_price, consider immediate fill
            try:
                p = float(ord.get('price')) if ord.get('price') is not None else None
                if p is not None and last_price is not None:
                    if (side_str == 'sell' and p <= last_price) or (side_str == 'buy' and p >= last_price):
                        try:
                            filled = float(ord_amount) if ord_amount is not None else 0.0
                        except Exception:
                            filled = 0.0
                        if filled > 0:
                            ts = _now_ms()
                            trades = [{"id": f"t{ts}", "timestamp": ts, "datetime": None, "symbol": symbol_str, "price": p, "amount": filled, "side": side_str}]
                            try:
                                cost = float(p) * filled
                            except Exception:
                                cost = 0.0
                            average = p
            except Exception:
                pass

        ord['filled'] = filled
        try:
            ord['remaining'] = (ord_amount - filled) if (ord_amount is not None) else 0.0
        except Exception:
            ord['remaining'] = 0.0
        ord['status'] = 'closed' if filled > 0 else 'open'
        ord['trades'] = trades
        ord['cost'] = cost
        ord['average'] = average

        # Compute cost deterministically if filled but cost not set
        try:
            if ord.get('filled', 0) and not ord.get('cost'):
                price_for_cost = ord.get('average') or ord.get('price') or last_price
                if price_for_cost is not None:
                    try:
                        ord['cost'] = float(price_for_cost) * float(ord.get('filled', 0))
                    except Exception:
                        ord['cost'] = ord.get('cost', 0.0)
        except Exception:
            pass

        # Ensure symbol/type/side fields are plain values
        if symbol_str is not None:
            ord['symbol'] = symbol_str
        ord['type'] = order_type or ord.get('type', None)
        ord['side'] = side or ord.get('side', None)

        # Register recent orders (symbol -> list of order infos) so fetch_my_trades
        # can return matching trades referencing the order id. Register both open
        # and immediately-filled orders to ensure callers can discover trades.
        try:
            if symbol_str is not None:
                try:
                    ro = getattr(self, "_stub_recent_orders", None)
                    if ro is None:
                        self._stub_recent_orders = {}
                        ro = self._stub_recent_orders
                except Exception:
                    ro = getattr(self, "_stub_recent_orders", {})
                try:
                    lst = ro.get(symbol_str, [])
                    lst.append({"id": ord.get("id"), "price": ord.get("price"), "amount": ord.get("amount"), "side": ord.get("side")})
                    ro[symbol_str] = lst
                except Exception:
                    pass
                # initialize trade buffer for symbol and append immediate trades so watchers can pick them up
                try:
                    tb = getattr(self, "_stub_trade_buffer", None)
                    if tb is None:
                        self._stub_trade_buffer = {}
                        tb = self._stub_trade_buffer
                except Exception:
                    tb = getattr(self, "_stub_trade_buffer", {})
                try:
                    symbuf = tb.get(symbol_str, []) if isinstance(tb, dict) else []
                except Exception:
                    symbuf = []
                try:
                    if trades:
                        appended = []
                        for tr in trades:
                            try:
                                trd = dict(tr)
                            except Exception:
                                try:
                                    trd = dict(tr._asdict())
                                except Exception:
                                    trd = tr
                            try:
                                o_id = ord.get("id")
                                if o_id is None:
                                    o_id = f"o{_now_ms()}"
                                    ord['id'] = o_id
                                trd_order = trd.get('order') or trd.get('orderId') or str(o_id)
                                trd['order'] = trd_order
                                trd['orderId'] = trd.get('orderId') or trd_order
                                trd['clientOrderId'] = trd.get('clientOrderId') or trd_order
                            except Exception:
                                pass
                            appended.append(trd)
                        try:
                            sb = tb.get(symbol_str, [])
                            sb.extend(appended)
                            tb[symbol_str] = sb
                        except Exception:
                            try:
                                tb[symbol_str] = appended
                            except Exception:
                                pass
                except Exception:
                    pass
        except Exception:
            pass

        if _debug:
            try:
                print("stubex.create_order returning ord:", ord)
            except Exception:
                pass
        # If immediate trades were generated, allow a small window for watchers to process them
        try:
            if trades:
                time.sleep(0.02)
        except Exception:
            pass

        return ord
    except Exception:
        return utils.generate_order(None, order_type=None)


async def cancel_order(self, *args, **kwargs):
    try:
        id = args[0] if len(args) > 0 else kwargs.get('id', None)
        return {"id": id, "status": "canceled"}
    except Exception:
        return {"id": None, "status": "canceled"}


async def fetch_order_trades(self, *args, **kwargs):
    """Return trades associated with a specific order id.

    Flexible signature handling to interoperate with ccxt and Planar calls.
    Expected common signatures:
      - fetchOrderTrades(symbol, id, since=None, limit=None, params=None)
      - fetchOrderTrades(id, symbol=None)
      - fetch_order_trades(self, *args, **kwargs)
    """
    try:
        order_id = None
        symbol = None
        # kwargs first
        for k in ('id', 'orderId', 'order_id', 'order'):
            if k in kwargs and kwargs.get(k) is not None:
                order_id = kwargs.get(k)
                break
        # positional heuristics
        if order_id is None:
            if len(args) >= 2:
                # common: (symbol, id, ...)
                try:
                    cand_sym = args[0]
                    cand_id = args[1]
                    if isinstance(cand_sym, str) and "/" in cand_sym:
                        symbol = cand_sym
                        order_id = cand_id
                    else:
                        # maybe called (id,)
                        order_id = args[0]
                        if len(args) > 1:
                            symbol = args[1]
                except Exception:
                    order_id = args[0]
            elif len(args) == 1:
                order_id = args[0]
        # symbol kw override
        if 'symbol' in kwargs and kwargs.get('symbol') is not None:
            symbol = kwargs.get('symbol')
        try:
            order_str = str(order_id) if order_id is not None else None
        except Exception:
            order_str = order_id

        out = []
        # Search trade buffer first
        tb = getattr(self, "_stub_trade_buffer", None)
        if isinstance(tb, dict):
            if symbol is not None:
                try:
                    lst = tb.get(str(symbol), [])
                except Exception:
                    lst = []
                for t in list(lst):
                    try:
                        if (str(t.get('order')) == order_str) or (str(t.get('orderId')) == order_str) or (str(t.get('clientOrderId', '')) == order_str):
                            out.append(t)
                    except Exception:
                        pass
            else:
                for sym, lst in list(tb.items()):
                    for t in list(lst):
                        try:
                            if (str(t.get('order')) == order_str) or (str(t.get('orderId')) == order_str) or (str(t.get('clientOrderId', '')) == order_str):
                                out.append(t)
                        except Exception:
                            pass
        # If none found, synthesize from recent orders
        ro = getattr(self, "_stub_recent_orders", None)
        if (not out) and isinstance(ro, dict):
            # try symbol-specific first
            if symbol is not None and symbol in ro:
                for ordinfo in list(ro.get(symbol, [])):
                    try:
                        if str(ordinfo.get('id')) == order_str:
                            ts = _now_ms()
                            price = ordinfo.get('price') if ordinfo.get('price') is not None else 100.0
                            amt = ordinfo.get('amount') if ordinfo.get('amount') is not None else 0.0
                            side = ordinfo.get('side', None)
                            tr = {"id": f"t{ts}", "timestamp": ts, "datetime": None, "symbol": symbol, "price": round(float(price),8) if price is not None else None, "amount": amt, "side": side, "order": order_str, "orderId": order_str, "clientOrderId": order_str}
                            out.append(tr)
                    except Exception:
                        pass
            # fallback: search all symbols
            if not out:
                for sym, lst in list(ro.items()):
                    for ordinfo in list(lst):
                        try:
                            if str(ordinfo.get('id')) == order_str:
                                ts = _now_ms()
                                price = ordinfo.get('price') if ordinfo.get('price') is not None else 100.0
                                amt = ordinfo.get('amount') if ordinfo.get('amount') is not None else 0.0
                                side = ordinfo.get('side', None)
                                tr = {"id": f"t{ts}", "timestamp": ts, "datetime": None, "symbol": sym, "price": round(float(price),8) if price is not None else None, "amount": amt, "side": side, "order": order_str, "orderId": order_str, "clientOrderId": order_str}
                                out.append(tr)
                        except Exception:
                            pass
        return out
    except Exception:
        return []


async def fetch_orders(self, *args, **kwargs):
    # return an empty list by default
    return []


async def fetch_open_orders(self, *args, **kwargs):
    return []


async def fetch_positions(self, *args, **kwargs):
    # Accept flexible signature: (symbols=None, params=None) or positional args
    try:
        symbols = None
        if len(args) > 0:
            symbols = args[0]
        elif 'symbols' in kwargs:
            symbols = kwargs.get('symbols')
        if symbols is None:
            return []
        out = []
        try:
            # symbols may be a python list or tuple
            for s in symbols:
                out.append(_make_position(s, self))
        except Exception:
            try:
                out.append(_make_position(symbols, self))
            except Exception:
                pass
        return out
    except Exception:
        return []


# Some exchanges (e.g., binance) call load_leverage_brackets during position fetches.
# Provide a lightweight in-process implementation to avoid network calls while
# returning a plausible structure for leverage tiers and related helpers.
def load_leverage_brackets(self, reload=False, params=None):
    """Populate and return a per-symbol leverage brackets mapping.

    The structure is intentionally simple and deterministic so Planar's
    leverage_tiers() can parse and cache it. Stored on the instance as
    `_stub_leverage_brackets`.
    """
    try:
        if getattr(self, "_stub_leverage_brackets", None) is None:
            self._stub_leverage_brackets = {}
        try:
            syms = list(self.symbols) if hasattr(self, "symbols") and self.symbols else ["BTC/USDT:USDT", "ETH/USDT:USDT", "SOL/USDT:USDT"]
        except Exception:
            syms = ["BTC/USDT:USDT", "ETH/USDT:USDT", "SOL/USDT:USDT"]
        for s in syms:
            try:
                self._stub_leverage_brackets[s] = utils.generate_leverage_tiers(s)
            except Exception:
                self._stub_leverage_brackets[s] = []
        return self._stub_leverage_brackets
    except Exception:
        return None


def fetch_market_leverage_tiers(self, symbol, *args, **kwargs):
    """Return a list of leverage tier dicts for the given symbol.

    Matches the shape expected by Planar's leverage_tiers() caller.
    """
    try:
        return utils.generate_leverage_tiers(symbol)
    except Exception:
        return []


def set_leverage(self, lev, symbol, *args, **kwargs):
    """Set stub leverage for a symbol. Returns True on success.

    Accepts string or numeric leverage values; stored on the instance so
    fetchLeverage can return it later.
    """
    try:
        sval = str(lev)
        val = float(sval)
    except Exception:
        try:
            val = float(lev)
        except Exception:
            val = 1.0
    try:
        if getattr(self, "_stub_leverage_map", None) is None:
            self._stub_leverage_map = {}
        self._stub_leverage_map[str(symbol)] = {"longLeverage": float(val), "shortLeverage": float(val)}
    except Exception:
        pass
    return True


def fetch_leverage(self, symbol, *args, **kwargs):
    """Return the current stubbed leverage for `symbol` or a sensible default."""
    try:
        m = getattr(self, "_stub_leverage_map", None)
        key = str(symbol)
        if isinstance(m, dict) and key in m:
            return m[key]
        # fallback default
        return {"longLeverage": 3.0, "shortLeverage": 3.0}
    except Exception:
        return {"longLeverage": 1.0, "shortLeverage": 1.0}


def fetch_funding_rate(self, symbol, *args, **kwargs):
    """Return a single funding-rate-like dict for a symbol."""
    try:
        s = str(symbol)
        return utils.generate_funding_rate(s, self)
    except Exception:
        return {"symbol": symbol, "fundingRate": 0.0, "nextFundingTime": _now_ms() + 8 * 60 * 60 * 1000}


def fetch_funding_rates(self, *args, **kwargs):
    """Return a dict of funding rates keyed by symbol."""
    try:
        syms = list(self.symbols) if hasattr(self, "symbols") and self.symbols else ["BTC/USDT:USDT", "ETH/USDT:USDT", "SOL/USDT:USDT"]
        out = {}
        for s in syms:
            try:
                out[s] = utils.generate_funding_rate(s, self)
            except Exception:
                out[s] = {"symbol": s, "fundingRate": 0.0, "nextFundingTime": _now_ms() + 8 * 60 * 60 * 1000}
        return out
    except Exception:
        return {}


def fetch_funding_rate_history(self, symbol, since=None, limit=None, params=None):
    """Return a list of historical funding-rate rows for `symbol`.

    Each row is a dict with keys: timestamp (ms), symbol, fundingRate.
    The implementation is deterministic and spaced at 8-hour intervals to
    match Planar's FUNDING_PERIOD semantics.
    """
    try:
        s = str(symbol)
        now_ms = _now_ms()
        period_ms = 8 * 60 * 60 * 1000
        # Choose a conservative default limit
        lim = int(limit) if limit is not None else 100
        # If since provided, interpret negative values as offsets from now
        if since is None:
            timestamps = [now_ms - i * period_ms for i in range(lim)]
        else:
            try:
                since_int = int(since)
            except Exception:
                since_int = 0
            if since_int < 0:
                start_ms = now_ms + since_int
            else:
                start_ms = since_int
            if start_ms >= now_ms:
                timestamps = [now_ms]
            else:
                # build ascending series from start_ms to now_ms
                count = int(((now_ms - start_ms) // period_ms) + 1)
                count = min(count, lim) if lim is not None else count
                timestamps = [start_ms + i * period_ms for i in range(count)]
        # Use deterministic RNG per-symbol/exchange so results are stable
        r = utils.deterministic_random((s, getattr(self, "id", "")))
        out = []
        # return most-recent-first to match typical exchange APIs
        for ts in reversed(timestamps):
            rate = (r.random() - 0.5) * 0.001
            out.append({"timestamp": int(ts), "symbol": s, "fundingRate": round(rate, 8)})
        return out
    except Exception:
        return []

# ccxt.pro uses load_positions_snapshot to initialize position snapshots in the background.
# Patch it to a no-op in stub mode to avoid background coroutines that may call network
# functions such as sign()/fetch2() and raise NotSupported.
async def load_positions_snapshot(self, *args, **kwargs):
    return []

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
        try:
            ex_id = getattr(exchange, 'id', None)
        except Exception:
            ex_id = None
        print(f"stubex: patch_exchange called for exchange id={ex_id}")
        # Initialize internal buffers used by the stub to transport synthetic events to callers
        try:
            tb = getattr(exchange, "_stub_trade_buffer", None)
            if tb is None:
                exchange._stub_trade_buffer = {}
        except Exception:
            pass
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

        async def watch_positions(self, *args, **kwargs):
            try:
                symbols = None
                if len(args) > 0:
                    symbols = args[0]
                elif 'symbols' in kwargs:
                    symbols = kwargs.get('symbols')
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
            except Exception:
                return []

        async def watch_order_book(self, symbol, limit=None, params=None):
            depth = limit if limit is not None else 20
            return utils.generate_orderbook(symbol, depth)

        async def watch_trades(self, symbol, since=None, limit=50, params=None):
            lim = limit if limit is not None else 50
            return utils.generate_trades(symbol, lim)

        async def watch_my_trades(self, symbol, since=None, limit=50, params=None):
            # Prefer returning buffered trades for the symbol when available
            try:
                tb = getattr(self, "_stub_trade_buffer", None)
                if isinstance(tb, dict):
                    lst = tb.get(symbol, [])
                    if lst:
                        out = list(lst)
                        try:
                            tb[symbol] = []
                        except Exception:
                            pass
                        return out
            except Exception:
                pass

            # Synthesize trades from recent orders if present
            try:
                ro = getattr(self, "_stub_recent_orders", None)
                if isinstance(ro, dict) and symbol in ro and ro[symbol]:
                    synths = []
                    for ordinfo in list(ro.get(symbol, [])):
                        try:
                            if ordinfo.get('_returned'):
                                continue
                        except Exception:
                            pass
                        ts = _now_ms()
                        price = ordinfo.get('price') if ordinfo.get('price') is not None else None
                        if price is None:
                            try:
                                st = utils.generate_trades(symbol, 1)
                                price = st[0].get('price') if st else 100.0
                            except Exception:
                                price = 100.0
                        amt = ordinfo.get('amount') if ordinfo.get('amount') is not None else 0.0
                        side = ordinfo.get('side', None)
                        o_id = ordinfo.get('id')
                        if o_id is None:
                            o_id = f"o{_now_ms()}"
                            try:
                                ordinfo['id'] = o_id
                            except Exception:
                                pass
                        o_str = str(o_id)
                        tr = {"id": f"t{ts}", "timestamp": ts, "datetime": None, "symbol": symbol, "price": round(float(price), 8) if price is not None else None, "amount": amt, "side": side, "order": o_str, "orderId": o_str, "clientOrderId": o_str}
                        synths.append(tr)
                        try:
                            ordinfo['_returned'] = True
                        except Exception:
                            pass
                    if synths:
                        return synths
            except Exception:
                pass

            # no trades available right now - sleep briefly to yield to event loop and return empty list
            await asyncio.sleep(0.05)
            return []

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
            ("load_leverage_brackets", load_leverage_brackets),
            ("loadLeverageBrackets", load_leverage_brackets),
            ("fetchMarketLeverageTiers", fetch_market_leverage_tiers),
            ("fetch_market_leverage_tiers", fetch_market_leverage_tiers),
            ("setLeverage", set_leverage),
            ("set_leverage", set_leverage),
            ("fetchLeverage", fetch_leverage),
            ("fetch_leverage", fetch_leverage),
            ("load_positions_snapshot", load_positions_snapshot),
            ("loadPositionsSnapshot", load_positions_snapshot),
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
            ("fetchFundingRate", fetch_funding_rate),
            ("fetch_funding_rate", fetch_funding_rate),
            ("fetchFundingRates", fetch_funding_rates),
            ("fetch_funding_rates", fetch_funding_rates),
            ("fetchFundingRateHistory", fetch_funding_rate_history),
            ("fetch_funding_rate_history", fetch_funding_rate_history),
            ("loadMarkets", fetch_orders),
        ]

        # Bind all mappings
        for (nm, fn) in mappings:
            try:
                _bind(exchange, nm, fn)
            except Exception:
                # ignore
                pass

        # Ensure fetch_tickers mapping is available (some code calls fetchTickers/fetch_tickers)
        try:
            _bind(exchange, "fetch_tickers", fetch_tickers)
            _bind(exchange, "fetchTickers", fetch_tickers)
            _bind(exchange, "fetch_currencies", fetch_currencies)
            _bind(exchange, "fetchCurrencies", fetch_currencies)
        except Exception:
            pass

        # Also try patching the exchange class to override methods implemented as descriptors
        try:
            ex_cls = type(exchange)
            for (nm, fn) in mappings:
                try:
                    setattr(ex_cls, nm, fn)
                except Exception:
                    pass
            try:
                setattr(ex_cls, "fetch_tickers", fetch_tickers)
                setattr(ex_cls, "fetchTickers", fetch_tickers)
                setattr(ex_cls, "fetch_currencies", fetch_currencies)
                setattr(ex_cls, "fetchCurrencies", fetch_currencies)
            except Exception:
                pass
        except Exception:
            pass

        # Provide a minimal async loadMarkets implementation to avoid network calls
        def _load_markets(self, reload=False):
            # minimal markets expected by Planar's loadmarkets! flow
            try:
                self.markets = {}
                self.markets_by_id = {}
                # prefer an existing symbols list if present, otherwise fall back to common test symbols
                try:
                    syms = list(self.symbols) if hasattr(self, 'symbols') and self.symbols else ["BTC/USDT:USDT", "ETH/USDT:USDT", "SOL/USDT:USDT"]
                except Exception:
                    syms = ["BTC/USDT:USDT", "ETH/USDT:USDT", "SOL/USDT:USDT"]
                # recreate symbols list and populate minimal market metadata
                self.symbols = []
                for s in syms:
                    try:
                        sym = str(s)
                    except Exception:
                        sym = s
                    base = None
                    quote = None
                    if isinstance(sym, str) and '/' in sym:
                        parts = sym.split('/', 1)
                        base = parts[0]
                        quote = parts[1]
                    else:
                        base = sym
                        quote = ""
                    # derive a sensible minimum price based on a tiny fraction of last price
                    last_price = None
                    try:
                        ohlcv = utils.generate_ohlcv(sym, None, 1, 1)
                        if ohlcv and len(ohlcv) > 0:
                            last_price = float(ohlcv[-1][4])
                    except Exception:
                        last_price = None
                    if last_price is None:
                        last_price = 100.0
                    # use a very small min price to avoid accidental clamping in consumers
                    min_price = max(1e-12, float(last_price) * 1e-6)
                    m = {
                        'id': sym,
                        'symbol': sym,
                        'base': base,
                        'quote': quote,
                        'type': 'spot',
                        'limits': {
                            'amount': {'min': 1e-8, 'max': None},
                            'price': {'min': min_price, 'max': None},
                            'cost': {'min': 1e-8, 'max': None},
                        },
                        'precision': {'amount': 8, 'price': 8},
                        'active': True,
                        'taker': 0.001,
                        'maker': 0.001,
                    }
                    self.markets[sym] = m
                    self.markets_by_id[sym] = m
                    try:
                        # ensure symbols is a plain python list
                        self.symbols.append(sym)
                    except Exception:
                        pass
                self.currencies = {}
            except Exception:
                pass
            return None

        _bind(exchange, "loadMarkets", _load_markets)
        _bind(exchange, "load_markets", _load_markets)

        # Immediately populate minimal markets to override any pre-existing data.
        try:
            # Clear existing markets to avoid mixing real exchange metadata with stub data
            try:
                exchange.markets = {}
            except Exception:
                pass
            try:
                exchange.markets_by_id = {}
            except Exception:
                pass
            try:
                syms = list(exchange.symbols) if hasattr(exchange, 'symbols') and exchange.symbols else ["BTC/USDT:USDT", "ETH/USDT:USDT", "SOL/USDT:USDT"]
            except Exception:
                syms = ["BTC/USDT:USDT", "ETH/USDT:USDT", "SOL/USDT:USDT"]
            exchange.symbols = []
            for s in syms:
                try:
                    sym = str(s)
                except Exception:
                    sym = s
                base = None
                quote = None
                if isinstance(sym, str) and '/' in sym:
                    parts = sym.split('/', 1)
                    base = parts[0]
                    quote = parts[1]
                else:
                    base = sym
                    quote = ""
                last_price = None
                try:
                    ohlcv = utils.generate_ohlcv(sym, None, 1, 1)
                    if ohlcv and len(ohlcv) > 0:
                        last_price = float(ohlcv[-1][4])
                except Exception:
                    last_price = None
                if last_price is None:
                    last_price = 100.0
                # Use a very small min price to avoid accidental clamping in consumers
                min_price = max(1e-12, float(last_price) * 1e-6)
                m = {
                    'id': sym,
                    'symbol': sym,
                    'base': base,
                    'quote': quote,
                    'type': 'spot',
                    'limits': {
                        'amount': {'min': 1e-8, 'max': None},
                        'price': {'min': min_price, 'max': None},
                        'cost': {'min': 1e-8, 'max': None},
                    },
                    'precision': {'amount': 8, 'price': 8},
                    'active': True,
                    'taker': 0.001,
                    'maker': 0.001,
                }
                try:
                    exchange.markets[sym] = m
                    exchange.markets_by_id[sym] = m
                except Exception:
                    pass
                try:
                    exchange.symbols.append(sym)
                except Exception:
                    pass
            try:
                exchange.currencies = {}
            except Exception:
                pass
        except Exception:
            pass

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
            from ccxt.base.errors import AuthenticationError, NotSupported, ExchangeNotAvailable, RequestTimeout, DDoSProtection

            def _make_wrapper(orig, nm):
                if asyncio.iscoroutinefunction(orig):
                    async def awrap(*args, **kwargs):
                        try:
                            return await orig(*args, **kwargs)
                        except Exception as e:
                            # On authentication, unsupported, network or unknown-symbol errors return fallback stub
                            try:
                                if isinstance(e, (AuthenticationError, NotSupported, ExchangeNotAvailable, RequestTimeout, DDoSProtection)) or e.__class__.__name__ in ('AuthenticationError','NotSupported','BadSymbol','ExchangeNotAvailable','RequestTimeout','DDoSProtection'):
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
                                if isinstance(e, (AuthenticationError, NotSupported, ExchangeNotAvailable, RequestTimeout, DDoSProtection, TypeError)) or e.__class__.__name__ in ('AuthenticationError','NotSupported','BadSymbol','ExchangeNotAvailable','RequestTimeout','DDoSProtection','TypeError'):
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

            # Some exchanges call `fetch_ticker` directly; ensure it's wrapped to return
            # fallback stub data (e.g., for unknown symbols) even when the mapping above
            # did not include it.
            try:
                orig_ft = getattr(exchange, 'fetch_ticker', None)
                if orig_ft is not None:
                    wrapper = _make_wrapper(orig_ft, 'fetch_ticker')
                    try:
                        bound = types.MethodType(wrapper, exchange)
                        setattr(exchange, 'fetch_ticker', bound)
                    except Exception:
                        try:
                            setattr(exchange, 'fetch_ticker', wrapper)
                        except Exception:
                            pass
            except Exception:
                pass
            try:
                orig_FT = getattr(exchange, 'fetchTicker', None)
                if orig_FT is not None:
                    wrapper = _make_wrapper(orig_FT, 'fetchTicker')
                    try:
                        bound = types.MethodType(wrapper, exchange)
                        setattr(exchange, 'fetchTicker', bound)
                    except Exception:
                        try:
                            setattr(exchange, 'fetchTicker', wrapper)
                        except Exception:
                            pass
            except Exception:
                pass
        except Exception:
            pass
        try:
            print(f"stubex: patch_exchange complete for exchange id={ex_id}")
        except Exception:
            pass
    except Exception:
        # swallow errors - patcher is best-effort
        pass


# Create a patched subclass instance when possible to ensure class-methods are overridden
def make_patched_instance(*args, **kwargs):
    """Instantiate a subclass of exc_cls that has stub methods attached at class level.

    Accept flexible calling conventions:
      - make_patched_instance(exc_cls)
      - make_patched_instance(exc_cls, params)
      - sp.make_patched_instance(self, exc_cls, params)  # bound method

    The function is intentionally permissive to interoperate with PythonCall/Julia bindings
    that may surface different calling conventions.
    """
    try:
        # Normalize inputs
        exc_cls = None
        params = None
        # prefer explicit kwargs
        if 'exc_cls' in kwargs:
            exc_cls = kwargs.get('exc_cls')
        if 'params' in kwargs:
            params = kwargs.get('params')
        # handle positional args
        if exc_cls is None:
            if len(args) == 0:
                raise TypeError("make_patched_instance requires exc_cls")
            elif len(args) == 1:
                exc_cls = args[0]
            else:
                # Common patterns: (exc_cls, params) or (self, exc_cls, params)
                # Heuristic: if first arg looks like a module/object (no __name__), assume it's bound and take last two
                if hasattr(args[0], '__name__') and isinstance(args[0], type):
                    # (exc_cls, params)
                    exc_cls = args[0]
                    params = args[1] if len(args) > 1 else None
                else:
                    # assume (self, exc_cls, params) -> take the last two
                    exc_cls = args[-2]
                    params = args[-1]
        # Proceed to create patched subclass
        cls_name = getattr(exc_cls, '__name__', 'PatchedExchange')
        Patched = type(f"Patched{cls_name}", (exc_cls,), {})
        mappings = [
            ("fetch_ohlcv", fetch_ohlcv),
            ("fetchOHLCV", fetch_ohlcv),
            ("fetch_order_book", fetch_order_book),
            ("fetchOrderBook", fetch_order_book),
            ("fetch_trades", fetch_trades),
            ("fetchTrades", fetch_trades),
            ("fetch_order_trades", fetch_order_trades),
            ("fetchOrderTrades", fetch_order_trades),
            ("fetchOrderTradesWs", fetch_order_trades),
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
            ("load_leverage_brackets", load_leverage_brackets),
            ("loadLeverageBrackets", load_leverage_brackets),
            ("fetchMarketLeverageTiers", fetch_market_leverage_tiers),
            ("fetch_market_leverage_tiers", fetch_market_leverage_tiers),
            ("setLeverage", set_leverage),
            ("set_leverage", set_leverage),
            ("fetchLeverage", fetch_leverage),
            ("fetch_leverage", fetch_leverage),
            ("load_positions_snapshot", load_positions_snapshot),
            ("loadPositionsSnapshot", load_positions_snapshot),
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
            ("fetchFundingRate", fetch_funding_rate),
            ("fetch_funding_rate", fetch_funding_rate),
            ("fetchFundingRates", fetch_funding_rates),
            ("fetch_funding_rates", fetch_funding_rates),
            ("fetchFundingRateHistory", fetch_funding_rate_history),
            ("fetch_funding_rate_history", fetch_funding_rate_history),
            ("loadMarkets", fetch_orders),
        ]
        for (nm, fn) in mappings:
            try:
                setattr(Patched, nm, fn)
            except Exception:
                pass
        try:
            setattr(Patched, "fetch_tickers", fetch_tickers)
            setattr(Patched, "fetchTickers", fetch_tickers)
            setattr(Patched, "fetch_currencies", fetch_currencies)
            setattr(Patched, "fetchCurrencies", fetch_currencies)
        except Exception:
            pass
        # instantiate
        try:
            inst = Patched() if params is None else Patched(params)
        except Exception:
            # try a dict/empty params fallback
            try:
                inst = Patched({}) if params is None else Patched(params)
            except Exception:
                # fallback to original class instantiation
                try:
                    inst = exc_cls() if params is None else exc_cls(params)
                except Exception:
                    # last resort: try creating with empty dict
                    inst = exc_cls({}) if params is None else exc_cls(params)
        # run instance-level patching as well
        try:
            patch_exchange(inst)
        except Exception:
            pass
        return inst
    except Exception:
        # fallback to normal instantiation and patching (best effort)
        try:
            inst = args[0]() if len(args) > 0 and len(args) == 1 and kwargs == {} else (args[0]() if len(args) > 0 else None)
        except Exception:
            try:
                inst = exc_cls() if 'exc_cls' in locals() else None
            except Exception:
                inst = None
        if inst is None:
            try:
                # try classic instantiation using kwargs
                inst = exc_cls() if 'exc_cls' in locals() else None
            except Exception:
                inst = None
        try:
            if inst is not None:
                patch_exchange(inst)
        except Exception:
            pass
        return inst
