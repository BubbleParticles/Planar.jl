import asyncio
import ccxt
import pytest
import os
import sys

# Ensure repository root is importable
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from stub_exchanges.stubex import patch


async def _make_inst():
    exch_name = None
    try:
        if 'binance' in ccxt.exchanges:
            exch_name = 'binance'
        elif ccxt.exchanges:
            exch_name = ccxt.exchanges[0]
    except Exception:
        pass
    assert exch_name is not None, "No exchanges available in ccxt"
    ex_cls = getattr(ccxt, exch_name)
    inst = patch.make_patched_instance(ex_cls)

    lm = getattr(inst, 'loadMarkets', getattr(inst, 'load_markets', None))
    if lm is not None:
        if asyncio.iscoroutinefunction(lm):
            await lm()
        else:
            lm()
    return inst


@pytest.mark.asyncio
async def test_fetch_order_trades_and_my_trades():
    inst = await _make_inst()
    sym = None
    # prefer a symbol from markets if present
    try:
        if hasattr(inst, 'markets') and inst.markets:
            sym = next(iter(inst.markets.keys()))
    except Exception:
        sym = None
    if sym is None:
        sym = 'BTC/USDT:USDT'

    # Create a limit order (stub may fill immediately)
    ord = await inst.createOrder(sym, 'limit', 'buy', 0.001, 100.0)
    order_id = ord.get('id')
    assert order_id is not None and str(order_id) != '', f"order id missing: {ord}"

    # Prefer canonical method name if available
    fetch_order_trades = getattr(inst, 'fetchOrderTrades', getattr(inst, 'fetch_order_trades', None))
    assert fetch_order_trades is not None, "patched instance has no fetchOrderTrades/fetch_order_trades"

    # try symbol+id, fallback to id,symbol or id-only
    trades_by_id = None
    try:
        trades_by_id = await fetch_order_trades(sym, order_id)
    except Exception:
        try:
            trades_by_id = await fetch_order_trades(order_id, sym)
        except Exception:
            trades_by_id = await fetch_order_trades(order_id)
    assert isinstance(trades_by_id, (list, tuple)), f"unexpected type: {type(trades_by_id)}"
    assert len(trades_by_id) > 0, "fetchOrderTrades returned empty"
    assert any(str(t.get('order') or t.get('orderId') or t.get('clientOrderId')) == str(order_id) for t in trades_by_id), "returned trades do not reference order id"

    # also try fetchMyTrades; accept either method returning the order-linked trade
    fetch_my = getattr(inst, 'fetchMyTrades', getattr(inst, 'fetch_my_trades', None))
    found_in_my = False
    if fetch_my is not None:
        try:
            my_trades = await fetch_my(sym)
            if isinstance(my_trades, (list, tuple)) and my_trades:
                found_in_my = any(str(t.get('order') or t.get('orderId') or t.get('clientOrderId')) == str(order_id) for t in my_trades)
        except Exception:
            found_in_my = False
    found_in_order_trades = any(str(t.get('order') or t.get('orderId') or t.get('clientOrderId')) == str(order_id) for t in trades_by_id)
    assert found_in_order_trades or found_in_my, "Neither fetchOrderTrades nor fetchMyTrades returned trades referencing the order id"
