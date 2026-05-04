"""Process manager for exchange subprocesses."""

import asyncio
import logging
import sys
import time
from typing import Any, Dict, List, Optional

import psutil

from ccxt_gateway.core.protocol import parse_message

logger: logging.Logger = logging.getLogger(__name__)


class ExchangeProcess:
    """Represents a running exchange subprocess."""

    def __init__(
        self,
        exchange_id: str,
        exchange_name: str,
        process: asyncio.subprocess.Process,
        started_at: float,
        config: Optional[Dict[str, Any]] = None,
    ) -> None:
        self.exchange_id: str = exchange_id
        self.exchange_name: str = exchange_name
        self.process: asyncio.subprocess.Process = process
        self.started_at: float = started_at
        self.config: Dict[str, Any] = config or {}
        self.restart_count: int = 0
        self.last_restart: Optional[float] = None
        self.last_memory_check: Optional[float] = None
        self.rss_mb: float = 0.0

    @property
    def pid(self) -> Optional[int]:
        """Get process PID."""
        return self.process.pid if self.process else None

    @property
    def is_running(self) -> bool:
        """Check if process is running."""
        return self.process is not None and self.process.returncode is None

    def update_memory(self) -> None:
        """Update memory usage (RSS) using psutil."""
        if not self.is_running or self.pid is None:
            return

        try:
            proc: psutil.Process = psutil.Process(self.pid)
            memory_info: psutil._psutil_osx.ProcessMemoryInfo = proc.memory_info()
            self.rss_mb = memory_info.rss / (1024 * 1024)  # Convert to MB
            self.last_memory_check = time.time()
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            self.rss_mb = 0.0

    def should_restart(self, max_restarts_per_hour: int) -> bool:
        """Check if we should allow another restart."""
        if self.restart_count >= max_restarts_per_hour:
            # Check if it's been more than an hour since first restart
            if self.last_restart is not None:
                elapsed: float = time.time() - self.last_restart
                if elapsed < 3600:  # Less than an hour
                    return False
                # Reset counter after an hour
                self.restart_count = 0
                self.last_restart = None
        return True


class ProcessManager:
    """Manages exchange subprocesses."""

    def __init__(
        self,
        broker_address: str = "tcp://127.0.0.1:5555",
        max_rss_mb: int = 512,
        check_interval: int = 30,
        auto_restart: bool = True,
        max_restarts_per_hour: int = 5,
        startup_timeout: int = 30,
    ) -> None:
        self.broker_address: str = broker_address
        self.max_rss_mb: int = max_rss_mb
        self.check_interval: int = check_interval
        self.auto_restart: bool = auto_restart
        self.max_restarts_per_hour: int = max_restarts_per_hour
        self.startup_timeout: int = startup_timeout

        self.processes: Dict[str, ExchangeProcess] = {}
        self.running: bool = False
        self._tasks: List[asyncio.Task[None]] = []

    async def start(self) -> None:
        """Start the process manager."""
        self.running = True
        self._tasks.append(asyncio.create_task(self._monitor_loop()))
        logger.info("Process manager started")

    async def stop(self) -> None:
        """Stop all exchange subprocesses."""
        self.running = False

        for task in self._tasks:
            task.cancel()

        # Stop all exchange processes
        for exchange_id in list(self.processes.keys()):
            await self.stop_exchange(exchange_id)

        logger.info("Process manager stopped")

    async def start_exchange(
        self,
        exchange_id: str,
        exchange_name: str,
        api_key: Optional[str] = None,
        secret: Optional[str] = None,
        password: Optional[str] = None,
        uid: Optional[str] = None,
        enable_rate_limit: bool = True,
        timeout: int = 30000,
        verbose: bool = False,
    ) -> bool:
        """Start an exchange subprocess."""
        if exchange_id in self.processes:
            logger.warning("Exchange %s already running", exchange_id)
            return False

        # Store configuration for restart
        config: Dict[str, Any] = {
            "exchange_id": exchange_id,
            "exchange_name": exchange_name,
            "api_key": api_key,
            "secret": secret,
            "password": password,
            "uid": uid,
            "enable_rate_limit": enable_rate_limit,
            "timeout": timeout,
            "verbose": verbose,
        }

        # Build command
        cmd: List[str] = [
            sys.executable,
            "-m",
            "ccxt_gateway.exchange.subprocess",
            exchange_id,
            exchange_name,
            "--broker",
            self.broker_address,
        ]

        if api_key:
            cmd.extend(["--api-key", api_key])
        if secret:
            cmd.extend(["--secret", secret])

        try:
            # Start subprocess
            process: asyncio.subprocess.Process = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )

            logger.info("Started exchange subprocess %s (PID: %d)", exchange_id, process.pid)

            # Create ExchangeProcess object
            exchange_proc: ExchangeProcess = ExchangeProcess(
                exchange_id=exchange_id,
                exchange_name=exchange_name,
                process=process,
                started_at=time.time(),
                config=config,
            )

            self.processes[exchange_id] = exchange_proc

            # Wait for ready (with timeout)
            try:
                await asyncio.wait_for(
                    self._wait_for_ready(exchange_id),
                    timeout=self.startup_timeout,
                )
            except asyncio.TimeoutError:
                logger.error("Exchange %s startup timeout", exchange_id)
                await self._cleanup_process(exchange_id)
                return False

            # Start stdout/stderr readers
            self._tasks.append(asyncio.create_task(self._read_stdout(exchange_id)))
            self._tasks.append(asyncio.create_task(self._read_stderr(exchange_id)))

            return True

        except Exception as e:
            logger.error("Failed to start exchange %s: %s", exchange_id, e)
            return False

    async def _wait_for_ready(self, exchange_id: str) -> None:
        """Wait for exchange subprocess to be ready."""
        # This is simplified - in reality we'd get a ZMQ ready message
        # For now, just wait a bit
        await asyncio.sleep(2)

    async def _read_stdout(self, exchange_id: str) -> None:
        """Read stdout from subprocess."""
        if exchange_id not in self.processes:
            return

        process: asyncio.subprocess.Process = self.processes[exchange_id].process
        if process.stdout is None:
            return

        try:
            while True:
                line: bytes = await process.stdout.readline()
                if not line:
                    break
                logger.info("[%s] %s", exchange_id, line.decode().strip())
        except asyncio.CancelledError:
            pass

    async def _read_stderr(self, exchange_id: str) -> None:
        """Read stderr from subprocess."""
        if exchange_id not in self.processes:
            return

        process: asyncio.subprocess.Process = self.processes[exchange_id].process
        if process.stderr is None:
            return

        try:
            while True:
                line: bytes = await process.stderr.readline()
                if not line:
                    break
                logger.error("[%s] %s", exchange_id, line.decode().strip())
        except asyncio.CancelledError:
            pass

    async def stop_exchange(self, exchange_id: str) -> None:
        """Stop an exchange subprocess."""
        if exchange_id not in self.processes:
            return

        proc: ExchangeProcess = self.processes[exchange_id]
        logger.info("Stopping exchange %s (PID: %s)", exchange_id, proc.pid)

        try:
            proc.process.terminate()
            await asyncio.wait_for(proc.process.wait(), timeout=10)
        except asyncio.TimeoutError:
            logger.warning("Force killing exchange %s", exchange_id)
            proc.process.kill()
        except Exception as e:
            logger.error("Error stopping exchange %s: %s", exchange_id, e)
        finally:
            await self._cleanup_process(exchange_id)

    async def _cleanup_process(self, exchange_id: str) -> None:
        """Clean up after process exit."""
        if exchange_id in self.processes:
            del self.processes[exchange_id]
            logger.info("Cleaned up exchange %s", exchange_id)

    async def _monitor_loop(self) -> None:
        """Main monitoring loop for memory and health checks."""
        while self.running:
            try:
                await self._check_all_processes()
                await asyncio.sleep(self.check_interval)
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error("Error in monitor loop: %s", e)

    async def _check_all_processes(self) -> None:
        """Check all running processes for memory usage and health."""
        for exchange_id in list(self.processes.keys()):
            proc: ExchangeProcess = self.processes[exchange_id]

            # Check if process is still running
            if not proc.is_running:
                logger.warning("Exchange %s process died", exchange_id)
                if self.auto_restart and proc.should_restart(self.max_restarts_per_hour):
                    await self._restart_exchange(exchange_id)
                else:
                    await self._cleanup_process(exchange_id)
                continue

            # Check memory usage
            proc.update_memory()

            if proc.rss_mb > self.max_rss_mb:
                logger.warning(
                    "Exchange %s exceeded memory limit: %.1fMB > %dMB",
                    exchange_id,
                    proc.rss_mb,
                    self.max_rss_mb,
                )
                if self.auto_restart:
                    await self._restart_exchange(exchange_id)

    async def _restart_exchange(self, exchange_id: str) -> None:
        """Restart an exchange subprocess."""
        if exchange_id not in self.processes:
            return

        proc: ExchangeProcess = self.processes[exchange_id]
        logger.info("Restarting exchange %s", exchange_id)

        # Get stored config
        config: Dict[str, Any] = proc.config

        # Stop the old process
        await self.stop_exchange(exchange_id)

        # Wait a bit before restart
        await asyncio.sleep(1)

        # Restart with stored config
        success: bool = await self.start_exchange(
            exchange_id=config["exchange_id"],
            exchange_name=config["exchange_name"],
            api_key=config.get("api_key"),
            secret=config.get("secret"),
            password=config.get("password"),
            uid=config.get("uid"),
            enable_rate_limit=config.get("enable_rate_limit", True),
            timeout=config.get("timeout", 30000),
            verbose=config.get("verbose", False),
        )

        if success:
            # Update restart count for the new process
            if exchange_id in self.processes:
                new_proc: ExchangeProcess = self.processes[exchange_id]
                new_proc.restart_count = proc.restart_count + 1
                new_proc.last_restart = time.time()
        else:
            logger.error("Failed to restart exchange %s", exchange_id)
