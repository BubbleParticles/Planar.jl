"""Main entry point for ccxt-gateway."""

import asyncio
import logging
import os
import time
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Any, Dict, Optional

import uvicorn
from fastapi import FastAPI, Request

from ccxt_gateway.config import settings
from ccxt_gateway.core.zmq_broker import ZMQBroker
from ccxt_gateway.core.process_manager import ProcessManager
from ccxt_gateway.api.rest import router as rest_router
from ccxt_gateway.api.websocket import router as ws_router, set_broker_callback
from ccxt_gateway.api.admin import router as admin_router
from ccxt_gateway.utils.updates import UpdateChecker

logger: logging.Logger = logging.getLogger(__name__)

# Idle shutdown tracking
_last_request_time: float = time.time()
_idle_task: Optional[asyncio.Task[None]] = None
PIDFILE: str = settings.idle.pidfile_path


async def _idle_monitor(app: FastAPI) -> None:
    """Monitor for idle timeout and shut down if exceeded."""
    timeout_seconds: float = settings.idle.timeout_minutes * 60.0
    while True:
        await asyncio.sleep(30)
        elapsed: float = time.time() - _last_request_time
        if elapsed >= timeout_seconds:
            logger.info(
                "Idle timeout reached (%.1f min), shutting down...",
                elapsed / 60.0,
            )
            os.remove(PIDFILE)
            app.state.shutdown_requested = True
            # Trigger shutdown via lifespan
            for handler in app.router.lifespan:
                if hasattr(handler, "__call__"):
                    pass
            # Fastest way: just exit
            import sys
            sys.exit(0)


async def _write_pidfile() -> None:
    """Write the PID file."""
    with open(PIDFILE, "w") as f:
        f.write(str(os.getpid()))


def _remove_pidfile() -> None:
    """Remove the PID file."""
    try:
        if os.path.exists(PIDFILE):
            os.remove(PIDFILE)
    except OSError:
        pass


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    """Application lifespan events."""
    logger.info("Starting ccxt-gateway...")

    import time
    app.state.start_time = time.time()

    # Initialize ZMQ broker
    broker: ZMQBroker = ZMQBroker(settings.zmq.broker_address)
    await broker.start()

    # Set watch update callback for WebSocket
    set_broker_callback(broker)

    # Initialize process manager
    process_manager: ProcessManager = ProcessManager(
        broker_address=settings.zmq.broker_address,
        max_rss_mb=settings.process_manager.max_rss_mb,
        check_interval=settings.process_manager.check_interval,
        auto_restart=settings.process_manager.auto_restart,
        max_restarts_per_hour=settings.process_manager.max_restarts_per_hour,
        startup_timeout=settings.process_manager.startup_timeout,
    )
    await process_manager.start()

    # Initialize update checker
    update_checker: UpdateChecker = UpdateChecker(
        check_interval_hours=settings.update.check_interval_hours,
        auto_update=settings.update.auto_update,
    )
    await update_checker.start()

    # Store in app state
    app.state.broker = broker
    app.state.process_manager = process_manager
    app.state.update_checker = update_checker
    app.state.shutdown_requested = False

    # Write PID file
    await _write_pidfile()

    # Start idle monitor
    global _idle_task
    _idle_task = asyncio.create_task(_idle_monitor(app))

    logger.info("ccxt-gateway started successfully (idle timeout: %d min)", settings.idle.timeout_minutes)

    yield

    # Shutdown
    logger.info("Shutting down ccxt-gateway...")
    _remove_pidfile()
    if _idle_task and not _idle_task.done():
        _idle_task.cancel()

    await update_checker.stop()
    await process_manager.stop()
    await broker.stop()

    logger.info("ccxt-gateway stopped")


# Create FastAPI app
app: FastAPI = FastAPI(
    title="ccxt-gateway",
    description="High-performance self-hosted gateway for 100+ crypto exchanges via CCXT",
    version="0.1.0",
    lifespan=lifespan,
)

# Touch middleware to update last-request time on every request
@app.middleware("http")
async def _touch_last_request(request: Request, call_next: Any) -> Any:
    global _last_request_time
    _last_request_time = time.time()
    response = await call_next(request)
    return response

app.include_router(rest_router, prefix="/exchanges", tags=["exchanges"])
app.include_router(ws_router, tags=["websocket"])
app.include_router(admin_router, prefix="/admin", tags=["admin"])


@app.get("/")
async def root() -> Dict[str, Any]:
    """Root endpoint."""
    return {
        "service": "ccxt-gateway",
        "version": "0.1.0",
        "status": "running",
        "endpoints": {
            "rest": "/exchanges/{exchange_id}/{method}",
            "websocket": "/ws",
            "admin": "/admin",
        },
    }


@app.get("/health")
async def health() -> Dict[str, str]:
    """Health check endpoint."""
    return {"status": "healthy"}


@app.get("/ping")
async def ping() -> Dict[str, str]:
    """Ping endpoint."""
    return {"status": "pong"}


def main() -> None:
    """Entry point."""
    import sys

    # Use uvloop if available
    try:
        import uvloop

        asyncio.set_event_loop_policy(uvloop.EventLoopPolicy())
    except ImportError:
        pass

    # Build uvicorn kwargs
    uvicorn_kwargs = {
        "app": app,
        "host": settings.server.host,
        "port": settings.server.port,
        "log_level": "info",
        "loop": "uvloop" if "uvloop" in sys.modules else "auto",
    }

    # Add SSL if configured
    if settings.server.use_ssl and settings.server.ssl_cert and settings.server.ssl_key:
        uvicorn_kwargs["ssl_keyfile"] = settings.server.ssl_key
        uvicorn_kwargs["ssl_certfile"] = settings.server.ssl_cert

    # Run with uvicorn
    uvicorn.run(**uvicorn_kwargs)


if __name__ == "__main__":
    main()
