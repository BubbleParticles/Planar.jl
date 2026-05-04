"""WebSocket API for ccxt-gateway."""

import asyncio
import json
import logging
from typing import Any, Callable, Dict, List

import fastapi
from fastapi import APIRouter, Request, WebSocket, WebSocketDisconnect

logger: logging.Logger = logging.getLogger(__name__)

router: APIRouter = APIRouter()

# Store active WebSocket connections and subscriptions
# subscription_id -> WebSocket
active_subscriptions: Dict[str, WebSocket] = {}
# exchange_id -> list of subscription_ids
exchange_subscriptions: Dict[str, List[str]] = {}


def set_broker_callback(broker: Any) -> None:
    """Set the watch update callback on the broker."""

    def callback(subscription_id: str, data: Any) -> None:
        """Forward watch update to WebSocket client."""
        forward_watch_update(subscription_id, data)

    if hasattr(broker, "set_watch_update_callback"):
        broker.set_watch_update_callback(callback)


@router.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket) -> None:
    """WebSocket endpoint for watch* methods."""
    await websocket.accept()
    logger.info("WebSocket client connected")

    # Get broker from app state
    broker = getattr(websocket.app.state, "broker", None)

    try:
        while True:
            # Receive message from client
            data: str = await websocket.receive_text()

            try:
                message: Dict[str, Any] = json.loads(data)
                msg_type: str = str(message.get("type", ""))

                if msg_type == "subscribe":
                    await handle_subscribe(websocket, message, broker)
                elif msg_type == "unsubscribe":
                    await handle_unsubscribe(websocket, message)
                else:
                    await websocket.send_json(
                        {"type": "error", "error": f"Unknown message type: {msg_type}"}
                    )

            except json.JSONDecodeError:
                await websocket.send_json({"type": "error", "error": "Invalid JSON"})
            except Exception as e:
                await websocket.send_json({"type": "error", "error": str(e)})

    except WebSocketDisconnect:
        logger.info("WebSocket client disconnected")
        # Clean up subscriptions for this WebSocket
        await cleanup_websocket(websocket)
    except Exception as e:
        logger.error("WebSocket error: %s", e)
        await cleanup_websocket(websocket)


async def handle_subscribe(websocket: WebSocket, message: Dict[str, Any], broker: Any) -> None:
    """Handle subscription request."""
    subscription_id: str = str(message.get("subscription_id", ""))
    exchange_id: str = str(message.get("exchange_id", ""))
    method: str = str(message.get("method", ""))
    params: Dict[str, Any] = message.get("params", {})

    if not all([subscription_id, exchange_id, method]):
        await websocket.send_json(
            {
                "type": "error",
                "subscription_id": subscription_id,
                "error": "Missing required fields: subscription_id, exchange_id, method",
            }
        )
        return

    # Check if exchange exists
    process_manager = getattr(websocket.app.state, "process_manager", None)

    if not process_manager or exchange_id not in process_manager.processes:
        await websocket.send_json(
            {
                "type": "error",
                "subscription_id": subscription_id,
                "error": f"Exchange {exchange_id} not found",
            }
        )
        return

    # Register subscription
    active_subscriptions[subscription_id] = websocket
    if exchange_id not in exchange_subscriptions:
        exchange_subscriptions[exchange_id] = []
    exchange_subscriptions[exchange_id].append(subscription_id)

    # Send request to exchange subprocess
    from ccxt_gateway.core.protocol import create_request, parse_message
    import uuid

    request_id: str = str(uuid.uuid4())
    request_msg: bytes = create_request(
        method=method,
        params=params,
        exchange_id=exchange_id,
        request_id=request_id,
    )

    # Add subscription_id to message for tracking
    request_dict: Dict[str, Any] = parse_message(request_msg)
    request_dict["subscription_id"] = subscription_id
    request_msg = json.dumps(request_dict).encode("utf-8")

    # Send to broker
    if broker:
        # For watch methods, we don't wait for response here
        # The subprocess will send updates via ZMQ
        # We need to register this subscription with the broker
        if hasattr(broker, "register_subscription"):
            broker.register_subscription(subscription_id, exchange_id)

        await broker.send_request(exchange_id, request_msg)

        await websocket.send_json(
            {
                "type": "subscribed",
                "subscription_id": subscription_id,
                "exchange_id": exchange_id,
                "method": method,
            }
        )
    else:
        await websocket.send_json(
            {
                "type": "error",
                "subscription_id": subscription_id,
                "error": "Broker not available",
            }
        )


async def handle_unsubscribe(websocket: WebSocket, message: Dict[str, Any]) -> None:
    """Handle unsubscribe request."""
    subscription_id: str = str(message.get("subscription_id", ""))

    if subscription_id and subscription_id in active_subscriptions:
        # Remove subscription
        del active_subscriptions[subscription_id]

        # Remove from exchange_subscriptions
        for subs in exchange_subscriptions.values():
            if subscription_id in subs:
                subs.remove(subscription_id)
                break

        await websocket.send_json(
            {"type": "unsubscribed", "subscription_id": subscription_id}
        )
    else:
        await websocket.send_json(
            {
                "type": "error",
                "subscription_id": subscription_id,
                "error": "Subscription not found",
            }
        )


async def cleanup_websocket(websocket: WebSocket) -> None:
    """Clean up subscriptions for a disconnected WebSocket."""
    to_remove: List[str] = [
        sub_id for sub_id, ws in active_subscriptions.items() if ws == websocket
    ]

    for sub_id in to_remove:
        del active_subscriptions[sub_id]

    # Clean up exchange_subscriptions
    for exchange_id in list(exchange_subscriptions.keys()):
        exchange_subscriptions[exchange_id] = [
            sub_id for sub_id in exchange_subscriptions[exchange_id]
            if sub_id not in to_remove
        ]
        if not exchange_subscriptions[exchange_id]:
            del exchange_subscriptions[exchange_id]


def forward_watch_update(subscription_id: str, data: Any) -> None:
    """Forward watch update to WebSocket client."""
    if subscription_id in active_subscriptions:
        websocket: WebSocket = active_subscriptions[subscription_id]
        asyncio.create_task(
            websocket.send_json(
                {"type": "update", "subscription_id": subscription_id, "data": data}
            )
        )
