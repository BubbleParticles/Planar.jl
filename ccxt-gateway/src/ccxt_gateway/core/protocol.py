"""ZeroMQ message protocol for ccxt-gateway."""

import json
import uuid
from typing import Any, Dict, Optional
from datetime import datetime


def create_request(
    method: str,
    params: Optional[Dict[str, Any]] = None,
    exchange_id: Optional[str] = None,
    api_key: Optional[str] = None,
    secret: Optional[str] = None,
    request_id: Optional[str] = None,
) -> bytes:
    """Create a request message."""
    message: Dict[str, Any] = {
        "id": request_id or str(uuid.uuid4()),
        "type": "request",
        "method": method,
        "params": params or {},
        "exchange_id": exchange_id,
        "api_key": api_key,
        "secret": secret,
        "timestamp": datetime.utcnow().isoformat(),
    }
    return json.dumps(message).encode("utf-8")


def create_response(
    request_id: str,
    result: Any = None,
    error: Optional[str] = None,
    error_code: Optional[str] = None,
) -> bytes:
    """Create a response message."""
    message: Dict[str, Any] = {
        "id": request_id,
        "type": "response",
        "result": result,
        "error": error,
        "error_code": error_code,
        "timestamp": datetime.utcnow().isoformat(),
    }
    return json.dumps(message).encode("utf-8")


def create_subprocess_ready(exchange_id: str, pid: int) -> bytes:
    """Message sent by subprocess when ready."""
    message: Dict[str, Any] = {
        "type": "subprocess_ready",
        "exchange_id": exchange_id,
        "pid": pid,
        "timestamp": datetime.utcnow().isoformat(),
    }
    return json.dumps(message).encode("utf-8")


def create_heartbeat() -> bytes:
    """Heartbeat message."""
    message: Dict[str, Any] = {
        "type": "heartbeat",
        "timestamp": datetime.utcnow().isoformat(),
    }
    return json.dumps(message).encode("utf-8")


def create_watch_update(subscription_id: str, data: Any) -> bytes:
    """Create a watch update message."""
    message: Dict[str, Any] = {
        "type": "watch_update",
        "subscription_id": subscription_id,
        "data": data,
        "timestamp": datetime.utcnow().isoformat(),
    }
    return json.dumps(message).encode("utf-8")


def parse_message(data: bytes) -> Dict[str, Any]:
    """Parse a message from bytes."""
    result: Any = json.loads(data.decode("utf-8"))
    return result if isinstance(result, dict) else {}


# Method mapping for CCXT
CCXT_PUBLIC_METHODS: frozenset[str] = frozenset([
    "fetch_markets",
    "fetch_currencies",
    "fetch_ticker",
    "fetch_tickers",
    "fetch_order_book",
    "fetch_trades",
    "fetch_ohlcv",
    "fetch_status",
])

CCXT_PRIVATE_METHODS: frozenset[str] = frozenset([
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
])

CCXT_WATCH_METHODS: frozenset[str] = frozenset([
    "watch_ticker",
    "watch_tickers",
    "watch_order_book",
    "watch_trades",
    "watch_ohlcv",
    "watch_balance",
    "watch_orders",
    "watch_my_trades",
])
