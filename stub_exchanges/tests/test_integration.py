"""Integration test mimicking Julia's workflow."""
import sys
sys.path.insert(0, 'stubex')
sys.path.insert(0, '.')

import asyncio
from stubex.patch import patch_exchange, make_patched_instance
import ccxt


def test_market_loading():
    """Test market loading."""
    print("\n=== Testing Market Loading ===")

    # Test 1: Using make_patched_instance
    print("\n1. Testing make_patched_instance:")
    ex = make_patched_instance('binance')
    print(f"   Exchange type: {type(ex)}")

    if ex is None:
        print("   ✗ make_patched_instance returned None")
    else:
        print(f"   Exchange created: {type(ex).__name__}")

        # Try loading markets
        try:
            ex.load_markets()
            print("   ✓ load_markets() called")

            # Check attributes
            print(f"   markets type: {type(ex.markets)}")
            print(f"   markets count: {len(ex.markets) if ex.markets else 0}")
            print(f"   symbols type: {type(ex.symbols)}")
            print(f"   symbols count: {len(ex.symbols) if ex.symbols else 0}")

            if ex.symbols:
                print(f"   First few symbols: {ex.symbols[:5]}")

        except Exception as e:
            print(f"   ✗ Error loading markets: {type(e).__name__}: {e}")

    # Test 2: Using patch_exchange directly
    print("\n2. Testing patch_exchange:")
    ex2 = ccxt.binance()
    print(f"   Before patch: {type(ex2).__name__}")

    try:
        patch_exchange(ex2)
        print("   ✓ patch_exchange() called")

        # Check attributes after patch
        print(f"   markets type: {type(ex2.markets)}")
        print(f"   markets count: {len(ex2.markets) if ex2.markets else 0}")

    except Exception as e:
        print(f"   ✗ Error in patch_exchange: {type(e).__name__}: {e}")
        import traceback
        traceback.print_exc()


def test_ticker_fetching():
    """Test ticker fetching."""
    print("\n=== Testing Ticker Fetching ===")

    # Using patch_exchange
    ex = ccxt.binance()
    patch_exchange(ex)

    # First load markets if needed
    print("\n1. Loading markets...")
    try:
        ex.load_markets()
        print(f"   ✓ Markets loaded: {len(ex.markets)} symbols")
    except Exception as e:
        print(f"   ✗ Error: {type(e).__name__}: {e}")

    # Now try fetching ticker
    print("\n2. Fetching ticker for BTC/USDT:")
    try:
        # Try sync call first
        ticker = ex.fetchTicker('BTC/USDT')
        print(f"   ✓ fetchTicker result type: {type(ticker)}")
        print(f"   Keys: {list(ticker.keys())[:10]}...")

        if isinstance(ticker, dict):
            print(f"   last: {ticker.get('last')}")
            print(f"   bid: {ticker.get('bid')}")
            print(f"   ask: {ticker.get('ask')}")

    except Exception as e:
        print(f"   ✗ Error: {type(e).__name__}: {e}")
        import traceback
        traceback.print_exc()

    # Try async call
    print("\n3. Fetching ticker (async):")
    try:
        async def fetch():
            return await ex.fetch_ticker('ETH/USDT')

        ticker = asyncio.run(fetch())
        print(f"   ✓ async fetch_ticker result type: {type(ticker)}")

    except Exception as e:
        print(f"   ✗ Error: {type(e).__name__}: {e}")


def test_orderbook():
    """Test orderbook fetching."""
    print("\n=== Testing Orderbook ===")

    ex = ccxt.binance()
    patch_exchange(ex)

    # Load markets
    try:
        ex.load_markets()
    except:
        pass

    print("\n1. Fetching orderbook:")
    try:
        ob = ex.fetch_order_book('BTC/USDT', 10)
        print(f"   ✓ Result type: {type(ob)}")
        print(f"   Keys: {list(ob.keys())}")
        print(f"   Bids count: {len(ob.get('bids', []))}")
        print(f"   Asks count: {len(ob.get('asks', []))}")

        if ob.get('bids'):
            print(f"   First bid: {ob['bids'][0]}")

    except Exception as e:
        print(f"   ✗ Error: {type(e).__name__}: {e}")
        import traceback
        traceback.print_exc()


def test_full_workflow():
    """Test complete paper trading workflow."""
    print("\n=== Testing Full Workflow ===")

    ex = ccxt.binance()
    patch_exchange(ex)

    # 1. Load markets
    print("\n1. Loading markets...")
    try:
        ex.load_markets()
        print(f"   ✓ {len(ex.symbols)} symbols loaded")
    except Exception as e:
        print(f"   ✗ Error: {type(e).__name__}: {e}")
        return

    # 2. Get ticker
    print("\n2. Getting ticker...")
    try:
        ticker = ex.fetchTicker('ETH/USDT')
        price = ticker.get('last', 0)
        print(f"   ✓ ETH/USDT price: {price}")
    except Exception as e:
        print(f"   ✗ Error: {type(e).__name__}: {e}")
        # Continue anyway

    # 3. Get orderbook
    print("\n3. Getting orderbook...")
    try:
        ob = ex.fetch_order_book('ETH/USDT', 10)
        print(f"   ✓ bids: {len(ob.get('bids', []))}, asks: {len(ob.get('asks', []))}")
    except Exception as e:
        print(f"   ✗ Error: {type(e).__name__}: {e}")

    # 4. Create order
    print("\n4. Creating market order...")
    try:
        order = ex.create_order('ETH/USDT', 'market', 'buy', 0.01)
        print(f"   ✓ Order created: {order.get('id')}")
    except Exception as e:
        print(f"   ✗ Error: {type(e).__name__}: {e}")
        import traceback
        traceback.print_exc()


def compare_with_real_ccxt():
    """Compare stub vs real ccxt market structure."""
    print("\n=== Comparing with Real CCXT ===")

    # Stub first
    print("\n1. Stub exchange:")
    stub = ccxt.binance()
    patch_exchange(stub)

    try:
        stub.load_markets()
        print(f"   markets type: {type(stub.markets)}")
        print(f"   symbols count: {len(stub.symbols) if stub.symbols else 0}")

        if stub.symbols:
            print(f"   Symbols: {stub.symbols}")
        else:
            print(f"   No symbols!")

        if stub.markets:
            print(f"   Market keys: {list(stub.markets.keys())}")

            for sym, m in stub.markets.items():
                print(f"   {sym}: {list(m.keys())}")
                break

    except Exception as e:
        print(f"   ✗ Error: {type(e).__name__}: {e}")
        import traceback
        traceback.print_exc()


if __name__ == '__main__':
    test_market_loading()
    compare_with_real_ccxt()
    test_ticker_fetching()
    test_orderbook()
    test_full_workflow()
    print("\n" + "="*50)
    print("Integration tests complete!")
