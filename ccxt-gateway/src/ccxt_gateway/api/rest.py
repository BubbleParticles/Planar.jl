"""REST API endpoints for ccxt-gateway."""

import logging
import time
from typing import Any, Dict, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from fastapi.responses import JSONResponse

from ccxt_gateway.core.protocol import create_request, parse_message

logger: logging.Logger = logging.getLogger(__name__)

router: APIRouter = APIRouter()


def get_process_manager(request: Request) -> Any:
    """Dependency to get process manager."""
    process_manager = getattr(request.app.state, "process_manager", None)

    if process_manager is None:
        raise HTTPException(status_code=503, detail="Process manager not initialized")
    return process_manager


def get_broker(request: Request) -> Any:
    """Dependency to get ZMQ broker."""
    broker = getattr(request.app.state, "broker", None)

    if broker is None:
        raise HTTPException(status_code=503, detail="ZMQ broker not initialized")
    return broker


@router.post("/{exchange_id}")
async def create_exchange(
    exchange_id: str,
    exchange_name: str = Query(..., description="CCXT exchange name (e.g., binance)"),
    api_key: Optional[str] = Query(None, description="API key for private methods"),
    secret: Optional[str] = Query(None, description="API secret"),
    password: Optional[str] = Query(None, description="API password (if required)"),
    uid: Optional[str] = Query(None, description="User ID (if required)"),
    process_manager: Any = Depends(get_process_manager),
) -> Dict[str, Any]:
    """Create a new exchange instance (idempotent: returns success if already running)."""
    if exchange_id in process_manager.processes:
        logger.info("Exchange %s already running, returning success", exchange_id)
        return {
            "status": "already_started",
            "exchange_id": exchange_id,
            "exchange_name": exchange_name,
            "message": f"Exchange {exchange_id} already running",
        }

    success: bool = await process_manager.start_exchange(
        exchange_id=exchange_id,
        exchange_name=exchange_name,
        api_key=api_key,
        secret=secret,
        password=password,
        uid=uid,
    )

    if not success:
        raise HTTPException(status_code=500, detail=f"Failed to start exchange {exchange_id}")

    return {
        "status": "success",
        "exchange_id": exchange_id,
        "exchange_name": exchange_name,
        "message": f"Exchange {exchange_id} started",
    }


@router.delete("/{exchange_id}")
async def delete_exchange(
    exchange_id: str,
    process_manager: Any = Depends(get_process_manager),
) -> Dict[str, Any]:
    """Delete an exchange instance."""
    if exchange_id not in process_manager.processes:
        raise HTTPException(status_code=404, detail=f"Exchange {exchange_id} not found")

    await process_manager.stop_exchange(exchange_id)

    return {
        "status": "success",
        "exchange_id": exchange_id,
        "message": f"Exchange {exchange_id} stopped",
    }


@router.get("/{exchange_id}/status")
async def get_exchange_status(
    exchange_id: str,
    process_manager: Any = Depends(get_process_manager),
) -> Dict[str, Any]:
    """Get status of an exchange instance."""
    if exchange_id not in process_manager.processes:
        raise HTTPException(status_code=404, detail=f"Exchange {exchange_id} not found")

    proc: Any = process_manager.processes[exchange_id]
    proc.update_memory()

    return {
        "exchange_id": exchange_id,
        "exchange_name": proc.exchange_name,
        "pid": proc.pid,
        "running": proc.is_running,
        "rss_mb": round(proc.rss_mb, 2),
        "restart_count": proc.restart_count,
        "started_at": proc.started_at,
        "uptime_seconds": round(time.time() - proc.started_at, 2) if proc.started_at else None,
    }


@router.get("/{exchange_id}/has")
async def get_exchange_has(
    exchange_id: str,
    process_manager: Any = Depends(get_process_manager),
    broker: Any = Depends(get_broker),
) -> Dict[str, Any]:
    """Get the .has dict for an exchange (supported methods)."""
    if exchange_id not in process_manager.processes:
        raise HTTPException(status_code=404, detail=f"Exchange {exchange_id} not found")

    request_msg: bytes = create_request(method="has", exchange_id=exchange_id)
    response_bytes: Optional[bytes] = await broker.send_request(exchange_id, request_msg)

    if not response_bytes:
        raise HTTPException(status_code=504, detail="No response from exchange subprocess")

    response: Dict[str, Any] = parse_message(response_bytes)

    if response.get("error"):
        raise HTTPException(
            status_code=500,
            detail={"error": response["error"], "error_code": response.get("error_code")},
        )

    result: Dict[str, bool] = response.get("result", {})
    return result


@router.get("/{exchange_id}/metadata")
async def get_exchange_metadata(
    exchange_id: str,
    process_manager: Any = Depends(get_process_manager),
    broker: Any = Depends(get_broker),
) -> Dict[str, Any]:
    """Get exchange metadata (has, timeframes, fees, precisionMode, markets)."""
    if exchange_id not in process_manager.processes:
        raise HTTPException(status_code=404, detail=f"Exchange {exchange_id} not found")

    request_msg: bytes = create_request(method="metadata", exchange_id=exchange_id)
    response_bytes: Optional[bytes] = await broker.send_request(exchange_id, request_msg)

    if not response_bytes:
        raise HTTPException(status_code=504, detail="No response from exchange subprocess")

    response: Dict[str, Any] = parse_message(response_bytes)

    if response.get("error"):
        raise HTTPException(
            status_code=500,
            detail={"error": response["error"], "error_code": response.get("error_code")},
        )

    result: Dict[str, Any] = response.get("result", {})
    return result


@router.api_route("/{exchange_id}/{method}", methods=["GET", "POST"])
async def call_exchange_method(
    exchange_id: str,
    method: str,
    request: Request,
    body: Optional[Dict[str, Any]] = None,
    process_manager: Any = Depends(get_process_manager),
    broker: Any = Depends(get_broker),
) -> Any:
    """Call a CCXT method on an exchange instance.
    
    If the exchange subprocess has crashed, it will be restarted automatically
    and the request will be retried.
    """
    if exchange_id not in process_manager.processes:
        raise HTTPException(status_code=404, detail=f"Exchange {exchange_id} not found")

    # Check if subprocess is still alive; restart if dead
    if not process_manager.processes[exchange_id].is_running:
        logger.warning("Exchange %s subprocess dead, restarting...", exchange_id)
        success: bool = await process_manager.restart_exchange(exchange_id)
        if not success:
            raise HTTPException(status_code=503, detail=f"Failed to restart exchange {exchange_id}")

    # Prepare params from query (GET) or body (POST)
    if request.method == "GET":
        params: Dict[str, Any] = dict(request.query_params)
    else:
        params = body or {}

    # Create request message
    request_msg: bytes = create_request(
        method=method,
        params=params,
        exchange_id=exchange_id,
    )

    # Send request via broker
    response_bytes: Optional[bytes] = await broker.send_request(exchange_id, request_msg)

    if not response_bytes:
        raise HTTPException(status_code=504, detail="No response from exchange subprocess")

    # Parse response
    response: Dict[str, Any] = parse_message(response_bytes)

    if response.get("error"):
        raise HTTPException(
            status_code=500,
            detail={
                "error": response["error"],
                "error_code": response.get("error_code"),
            },
        )

    return response.get("result")



