"""CCXT method mappings and helpers."""

from typing import Any, Dict, Optional

import ccxt.async_support as ccxt


def get_ccxt_method(exchange: Any, method_name: str) -> Optional[Any]:
    """Get a CCXT method by name."""
    if not hasattr(exchange, method_name):
        return None
    return getattr(exchange, method_name)


def is_public_method(method_name: str) -> bool:
    """Check if a method is a public CCXT method."""
    public_prefixes: frozenset[str] = frozenset(
        [
            "fetch_markets",
            "fetch_currencies",
            "fetch_ticker",
            "fetch_tickers",
            "fetch_order_book",
            "fetch_trades",
            "fetch_ohlcv",
            "fetch_status",
        ]
    )
    return any(method_name.startswith(prefix) for prefix in public_prefixes)


def is_private_method(method_name: str) -> bool:
    """Check if a method is a private CCXT method."""
    private_prefixes: frozenset[str] = frozenset(
        [
            "fetch_balance",
            "create_order",
            "cancel_order",
            "fetch_order",
            "fetch_orders",
            "fetch_open_orders",
            "fetch_closed_orders",
            "fetch_my_trades",
            "deposit",
            "withdraw",
            "transfer",
        ]
    )
    return any(method_name.startswith(prefix) for prefix in private_prefixes)


def is_watch_method(method_name: str) -> bool:
    """Check if a method is a watch (WebSocket) method."""
    return method_name.startswith("watch_")


def get_supported_methods(exchange_name: str) -> Dict[str, Any]:
    """Get all supported methods for an exchange."""
    try:
        exchange_class: Any = getattr(ccxt, exchange_name)
        # Create temporary instance to check has dict
        temp: Any = exchange_class({"enableRateLimit": True})
        return temp.has if hasattr(temp, "has") else {}
    except Exception:
        return {}
