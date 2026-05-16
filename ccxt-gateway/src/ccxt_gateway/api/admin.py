"""Admin API endpoints for ccxt-gateway."""

import logging
import time
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Request

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


@router.get("/exchanges")
async def list_exchanges(
    process_manager: Any = Depends(get_process_manager),
) -> List[Dict[str, Any]]:
    """List all exchange instances."""
    result: List[Dict[str, Any]] = []
    for exchange_id, proc in process_manager.processes.items():
        proc.update_memory()
        result.append(
            {
                "exchange_id": exchange_id,
                "exchange_name": proc.exchange_name,
                "pid": proc.pid,
                "running": proc.is_running,
                "rss_mb": round(proc.rss_mb, 2),
                "restart_count": proc.restart_count,
                "uptime_seconds": round(time.time() - proc.started_at, 2)
                if proc.started_at
                else None,
            }
        )
    return result


@router.get("/exchanges/{exchange_id}")
async def get_exchange_details(
    exchange_id: str,
    process_manager: Any = Depends(get_process_manager),
) -> Dict[str, Any]:
    """Get details of a specific exchange instance."""
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
        "last_restart": proc.last_restart,
        "uptime_seconds": round(time.time() - proc.started_at, 2)
        if proc.started_at
        else None,
        "config": proc.config,
    }


@router.post("/exchanges/{exchange_id}/restart")
async def restart_exchange(
    exchange_id: str,
    process_manager: Any = Depends(get_process_manager),
) -> Dict[str, Any]:
    """Manually restart an exchange instance."""
    if exchange_id not in process_manager.processes:
        raise HTTPException(status_code=404, detail=f"Exchange {exchange_id} not found")

    await process_manager._restart_exchange(exchange_id)

    return {"status": "restart initiated", "exchange_id": exchange_id}


@router.get("/stats")
async def get_stats(
    process_manager: Any = Depends(get_process_manager),
    broker: Any = Depends(get_broker),
) -> Dict[str, Any]:
    """Get gateway statistics."""
    total_exchanges: int = len(process_manager.processes)
    running: int = sum(1 for p in process_manager.processes.values() if p.is_running)
    total_memory: float = sum(p.rss_mb for p in process_manager.processes.values())

    return {
        "total_exchanges": total_exchanges,
        "running_exchanges": running,
        "stopped_exchanges": total_exchanges - running,
        "total_memory_mb": round(total_memory, 2),
        "pending_requests": len(broker.pending_requests)
        if hasattr(broker, "pending_requests")
        else 0,
        "registered_exchanges": len(broker.exchange_identities)
        if hasattr(broker, "exchange_identities")
        else 0,
    }


@router.get("/info")
async def get_info(request: Request) -> Dict[str, Any]:
    """Get gateway server info."""
    import time
    start_time: float = getattr(request.app.state, "start_time", time.time())
    uptime: float = time.time() - start_time
    return {
        "result": {
            "status": "running",
            "version": "0.1.0",
            "uptime_seconds": round(uptime, 2),
            "python_version": __import__("sys").version,
        },
        "error": None,
        "error_code": None,
    }


@router.get("/memory")
async def get_memory(
    process_manager: Any = Depends(get_process_manager),
) -> Dict[str, Any]:
    """Get memory usage."""
    total_memory: float = sum(p.rss_mb for p in process_manager.processes.values())
    return {
        "result": {
            "total_memory_mb": round(total_memory, 2),
            "exchange_count": len(process_manager.processes),
        },
        "error": None,
        "error_code": None,
    }


@router.get("/exchange_names")
async def get_exchange_names() -> Dict[str, Any]:
    """Get all CCXT exchange names."""
    try:
        import ccxt
        names = sorted(ccxt.exchanges)
        return {
            "result": names,
            "error": None,
            "error_code": None,
        }
    except Exception as e:
        return {
            "result": None,
            "error": str(e),
            "error_code": "EXCHANGE_NAMES_FAILED",
        }


@router.post("/update/ccxt")
async def trigger_ccxt_update(
    broker: Any = Depends(get_broker),
) -> Dict[str, Any]:
    """Manually trigger CCXT update."""
    from ccxt_gateway.utils.updates import update_ccxt, check_update

    update_available: bool
    current: Optional[str]
    latest: Optional[str]
    update_available, current, latest = await check_update()

    if not update_available:
        return {
            "status": "no update available",
            "current_version": current,
            "latest_version": latest,
        }

    success: bool
    message: str
    success, message = await update_ccxt()

    return {
        "status": "success" if success else "failed",
        "message": message,
        "previous_version": current,
        "new_version": latest,
    }


@router.get("/update/check")
async def check_ccxt_update(
    broker: Any = Depends(get_broker),
) -> Dict[str, Any]:
    """Check if CCXT update is available."""
    from ccxt_gateway.utils.updates import check_update

    update_available: bool
    current: Optional[str]
    latest: Optional[str]
    update_available, current, latest = await check_update()

    return {
        "update_available": update_available,
        "current_version": current,
        "latest_version": latest,
    }


@router.get("/errors")
async def list_errors(
    broker: Any = Depends(get_broker),
) -> Dict[str, Any]:
    """List all ccxt error names."""
    try:
        import ccxt
        from ccxt.base.errors import ExchangeError, NetworkError, AuthenticationError, PermissionError, RequestTimeout, ExchangeNotAvailable, NotSupported, OperationFailed, BaseError
        
        error_names = [
            "BaseError",
            "ExchangeError", 
            "NetworkError",
            "AuthenticationError",
            "PermissionError",
            "RequestTimeout",
            "ExchangeNotAvailable",
            "NotSupported",
            "OperationFailed",
        ]
        
        return {
            "result": error_names,
            "error": None,
            "error_code": None,
        }
    except Exception as e:
        return {
            "result": None,
            "error": str(e),
            "error_code": "ERROR_LIST_FAILED",
        }
