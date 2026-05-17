"""Exchange subprocess that runs CCXT and communicates via ZeroMQ."""

import asyncio
import json
import logging
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
        while self.running:
            try:
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

            # Special case: return the .has dict directly (not a callable method)
            if method == "has":
                raw: Any = self.exchange.has
                result: Dict[str, Any] = dict(raw) if hasattr(raw, "items") else {}
                serializable_result = self._make_serializable(result)
                response = create_response(request_id, result=serializable_result)
                await self.socket.send_multipart([b"", response])
                return

            # Special case: return exchange metadata
            if method == "metadata":
                import json as _json
                meta: Dict[str, Any] = {}
                try:
                    meta["has"] = dict(self.exchange.has) if hasattr(self.exchange.has, "items") else {}
                except Exception:
                    meta["has"] = {}
                try:
                    tfs = self.exchange.timeframes
                    meta["timeframes"] = list(tfs.keys()) if hasattr(tfs, "keys") else (list(tfs) if tfs else [])
                except Exception:
                    meta["timeframes"] = []
                try:
                    fees = self.exchange.fees
                    meta["fees"] = self._make_serializable(fees)
                except Exception:
                    meta["fees"] = {}
                try:
                    meta["precisionMode"] = int(self.exchange.precisionMode)
                except Exception:
                    meta["precisionMode"] = 4
                try:
                    meta["markets"] = list(self.exchange.markets.keys()) if hasattr(self.exchange.markets, "keys") else []
                except Exception:
                    meta["markets"] = []
                response = create_response(request_id, result=meta)
                await self.socket.send_multipart([b"", response])
                return

            # Get the method from CCXT
            if not hasattr(self.exchange, method):
                raise AttributeError(f"Method {method} not found on exchange {self.exchange_name}")

            ccxt_method: Callable[..., Any] = getattr(self.exchange, method)

            # Check if this is a watch method
            if method.startswith("watch_"):
                await self._handle_watch_method(method, ccxt_method, params, subscription_id, request_id)
                return

            # Regular method
            result: Any = await self._call_method(ccxt_method, params)

            # Convert result to JSON-serializable format
            serializable_result: Any = self._make_serializable(result)

            response: bytes = create_response(request_id, result=serializable_result)

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
        else:
            i += 1

    subprocess: ExchangeSubprocess = ExchangeSubprocess(
        exchange_id=exchange_id,
        exchange_name=exchange_name,
        broker_address=broker_address,
        api_key=api_key,
        secret=secret,
    )

    await subprocess.start()


if __name__ == "__main__":
    asyncio.run(main())
