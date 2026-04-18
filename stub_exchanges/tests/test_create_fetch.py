import asyncio
import ccxt

from stub_exchanges.stubex import patch

async def main():
    # pick a known exchange class from ccxt.exchanges
    exch_name = None
    try:
        if 'binance' in ccxt.exchanges:
            exch_name = 'binance'
        elif ccxt.exchanges:
            exch_name = ccxt.exchanges[0]
    except Exception:
        pass
    if exch_name is None:
        print("No exchanges available in ccxt")
        return
    ex_cls = getattr(ccxt, exch_name)
    inst = patch.make_patched_instance(ex_cls)

    # load markets if available
    try:
        lm = getattr(inst, 'loadMarkets', getattr(inst, 'load_markets', None))
        if lm is not None:
            if asyncio.iscoroutinefunction(lm):
                await lm()
            else:
                lm()
    except Exception:
        pass

    # create an order and ensure fetch_my_trades returns a trade referencing it
    ord = await inst.createOrder('BTC/USDT:USDT', 'limit', 'buy', 0.001, 100.0)
    trades = await inst.fetchMyTrades('BTC/USDT:USDT')
    order_id = ord.get('id')
    print("Order id:", order_id)
    print("Trades returned (first 5):", trades[:5])

    found = False
    for t in trades:
        o = t.get('order') or t.get('orderId') or t.get('clientOrderId')
        if o is not None and str(o) == str(order_id):
            found = True
            break

    if not found:
        raise AssertionError("Created order id not found in fetch_my_trades")
    else:
        print("OK: found matching trade for order id", order_id)

if __name__ == '__main__':
    asyncio.run(main())
