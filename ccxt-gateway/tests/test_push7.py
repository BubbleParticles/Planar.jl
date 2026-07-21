"""Test process_manager.py cleanup and exceptions."""
import pytest
import asyncio
from unittest.mock import MagicMock, AsyncMock, patch
from ccxt_gateway.core.process_manager import ProcessManager, ExchangeProcess

class TestProcessManagerCleanup:
    @pytest.mark.asyncio
    async def test_cleanup_process(self):
        pm = ProcessManager(max_rss_mb=1000)
        pm.running = True
        exchange_id = "test-exchange"
        
        # Add a process
        proc = ExchangeProcess(
            exchange_id=exchange_id,
            exchange_name="test",
            process=MagicMock(spec=asyncio.subprocess.Process),
            started_at=1000.0,
            config={},
        )
        pm.processes[exchange_id] = proc
        
        # Cleanup
        await pm._cleanup_process(exchange_id)
        assert exchange_id not in pm.processes

    @pytest.mark.asyncio
    async def test_restart_exchange_not_found(self):
        pm = ProcessManager(max_rss_mb=1000)
        pm.running = True
        
        # Try to restart non-existent
        await pm._restart_exchange("nonexistent")

    @pytest.mark.asyncio
    async def test_check_all_processes_dead(self):
        pm = ProcessManager(max_rss_mb=1000, auto_restart=False)
        pm.running = True
        
        # Add a dead process
        proc = ExchangeProcess(
            exchange_id="test",
            exchange_name="binance",
            process=MagicMock(spec=asyncio.subprocess.Process),
            started_at=1000.0,
            config={},
        )
        proc._is_running = False  # Dead
        proc.rss_mb = 500
        pm.processes["test"] = proc
        
        # Should handle dead process
        await pm._check_all_processes()

    @pytest.mark.asyncio
    async def test_check_all_processes_memory_exceeded(self):
        pm = ProcessManager(max_rss_mb=100, auto_restart=False)
        pm.running = True
        
        proc = ExchangeProcess(
            exchange_id="test",
            exchange_name="binance",
            process=MagicMock(spec=asyncio.subprocess.Process),
            started_at=1000.0,
            config={},
        )
        proc._is_running = True
        proc.rss_mb = 500  # Over limit
        pm.processes["test"] = proc
        
        # Should handle memory exceeded
        await pm._check_all_processes()
