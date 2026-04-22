"""Create a ccxt exchange that uses the stub server.

This provides a simpler interface than patching every method - instead we
override the API URLs to point to a local stub server.
"""

import ccxt
import logging

from .server import start_stub_server, get_stub_server

logger = logging.getLogger(__name__)


# Exchange URL configurations for stub server - these get merged into existing URLs
STUB_URL_MERGES = {
    "binance": {
        "public": "http://127.0.0.1:8765",
        "private": "http://127.0.0.1:8765",
        "fapiPublic": "http://127.0.0.1:8765",
        "fapiPrivate": "http://127.0.0.1:8765",
        "dapiPublic": "http://127.0.0.1:8765",
        "dapiPrivate": "http://127.0.0.1:8765",
    },
    "bybit": {
        "public": "http://127.0.0.1:8765",
        "private": "http://127.0.0.1:8765",
    },
    "okx": {
        "public": "http://127.0.0.1:8765",
        "private": "http://127.0.0.1:8765",
    },
    "default": {
        "public": "http://127.0.0.1:8765",
        "private": "http://127.0.0.1:8765",
    },
}


def create_stub_exchange(exchange_name: str, **kwargs):
    """Create a ccxt exchange that uses the stub server.

    Args:
        exchange_name: Name of the exchange (e.g., 'binance', 'bybit')
        **kwargs: Additional arguments to pass to exchange constructor

    Returns:
        A ccxt exchange instance configured to use the stub server
    """
    # Ensure stub server is running BEFORE anything else
    try:
        server = get_stub_server()
        if server is None:
            start_stub_server()
            server = get_stub_server()
            if server:
                logger.info(f"Stub server started at {server.url}")
    except Exception as e:
        logger.warning(f"Could not start stub server: {e}")

    # Get exchange class
    try:
        exchange_class = getattr(ccxt, exchange_name.lower())
    except AttributeError:
        raise ValueError(f"Unknown exchange: {exchange_name}")

    # Create exchange instance - filter out unsupported kwargs
    try:
        exchange = exchange_class(**kwargs)
    except TypeError as e:
        if "unexpected keyword argument" in str(e):
            logger.warning(f"Failed to create exchange with params {kwargs}: {e}")
            exchange = exchange_class()
        else:
            raise

    # Get URL merges for this exchange
    url_merges = STUB_URL_MERGES.get(exchange_name.lower(), STUB_URL_MERGES["default"])

    # Patch URLs if the exchange supports it
    if hasattr(exchange, "urls") and "api" in exchange.urls:
        try:
            api_urls = exchange.urls["api"]
            for key, stub_prefix in url_merges.items():
                if key in api_urls:
                    original = api_urls[key]
                    if isinstance(original, str):
                        if "://" in original:
                            path_start = original.find("/", original.find("://") + 3)
                            if path_start > 0:
                                api_urls[key] = stub_prefix + original[path_start:]
        except Exception as e:
            logger.warning(f"Could not patch URLs for {exchange_name}: {e}")

    # Disable rate limiting
    if hasattr(exchange, "enableRateLimit"):
        exchange.enableRateLimit = False

    # Set dummy credentials
    if hasattr(exchange, "apiKey"):
        exchange.apiKey = "stub_api_key"
    if hasattr(exchange, "secret"):
        exchange.secret = "stub_secret"

    # Override check_required_credentials
    def stub_check_required_credentials(self, error=True):
        url = str(self.urls.get("api", {}))
        if "127.0.0.1:8765" in url or "localhost:8765" in url:
            return
        original_check(self, error)

    try:
        original_check = ccxt.Exchange.check_required_credentials
        ccxt.Exchange.check_required_credentials = stub_check_required_credentials
    except Exception as e:
        logger.warning(f"Could not patch credentials check: {e}")

    # Try to get markets from stub server BEFORE loading
    # The stub server will provide market data via exchangeInfo
    try:
        # Load markets from exchange (will hit our stub server's exchangeInfo endpoint)
        exchange.load_markets()
        # Ensure all markets have required fields that ccxt expects
        required_fields = {
            "option": None,
            "linear": None,
            "inverse": None,
            "spot": True,
            "margin": True,
            "swap": False,
            "future": False,
            "contract": False,
        }
        for sym, market in exchange.markets.items():
            for field, default in required_fields.items():
                if field not in market:
                    market[field] = default
    except Exception as e:
        logger.warning(f"Could not pre-populate markets: {e}")

    return exchange


def make_stub_instance(exchange_name_or_class):
    """Create a stub exchange instance from name or class.

    This is the main entry point called from Julia via PythonCall.

    Args:
        exchange_name_or_class: Exchange name string or ccxt class

    Returns:
        A ccxt exchange instance configured to use the stub server
    """
    # Handle string input
    if isinstance(exchange_name_or_class, str):
        exchange_name = exchange_name_or_class.lower()
        return create_stub_exchange(exchange_name)

    # Handle class input
    exchange_name = getattr(exchange_name_or_class, "id", None)
    if exchange_name is None:
        # Try to get from class name
        exchange_name = exchange_name_or_class.__name__.lower()

    try:
        exchange = exchange_name_or_class()
    except Exception:
        exchange = exchange_name_or_class({})

    return create_stub_exchange(exchange_name)


# Alias for backwards compatibility
def patch_exchange(exchange, exch_name=None):
    """Legacy function for compatibility.

    This just returns the exchange - the actual patching happens
    at creation time now.
    """
    return exchange
