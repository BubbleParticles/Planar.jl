"""ZeroMQ broker for routing messages between main process and exchange subprocesses."""

import asyncio
import logging
from typing import Any, Callable, Dict, Optional

import zmq
import zmq.asyncio

from .protocol import parse_message, create_response

logger: logging.Logger = logging.getLogger(__name__)


class ZMQBroker:
    """Broker that routes messages between main process and exchange subprocesses."""

    def __init__(self, broker_address: str = "tcp://127.0.0.1:5555") -> None:
        self.broker_address: str = broker_address
        self.context: zmq.asyncio.Context = zmq.asyncio.Context()
        self.socket: zmq.asyncio.Socket = self.context.socket(zmq.ROUTER)
        self.socket.bind(broker_address)

        # Map exchange_id -> zmq identity
        self.exchange_identities: Dict[str, bytes] = {}
        # Reverse map: zmq identity -> exchange_id
        self.identity_exchanges: Dict[bytes, str] = {}

        # Pending requests: request_id -> future
        self.pending_requests: Dict[str, asyncio.Future[bytes]] = {}

        # Subscription management: subscription_id -> exchange_id
        self.subscriptions: Dict[str, str] = {}

        # Callback for watch updates
        self.watch_update_callback: Optional[Callable[[str, Any], None]] = None

        self.running: bool = False
        self._tasks: list[asyncio.Task[None]] = []

    async def start(self) -> None:
        """Start the broker."""
        self.running = True
        logger.info("ZMQ Broker started on %s", self.broker_address)
        self._tasks.append(asyncio.create_task(self._message_loop()))

    async def stop(self) -> None:
        """Stop the broker."""
        self.running = False
        for task in self._tasks:
            task.cancel()
        # Cancel pending requests
        for future in self.pending_requests.values():
            future.cancel()
        self.socket.close()
        self.context.term()
        logger.info("ZMQ Broker stopped")

    async def _message_loop(self) -> None:
        """Main message loop."""
        while self.running:
            try:
                # Poll with timeout to allow checking running flag
                try:
                    parts: list[bytes] = await asyncio.wait_for(
                        self.socket.recv_multipart(),
                        timeout=1.0,
                    )
                    identity, empty, raw_message = parts[0], parts[1], parts[2]
                except asyncio.TimeoutError:
                    continue

                try:
                    msg: Dict[str, Any] = parse_message(raw_message)
                    msg_type: str = msg.get("type", "")

                    if msg_type == "subprocess_ready":
                        exchange_id: Optional[str] = msg.get("exchange_id")
                        if exchange_id:
                            self.exchange_identities[exchange_id] = identity
                            self.identity_exchanges[identity] = exchange_id
                            logger.info(
                                "Subprocess ready: %s (identity: %s)",
                                exchange_id,
                                identity.hex(),
                            )

                    elif msg_type == "response":
                        request_id: Optional[str] = msg.get("id")
                        if request_id and request_id in self.pending_requests:
                            future: asyncio.Future[bytes] = self.pending_requests.pop(request_id)
                            if not future.done():
                                future.set_result(raw_message)
                        else:
                            logger.warning("Received response for unknown request: %s", request_id)

                    elif msg_type == "watch_update":
                        subscription_id: Optional[str] = msg.get("subscription_id")
                        if subscription_id and self.watch_update_callback:
                            self.watch_update_callback(subscription_id, msg.get("data"))
                        else:
                            logger.warning("Received watch_update without callback or subscription_id")

                    elif msg_type == "heartbeat":
                        pass

                    else:
                        logger.warning("Unknown message type: %s", msg_type)

                except Exception as e:
                    logger.error("Error handling message from %s: %s", identity.hex(), e)

            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error("Error in broker message loop: %s", e)

    async def send_request(
        self, exchange_id: str, message: bytes, timeout: float = 30.0
    ) -> Optional[bytes]:
        """Send a request to an exchange subprocess and wait for response."""
        if exchange_id not in self.exchange_identities:
            logger.error("No subprocess found for exchange: %s", exchange_id)
            return create_response(
                request_id="unknown",
                error=f"Exchange {exchange_id} not found or not ready",
                error_code="EXCHANGE_NOT_FOUND",
            )

        identity: bytes = self.exchange_identities[exchange_id]

        # Parse message to get request_id
        try:
            msg: Dict[str, Any] = parse_message(message)
            request_id: str = msg.get("id", "")
        except Exception:
            request_id = ""

        # Create future for response
        loop: asyncio.AbstractEventLoop = asyncio.get_running_loop()
        future: asyncio.Future[bytes] = loop.create_future()
        if request_id:
            self.pending_requests[request_id] = future

        try:
            # Send multipart: [identity, empty, message]
            await self.socket.send_multipart([identity, b"", message])

            # Wait for response with timeout
            response: bytes = await asyncio.wait_for(future, timeout=timeout)
            return response

        except asyncio.TimeoutError:
            logger.error("Timeout waiting for response from %s (request %s)", exchange_id, request_id)
            self.pending_requests.pop(request_id, None)
            return create_response(
                request_id=request_id or "unknown",
                error="Request timeout",
                error_code="TIMEOUT",
            )
        except Exception as e:
            logger.error("Error sending request to %s: %s", exchange_id, e)
            self.pending_requests.pop(request_id, None)
            return create_response(
                request_id=request_id or "unknown",
                error=str(e),
                error_code="SEND_ERROR",
            )

    def register_exchange(self, exchange_id: str, identity: bytes) -> None:
        """Register an exchange subprocess identity."""
        self.exchange_identities[exchange_id] = identity
        self.identity_exchanges[identity] = exchange_id

    def unregister_exchange(self, exchange_id: str) -> None:
        """Unregister an exchange subprocess."""
        if exchange_id in self.exchange_identities:
            identity: bytes = self.exchange_identities.pop(exchange_id)
            self.identity_exchanges.pop(identity, None)
            logger.info("Unregistered exchange: %s", exchange_id)

    def register_subscription(self, subscription_id: str, exchange_id: str) -> None:
        """Register a subscription."""
        self.subscriptions[subscription_id] = exchange_id

    def set_watch_update_callback(self, callback: Callable[[str, Any], None]) -> None:
        """Set callback for watch updates."""
        self.watch_update_callback = callback
