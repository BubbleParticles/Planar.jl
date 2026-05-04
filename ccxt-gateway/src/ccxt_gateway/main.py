"""Main entry point for ccxt-gateway."""

import asyncio
import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Any, Dict, Optional

import uvicorn
from fastapi import FastAPI

from ccxt_gateway.config import settings
from ccxt_gateway.core.zmq_broker import ZMQBroker
from ccxt_gateway.core.process_manager import ProcessManager
from ccxt_gateway.api.rest import router as rest_router
from ccxt_gateway.api.websocket import router as ws_router, set_broker_callback
from ccxt_gateway.api.admin import router as admin_router
from ccxt_gateway.utils.updates import UpdateChecker

logger: logging.Logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    """Application lifespan events."""
    logger.info("Starting ccxt-gateway...")

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

    logger.info("ccxt-gateway started successfully")

    yield

    # Shutdown
    logger.info("Shutting down ccxt-gateway...")

    # Stop update checker
    await update_checker.stop()

    # Stop process manager (which will stop all exchange processes)
    await process_manager.stop()

    # Stop broker
    await broker.stop()

    logger.info("ccxt-gateway stopped")


# Create FastAPI app
app: FastAPI = FastAPI(
    title="ccxt-gateway",
    description="High-performance self-hosted gateway for 100+ crypto exchanges via CCXT",
    version="0.1.0",
    lifespan=lifespan,
)

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


def main() -> None:
    """Entry point."""
    import sys

    # Use uvloop if available
    try:
        import uvloop

        asyncio.set_event_loop_policy(uvloop.EventLoopPolicy())
    except ImportError:
        pass

    # Run with uvicorn
    uvicorn.run(
        app,
        host=settings.server.host,
        port=settings.server.port,
        log_level="info",
        loop="uvloop" if "uvloop" in sys.modules else "auto",
    )


if __name__ == "__main__":
    main()
