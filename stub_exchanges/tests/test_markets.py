import asyncio
import ccxt
import pytest

from stub_exchanges.stubex import patch


async def _make_inst():
    # pick a known exchange class from ccxt.exchanges
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

    # load markets if available
    lm = getattr(inst, 'loadMarkets', getattr(inst, 'load_markets', None))
    if lm is not None:
        if asyncio.iscoroutinefunction(lm):
            await lm()
        else:
            lm()
    return inst


@pytest.mark.asyncio
async def test_markets_min_price():
    inst = await _make_inst()
    assert hasattr(inst, 'markets'), "patched instance has no markets"
    markets = inst.markets
    assert markets, "markets mapping is empty"
    sym = next(iter(markets.keys()))
    min_price = markets[sym]['limits']['price']['min']
    # derive a reference last price using the stub utils and allow a small fraction
    from stub_exchanges.stubex import utils as stub_utils
    ohlcv = stub_utils.generate_ohlcv(sym, None, 1, 1)
    last_price = float(ohlcv[-1][4]) if ohlcv else 100.0
    assert float(min_price) <= max(1e-6, last_price * 1e-4), f"min_price too large: {min_price} (last={last_price})"
