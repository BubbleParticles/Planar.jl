"""Automatic CCXT update utilities."""

import asyncio
import logging
import subprocess
from typing import Any, Dict, Optional, Tuple

import httpx
from packaging import version

logger: logging.Logger = logging.getLogger(__name__)

PYPI_URL: str = "https://pypi.org/pypi/ccxt/json"


async def get_latest_version() -> Optional[str]:
    """Get latest CCXT version from PyPI."""
    try:
        async with httpx.AsyncClient() as client:
            response: httpx.Response = await client.get(PYPI_URL, timeout=10.0)
            response.raise_for_status()
            data: Dict[str, Any] = response.json()
            version: Optional[str] = data.get("info", {}).get("version")
            return version
    except Exception as e:
        logger.error("Failed to get latest CCXT version: %s", e)
        return None


def get_current_version() -> Optional[str]:
    """Get currently installed CCXT version."""
    try:
        import ccxt

        version: Any = ccxt.__version__
        return str(version) if version else None
    except Exception as e:
        logger.error("Failed to get current CCXT version: %s", e)
        return None


async def check_update() -> Tuple[bool, Optional[str], Optional[str]]:
    """Check if CCXT update is available.

    Returns:
        Tuple of (update_available, current_version, latest_version)
    """
    current: Optional[str] = get_current_version()
    latest: Optional[str] = await get_latest_version()

    if current is None or latest is None:
        return False, current, latest

    # Simple version comparison (assuming semantic versioning)
    try:
        update_available: bool = version.parse(latest) > version.parse(current)
        return update_available, current, latest
    except Exception as e:
        logger.error("Failed to compare versions: %s", e)
        return False, current, latest


async def update_ccxt() -> Tuple[bool, str]:
    """Update CCXT to latest version.

    Returns:
        Tuple of (success, message)
    """
    try:
        # Get latest version
        latest: Optional[str] = await get_latest_version()
        if latest is None:
            return False, "Failed to get latest version"

        # Run pip install upgrade
        result: subprocess.CompletedProcess[str] = subprocess.run(
            ["pip", "install", "--upgrade", f"ccxt[pro]=={latest}"],
            capture_output=True,
            text=True,
            timeout=300,
        )

        if result.returncode == 0:
            logger.info("Successfully updated CCXT to %s", latest)
            return True, f"Updated to {latest}"
        logger.error("Failed to update CCXT: %s", result.stderr or result.stdout)
        return False, f"Update failed: {result.stderr or result.stdout}"

    except Exception as e:
        logger.error("Error updating CCXT: %s", e)
        return False, str(e)


class UpdateChecker:
    """Periodic update checker."""

    def __init__(self, check_interval_hours: int = 24, auto_update: bool = False) -> None:
        self.check_interval_hours: int = check_interval_hours
        self.auto_update: bool = auto_update
        self.running: bool = False
        self._task: Optional[asyncio.Task[None]] = None

    async def start(self) -> None:
        """Start the update checker."""
        if self.check_interval_hours <= 0:
            logger.info("Update checker disabled")
            return

        self.running = True
        self._task = asyncio.create_task(self._check_loop())
        logger.info("Update checker started (interval: %d hours)", self.check_interval_hours)

    async def stop(self) -> None:
        """Stop the update checker."""
        self.running = False
        if self._task:
            self._task.cancel()
        logger.info("Update checker stopped")

    async def _check_loop(self) -> None:
        """Main check loop."""
        while self.running:
            try:
                await self._check_once()
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error("Error in update check loop: %s", e)

            # Wait for next check
            await asyncio.sleep(self.check_interval_hours * 3600)

    async def _check_once(self) -> None:
        """Perform a single check."""
        update_available: bool
        current: Optional[str]
        latest: Optional[str]
        update_available, current, latest = await check_update()

        if update_available:
            logger.info("CCXT update available: %s -> %s", current, latest)

            if self.auto_update:
                logger.info("Auto-updating CCXT...")
                success: bool
                msg: str
                success, msg = await update_ccxt()
                if success:
                    logger.info("Auto-update successful: %s", msg)
                else:
                    logger.error("Auto-update failed: %s", msg)
        else:
            logger.info("CCXT is up-to-date: %s", current)
