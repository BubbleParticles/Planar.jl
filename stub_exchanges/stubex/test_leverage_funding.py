import ccxt
import asyncio
from stub_exchanges.stubex import patch


def _instantiate():
    # pick a known exchange class from ccxt.exchanges
    ex_name = 'binance' if 'binance' in ccxt.exchanges else ccxt.exchanges[0]
    ex_cls = getattr(ccxt, ex_name)
    try:
        ex = ex_cls()
    except Exception:
        ex = ex_cls({})
    return ex


def test_leverage_tiers_and_funding_history_sync():
    ex = _instantiate()
    patch.patch_exchange(ex)
    syms = list(ex.symbols) if hasattr(ex, 'symbols') and ex.symbols else ['BTC/USDT:USDT']
    symbol = syms[0]

    tiers = ex.fetch_market_leverage_tiers(symbol)
    assert isinstance(tiers, list)
    assert len(tiers) >= 1
    assert 'tier' in tiers[0] and 'maxLeverage' in tiers[0]

    history = ex.fetch_funding_rate_history(symbol, limit=10)
    assert isinstance(history, list)
    if len(history) >= 2:
        period_ms = 8 * 60 * 60 * 1000
        # history is returned most-recent-first; differences should be ~period_ms
        assert abs(history[0]['timestamp'] - history[1]['timestamp'] - period_ms) <= 2000


def test_leverage_tiers_and_funding_history_async():
    ex = _instantiate()
    patch.patch_exchange(ex)
    syms = list(ex.symbols) if hasattr(ex, 'symbols') and ex.symbols else ['BTC/USDT:USDT']
    symbol = syms[0]

    async def run_async():
        # camelCase async variants may be coroutine functions
        if asyncio.iscoroutinefunction(getattr(ex, 'fetchMarketLeverageTiers', None)):
            tiers_async = await ex.fetchMarketLeverageTiers(symbol)
        else:
            tiers_async = ex.fetchMarketLeverageTiers(symbol)

        if asyncio.iscoroutinefunction(getattr(ex, 'fetchFundingRateHistory', None)):
            history_async = await ex.fetchFundingRateHistory(symbol, limit=5)
        else:
            history_async = ex.fetchFundingRateHistory(symbol, limit=5)
        return tiers_async, history_async

    tiers_async, history_async = asyncio.run(run_async())
    assert isinstance(tiers_async, list)
    assert isinstance(history_async, list)
