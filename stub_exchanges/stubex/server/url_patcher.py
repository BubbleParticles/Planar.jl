"""Module to override ccxt exchange URLs to point to stub server.

This provides a function to create a patched ccxt exchange that uses
the stub server instead of the real exchange API.
"""

import ccxt


# Store for exchange class patches
_original_urls = {}


def patch_exchange_urls(exchange):
    """Patch an exchange to use stub server URLs.

    This modifies the exchange's API URLs to point to the local stub server
    while preserving most of ccxt's request/response logic.

    Args:
        exchange: A ccxt exchange instance

    Returns:
        The same exchange instance (modified in place)
    """
    stub_server = None
    try:
        from .server import get_stub_server
        stub_server = get_stub_server()
    except ImportError:
        from stubex.server import get_stub_server
        stub_server = get_stub_server()

    if stub_server is None:
        from .server import start_stub_server
        start_stub_server()
        stub_server = get_stub_server()

    stub_url = stub_server.url
    exchange_id = getattr(exchange, 'id', 'binance')

    # Determine URLs based on exchange type
    # Most exchanges use similar URL patterns
    base_urls = {
        'binance': {
            'public': {
                'spot': f'{stub_url}/api/v3',
                'swap': f'{stub_url}/fapi/v1',
                'future': f'{stub_url}/dapi/v1',
            },
            'private': {
                'spot': f'{stub_url}/api/v3',
                'swap': f'{stub_url}/fapi/v1',
                'future': f'{stub_url}/dapi/v1',
            },
            'eapi': f'{stub_url}/eapi/v1',
        },
        'default': {
            'public': f'{stub_url}/api/v3',
            'private': f'{stub_url}/api/v3',
        }
    }

    urls = base_urls.get(exchange_id, base_urls['default'])

    # Store original URLs for later restoration
    if exchange_id not in _original_urls:
        _original_urls[exchange_id] = {
            'api': getattr(exchange, 'api', None),
            'urls': getattr(exchange, 'urls', {}).copy() if hasattr(exchange, 'urls') else {},
        }

    # Patch the URLs
    if hasattr(exchange, 'urls'):
        # Handle different URL structures
        for key in ['public', 'private']:
            if key in urls:
                if isinstance(urls[key], dict):
                    for subkey in urls[key]:
                        try:
                            if subkey not in exchange.urls.get(key, {}):
                                continue
                            exchange.urls[key][subkey] = urls[key][subkey]
                        except (TypeError, KeyError):
                            pass
                else:
                    try:
                        for subkey in ['spot', 'swap', 'future']:
                            if subkey not in exchange.urls.get(key, {}):
                                continue
                            exchange.urls[key][subkey] = urls[key]
                    except (TypeError, KeyError):
                        pass

    return exchange


def patch_exchange_urls_for_class(exchange_class, stub_url):
    """Patch an exchange class to use stub server URLs.

    This modifies the exchange class's API URLs before instantiation.

    Args:
        exchange_class: A ccxt exchange class (e.g., ccxt.binance)
        stub_url: The URL of the stub server

    Returns:
        The same exchange class (modified in place)
    """
    exchange_id = getattr(exchange_class, 'id', None)
    if exchange_id is None:
        # Try to get id from class name
        exchange_id = exchange_class.__name__.lower()

    urls = {
        'public': f'{stub_url}/api/v3',
        'private': f'{stub_url}/api/v3',
    }

    # Store original
    if not hasattr(exchange_class, '_original_urls'):
        exchange_class._original_urls = getattr(exchange_class, 'urls', {}).copy()

    # Patch
    if hasattr(exchange_class, 'urls'):
        exchange_class.urls.update(urls)

    return exchange_class


def get_patched_exchange(exchange_name, stub_server_url=None):
    """Create a patched exchange instance that uses the stub server.

    Args:
        exchange_name: Name of the exchange (e.g., 'binance')
        stub_server_url: Optional URL for stub server

    Returns:
        A patched ccxt exchange instance
    """
    # Get or start stub server
    if stub_server_url is None:
        try:
            from stubex.server import start_stub_server, get_stub_server
            server = get_stub_server()
            if server is None:
                start_stub_server()
            stub_server_url = get_stub_server().url
        except ImportError:
            stub_server_url = "http://127.0.0.1:8765"

    # Create exchange instance
    try:
        exchange_class = getattr(ccxt, exchange_name)
        exchange = exchange_class()
    except (AttributeError, KeyError):
        raise ValueError(f"Unknown exchange: {exchange_name}")

    # Patch URLs
    patch_exchange_urls_for_class(exchange_class, stub_server_url)

    return exchange