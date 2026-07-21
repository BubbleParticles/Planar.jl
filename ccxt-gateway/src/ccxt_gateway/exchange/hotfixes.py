"""Exchange-specific hotfixes applied during exchange subprocess init.

Each hotfix is an async callable (exchange, exchange_id, exchange_name) -> None
registered via register_hotfix() for a specific exchange name.

Hotfixes run after load_markets() during _init_exchange.
"""

import logging
from typing import Any

from ccxt_gateway.exchange.subprocess import register_hotfix

logger: logging.Logger = logging.getLogger(__name__)


# ── Bybit: clock sync ────────────────────────────────────────────────

async def _bybit_clock_sync(exchange: Any, exchange_id: str, exchange_name: str) -> None:
    """Sync Bybit's server clock for accurate timestamps."""
    try:
        await exchange.load_time_difference()
    except Exception:
        logger.debug("Clock sync skipped for %s (fetch_time not supported)", exchange_name)

register_hotfix("bybit", _bybit_clock_sync)


# ── Phemex: WebSocket positions ───────────────────────────────────────
# Phemex's ccxt.pro raises NotSupported for watchPositions, even though
# position data (positions_p) arrives via the same private WebSocket
# channel used by watchOrders/watchBalance.  This hotfix patches
# handle_message to capture positions_p and wires up a working
# watchPositions.

async def _phemex_websocket_hotfix(exchange: Any, exchange_id: str, exchange_name: str) -> None:
    """Override Phemex WebSocket to support watchPositions via positions_p messages."""

    _orig_handle = exchange.handle_message

    def _patched_handle(client: Any, message: dict) -> None:
        """Intercept positions_p messages and resolve the 'positions:' future."""
        # Perpetual position updates come as 'positions_p' (top-level key)
        pos_p = message.get("positions_p")
        if pos_p is not None:
            client.resolve(pos_p, "positions:")
        # Swap position updates come as 'positions' inside compound messages
        positions = message.get("positions")
        if positions is not None and "positions_p" not in message:
            client.resolve({"positions": positions}, "positions:")
        _orig_handle(client, message)

    exchange.handle_message = _patched_handle

    async def _watch_positions(
        symbols: Any = None,
        since: Any = None,
        limit: Any = None,
        params: Any = None,
    ) -> Any:
        """Watch positions via WebSocket by subscribing to the private feed."""
        if params is None:
            params = {}
        await exchange.load_markets()
        await exchange.authenticate()
        url = exchange.urls["api"]["ws"]
        request_id = exchange.seconds()
        settle = exchange.safe_string(params, "settle", "")
        settle_is_usdt = settle == "USDT"
        channel = "aop_p.subscribe" if settle_is_usdt else "aop.subscribe"
        request = {"id": request_id, "method": channel, "params": []}
        request = exchange.extend(request, exchange.omit(params, "settle"))
        return await exchange.watch(url, "positions:", request, channel)

    exchange.watchPositions = _watch_positions
    exchange.watch_positions = _watch_positions


register_hotfix("phemex", _phemex_websocket_hotfix)
