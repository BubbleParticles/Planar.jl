"""Exchange subprocess that runs CCXT and communicates via ZeroMQ."""

import asyncio
import json
import logging
import os
import signal
import sys
from typing import Any, Callable, Dict, List, Optional

from ccxt_gateway.core.protocol import (
    create_response,
    create_subprocess_ready,
    create_watch_update,
    parse_message,
)

import zmq
import zmq.asyncio

logger: logging.Logger = logging.getLogger(__name__)

# ── Exchange hotfix registry ──────────────────────────────────────────
# Maps exchange names to lists of async callables (exchange, exchange_id, name) -> None.
# Registered fixes run during _init_exchange after markets are loaded.
_HOTFIXES: Dict[str, List[Callable]] = {}

def register_hotfix(exchange_name: str, fix: Callable) -> None:
    """Register a hotfix function for a specific exchange."""
    _HOTFIXES.setdefault(exchange_name, []).append(fix)

def get_hotfixes(exchange_name: str) -> List[Callable]:
    """Return all registered hotfixes for an exchange name."""
    return _HOTFIXES.get(exchange_name, [])


class ExchangeSubprocess:
    """Subprocess that handles CCXT calls for a specific exchange."""

    def __init__(
        self,
        exchange_id: str,
        exchange_name: str,
        broker_address: str = "tcp://127.0.0.1:5555",
        api_key: Optional[str] = None,
        secret: Optional[str] = None,
        password: Optional[str] = None,
        uid: Optional[str] = None,
        enable_rate_limit: bool = True,
        timeout: int = 30000,
        verbose: bool = False,
        sandbox: bool = False,
    ) -> None:
        self.exchange_id: str = exchange_id
        self.exchange_name: str = exchange_name
        self.broker_address: str = broker_address
        self.api_key: Optional[str] = api_key
        self.secret: Optional[str] = secret
        self.password: Optional[str] = password
        self.uid: Optional[str] = uid
        self.enable_rate_limit: bool = enable_rate_limit
        self.timeout: int = timeout
        self.verbose: bool = verbose
        self.sandbox: bool = sandbox
        self.parent_pid: int = os.getppid()

        self.context: zmq.asyncio.Context = zmq.asyncio.Context()
        self.socket: zmq.asyncio.Socket = self.context.socket(zmq.DEALER)
        self.socket.setsockopt(zmq.IDENTITY, exchange_id.encode("utf-8"))

        self.exchange: Any = None
        self.running: bool = False

        # Setup signal handlers
        signal.signal(signal.SIGTERM, self._signal_handler)
        signal.signal(signal.SIGINT, self._signal_handler)

    def _signal_handler(self, signum: int, frame: Any) -> None:
        """Handle shutdown signals."""
        logger.info("Received signal %d, shutting down...", signum)
        self.running = False

    async def start(self) -> None:
        """Start the subprocess."""
        self.running = True

        # Connect to broker
        self.socket.connect(self.broker_address)
        logger.info("Connected to broker at %s", self.broker_address)

        # Initialize CCXT exchange
        await self._init_exchange()

        # Send ready message
        await self._send_ready()

        # Main message loop
        await self._message_loop()

    async def _init_exchange(self) -> None:
        """Initialize the CCXT exchange instance."""
        try:
            import ccxt.async_support as ccxt

            if not hasattr(ccxt, self.exchange_name):
                raise ValueError(f"Exchange {self.exchange_name} not supported by CCXT")

            exchange_class: Any = getattr(ccxt, self.exchange_name)

            params: Dict[str, Any] = {
                "enableRateLimit": self.enable_rate_limit,
                "timeout": self.timeout,
                "verbose": self.verbose,
            }

            if self.api_key:
                params["apiKey"] = self.api_key
            if self.secret:
                params["secret"] = self.secret
            if self.password:
                params["password"] = self.password
            if self.uid:
                params["uid"] = self.uid

            self.exchange = exchange_class(params)
            logger.info("Initialized CCXT exchange: %s", self.exchange_name)

            # Enable sandbox mode if requested
            if self.sandbox:
                try:
                    self.exchange.set_sandbox_mode(True) if hasattr(self.exchange, 'set_sandbox_mode') else self.exchange.setSandboxMode(True)
                    logger.info("Sandbox mode enabled for %s", self.exchange_name)
                except Exception as se:
                    logger.warning("Failed to enable sandbox mode for %s: %s", self.exchange_name, se)

            # Pre-load markets so they're available immediately
            try:
                await self.exchange.load_markets()
                logger.info("Loaded %d markets for %s", len(self.exchange.markets), self.exchange_name)
            except Exception as me:
                logger.warning("Failed to pre-load markets for %s: %s", self.exchange_name, me)

            # Apply exchange-specific hotfixes (clock sync, WS overrides, etc.)
            for fix in get_hotfixes(self.exchange_name):
                try:
                    await fix(self.exchange, self.exchange_id, self.exchange_name)
                    logger.debug("Applied hotfix for %s", self.exchange_name)
                except Exception as hf:
                    logger.warning("Hotfix failed for %s: %s", self.exchange_name, hf)

        except Exception as e:
            logger.error("Failed to initialize exchange %s: %s", self.exchange_name, e)
            raise

    async def _send_ready(self) -> None:
        """Send ready message to broker."""
        import os
        ready_msg: bytes = create_subprocess_ready(self.exchange_id, os.getpid())
        # For DEALER socket, we need to send empty frame first
        await self.socket.send_multipart([b"", ready_msg])
        logger.info("Sent ready message for %s", self.exchange_id)

    async def _message_loop(self) -> None:
        """Main message loop."""
        _parent_check_count: int = 0
        while self.running:
            try:
                # Periodically check if parent process is still alive
                _parent_check_count += 1
                if _parent_check_count % 5 == 0:
                    try:
                        os.kill(self.parent_pid, 0)
                    except OSError:
                        logger.warning(
                            "Parent process %d died, shutting down subprocess %s",
                            self.parent_pid, self.exchange_id,
                        )
                        self.running = False
                        break

                # Receive multipart: [empty, message]
                parts: List[bytes] = await self.socket.recv_multipart()
                if len(parts) < 2:
                    continue

                empty: bytes = parts[0]
                message: bytes = parts[1]

                try:
                    msg: Dict[str, Any] = parse_message(message)
                    msg_type: str = msg.get("type", "")

                    if msg_type == "request":
                        await self._handle_request(msg)
                    else:
                        logger.warning("Unknown message type: %s", msg_type)

                except json.JSONDecodeError as e:
                    logger.error("Invalid JSON in message: %s", e)
                    response: bytes = create_response(
                        request_id="unknown",
                        error="Invalid JSON",
                        error_code="INVALID_JSON",
                    )
                    await self.socket.send_multipart([b"", response])

            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error("Error in message loop: %s", e)

        # Cleanup
        await self._cleanup()

    async def _handle_request(self, msg: Dict[str, Any]) -> None:
        """Handle a request message."""
        request_id: Optional[str] = msg.get("id")
        method: Optional[str] = msg.get("method")
        params: Dict[str, Any] = msg.get("params", {})
        subscription_id: Optional[str] = msg.get("subscription_id")

        if not request_id or not method:
            logger.error("Invalid request message: missing id or method")
            return

        try:
            if not self.exchange:
                raise RuntimeError("Exchange not initialized")

            # Settable properties — check params for set-operations
            settable_props: Dict[str, str] = {"timeout": "value", "enableRateLimit": "flag", "rateLimit": "value"}
            if method in settable_props and settable_props[method] in params:
                setattr(self.exchange, method, params[settable_props[method]])
                response = create_response(request_id, result={"status": "ok"})
            # Custom command: set API key on a running exchange
            elif method == "set_api_key":
                api_key = params.get("apiKey", "")
                secret = params.get("secret", "")
                password = params.get("password", "")
                wallet_address = params.get("walletAddress", "")
                private_key = params.get("privateKey", "")
                if api_key:
                    self.exchange.apiKey = api_key
                if secret:
                    self.exchange.secret = secret
                if password:
                    self.exchange.password = password
                if wallet_address:
                    self.exchange.walletAddress = wallet_address
                if private_key:
                    self.exchange.privateKey = private_key
                response = create_response(request_id, result={"status": "ok"})
            # Try direct attribute first (methods, properties like timeframes, fees)
            elif hasattr(self.exchange, method):
                attr: Any = getattr(self.exchange, method)

                if callable(attr):
                    ccxt_method: Callable[..., Any] = attr

                    if method.startswith("watch_"):
                        await self._handle_watch_method(method, ccxt_method, params, subscription_id, request_id)
                        return

                    result: Any = await self._call_method(ccxt_method, params)
                    serializable_result: Any = self._make_serializable(result)
                    response: bytes = create_response(request_id, result=serializable_result)
                else:
                    # Lazy-loaded attributes (markets, currencies, etc.):
                    # try calling load_<attribute>() first to populate
                    load_name: str = f"load_{method}"
                    loaded: bool = False
                    if hasattr(self.exchange, load_name):
                        try:
                            load_fn: Any = getattr(self.exchange, load_name)
                            if asyncio.iscoroutinefunction(load_fn):
                                await load_fn()
                            else:
                                load_fn()
                            loaded = True
                        except Exception as load_err:
                            logger.warning("Failed to lazy-load %s: %s", method, load_err)
                    # Special case: currencies are populated by load_markets(),
                    # but can also be fetched via fetchCurrencies if still empty
                    if not loaded and method == "currencies":
                        try:
                            fetch_name: str = f"fetch{method[0].upper()}{method[1:]}"
                            if hasattr(self.exchange, fetch_name):
                                fetch_fn: Any = getattr(self.exchange, fetch_name)
                                if asyncio.iscoroutinefunction(fetch_fn):
                                    await fetch_fn()
                                else:
                                    fetch_fn()
                        except Exception as fetch_err:
                            logger.warning("Failed to fetch %s: %s", method, fetch_err)
                    # Re-read after loading
                    attr = getattr(self.exchange, method)
                    serializable_result: Any = self._make_serializable(attr)
                    response: bytes = create_response(request_id, result=serializable_result)
            else:
                # Not a direct attribute — try the .has dict (e.g. publicAPI, fetchTicker flags)
                has_dict: Dict[str, Any] = dict(self.exchange.has) if hasattr(self.exchange.has, "items") else {}
                if method in has_dict:
                    serializable_result: Any = self._make_serializable(has_dict[method])
                    response: bytes = create_response(request_id, result=serializable_result)
                elif method == "get_propertynames":
                    import types as _types
                    names: List[str] = []
                    for k in dir(self.exchange):
                        if k.startswith("_"):
                            continue
                        attr = getattr(self.exchange, k)
                        # Skip only modules
                        if isinstance(attr, _types.ModuleType):
                            continue
                        names.append(k)
                    response = create_response(request_id, result=sorted(names))
                else:
                    raise AttributeError(f"Method {method} not found on exchange {self.exchange_name}")

        except Exception as e:
            logger.error("Error handling request %s: %s", request_id, e)
            response = create_response(
                request_id=request_id,
                error=str(e),
                error_code=type(e).__name__,
            )

        # Send response
        await self.socket.send_multipart([b"", response])

    async def _handle_watch_method(
        self,
        method: str,
        ccxt_method: Callable[..., Any],
        params: Dict[str, Any],
        subscription_id: Optional[str],
        request_id: str,
    ) -> None:
        """Handle a watch* method (WebSocket streaming)."""
        try:
            # Call the watch method - it returns an async iterator
            iterator_or_value: Any = await self._call_method(ccxt_method, params)

            # Check if it's an async iterator
            if hasattr(iterator_or_value, "__aiter__"):
                # Send initial response (subscription confirmed)
                response: bytes = create_response(request_id, result={"status": "subscribed", "method": method})
                await self.socket.send_multipart([b"", response])

                # Iterate over watch updates
                async for update in iterator_or_value:
                    # Send each update as a watch_update message
                    update_msg: bytes = create_watch_update(
                        subscription_id or request_id, update
                    )
                    await self.socket.send_multipart([b"", update_msg])
            else:
                # Not an iterator, just send result
                serializable_result: Any = self._make_serializable(iterator_or_value)
                response = create_response(request_id, result=serializable_result)
                await self.socket.send_multipart([b"", response])

        except Exception as e:
            logger.error("Error in watch method %s: %s", method, e)
            response = create_response(
                request_id=request_id,
                error=str(e),
                error_code=type(e).__name__,
            )
            await self.socket.send_multipart([b"", response])

    async def _call_method(self, method: Callable[..., Any], params: Dict[str, Any]) -> Any:
        """Call a CCXT method with given params."""
        if asyncio.iscoroutinefunction(method):
            if params:
                return await method(**params)
            return await method()
        if params:
            return method(**params)
        return method()

    def _make_serializable(self, result: Any) -> Any:
        """Convert result to JSON-serializable format."""
        try:
            # Test if result is JSON serializable
            json.dumps(result)
            return result
        except (TypeError, ValueError):
            # Convert to string if not serializable
            return str(result)

    async def _cleanup(self) -> None:
        """Cleanup resources."""
        if self.exchange:
            try:
                await self.exchange.close()
            except Exception as e:
                logger.error("Error closing exchange: %s", e)

        self.socket.close()
        self.context.term()
        logger.info("Subprocess %s cleaned up", self.exchange_id)


async def main() -> None:
    """Entry point for exchange subprocess."""
    if len(sys.argv) < 3:
        print("Usage: subprocess.py <exchange_id> <exchange_name>")
        sys.exit(1)

    exchange_id: str = sys.argv[1]
    exchange_name: str = sys.argv[2]

    # Parse additional arguments
    broker_address: str = "tcp://127.0.0.1:5555"
    api_key: Optional[str] = None
    secret: Optional[str] = None
    sandbox: bool = False

    i: int = 3
    while i < len(sys.argv):
        if sys.argv[i] == "--broker" and i + 1 < len(sys.argv):
            broker_address = sys.argv[i + 1]
            i += 2
        elif sys.argv[i] == "--api-key" and i + 1 < len(sys.argv):
            api_key = sys.argv[i + 1]
            i += 2
        elif sys.argv[i] == "--secret" and i + 1 < len(sys.argv):
            secret = sys.argv[i + 1]
            i += 2
        elif sys.argv[i] == "--sandbox":
            sandbox = True
            i += 1
        else:
            i += 1

    subprocess: ExchangeSubprocess = ExchangeSubprocess(
        exchange_id=exchange_id,
        exchange_name=exchange_name,
        broker_address=broker_address,
        api_key=api_key,
        secret=secret,
        sandbox=sandbox,
    )

    await subprocess.start()


# ── Exchange hotfix registrations ─────────────────────────────────────

async def _bybit_clock_sync(exchange: Any, exchange_id: str, exchange_name: str) -> None:
    """Sync Bybit's server clock for accurate timestamps."""
    try:
        await exchange.load_time_difference()
    except Exception:
        logger.debug("Clock sync skipped for %s (fetch_time not supported)", exchange_name)

register_hotfix("bybit", _bybit_clock_sync)


# ── Phemex WebSocket hotfix ───────────────────────────────────────────
# Phemex's ccxt.pro implementation raises NotSupported for watchPositions,
# even though position data (positions_p) arrives via the same private
# WebSocket channel used by watchOrders/watchBalance. This hotfix patches
# handle_message to capture positions_p and wires up a working watchPositions.

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


if __name__ == "__main__":
    asyncio.run(main())
