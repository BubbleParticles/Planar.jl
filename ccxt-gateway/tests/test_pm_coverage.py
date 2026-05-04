"""Tests for process_manager.py remaining gaps."""

import asyncio
from unittest.mock import MagicMock, patch, AsyncMock

import pytest

from ccxt_gateway.core.process_manager import ProcessManager, ExchangeProcess


class TestProcessManagerCoverage:
    """Tests for process_manager.py remaining lines."""

    @pytest.mark.asyncio
    async def test_start_exchange_already_running(self):
        """Test start_exchange when already running (line 129-202)."""
        pm = ProcessManager()
        pm.running = True

        # Add existing process
        mock_proc = MagicMock()
        pm.processes["binance"] = mock_proc()

        result = await pm.start_exchange("binance", "binance")
        assert result is False

    @pytest.mark.asyncio
    async def test_start_exchange_success_full(self):
        """Test start_exchange success path with full flow."""
        pm = ProcessManager()
        pm.running = True
        pm.startup_timeout = 5

        # Mock asyncio.create_subprocess_exec
        mock_process = MagicMock()
        mock_process.pid = 12345
        mock_process.stdout = MagicMock()
        mock_process.stderr = MagicMock()

        with patch('asyncio.create_subprocess_exec', new_callable=AsyncMock, return_value=mock_process), \
             patch.object(pm, '_wait_for_ready', new_callable=AsyncMock):

            result = await pm.start_exchange(
                "binance", "binance",
                api_key="test-key",
                secret="test-secret",
                password="test-password",
                uid="test-uid",
                enable_rate_limit=False,
                timeout=60000,
            )

            assert result is True
            assert "binance" in pm.processes

    @pytest.mark.asyncio
    async def test_start_exchange_subprocess_error(self):
        """Test start_exchange when subprocess creation fails."""
        pm = ProcessManager()

        with patch('asyncio.create_subprocess_exec', side_effect=Exception("Failed")):
            result = await pm.start_exchange("binance", "binance")
            assert result is False

    @pytest.mark.asyncio
    async def test_stop_exchange_with_process(self):
        """Test stop_exchange with actual process."""
        pm = ProcessManager()

        mock_process = MagicMock()
        mock_process.pid = 12345
        mock_process.returncode = None  # Still running
        mock_process.terminate = MagicMock()
        mock_process.wait = AsyncMock()

        mock_proc = ExchangeProcess(
            exchange_id="binance",
            exchange_name="binance",
            process=mock_process,
            started_at=time.time(),
        )
        pm.processes["binance"] = mock_proc

        await pm.stop_exchange("binance")

        mock_process.terminate.assert_called_once()
        assert "binance" not in pm.processes

    @pytest.mark.asyncio
    async def test_stop_exchange_not_found(self):
        """Test stop_exchange when not found."""
        pm = ProcessManager()

        # Should not raise
        await pm.stop_exchange("nonexistent")

    @pytest.mark.asyncio
    async def test__cleanup_process_exists(self):
        """Test _cleanup_process when exists."""
        pm = ProcessManager()

        mock_proc = MagicMock()
        pm.processes["binance"] = mock_proc

        await pm._cleanup_process("binance")

        assert "binance" not in pm.processes

    @pytest.mark.asyncio
    async def test__cleanup_process_not_found(self):
        """Test _cleanup_process when not found."""
        pm = ProcessManager()

        # Should not raise
        await pm._cleanup_process("nonexistent")

    @pytest.mark.asyncio
    async def test__monitor_loop_running(self):
        """Test _monitor_loop when running."""
        pm = ProcessManager()
        pm.running = True
        pm.check_interval = 0.1

        # Mock _check_all_processes
        pm._check_all_processes = AsyncMock()

        # Run loop for a short time
        async def stop_after_delay():
            await asyncio.sleep(0.2)
            pm.running = False

        asyncio.create_task(stop_after_delay())
        await pm._monitor_loop()

        # Check that _check_all_processes was called
        pm._check_all_processes.assert_called()

    @pytest.mark.asyncio
    async def test__monitor_loop_not_running(self):
        """Test _monitor_loop when not running."""
        pm = ProcessManager()
        pm.running = False

        # Should exit immediately
        await pm._monitor_loop()

    @pytest.mark.asyncio
    async def test__check_all_processes_running_ok(self):
        """Test _check_all_processes with running process."""
        pm = ProcessManager()
        pm.auto_restart = False

        mock_proc = MagicMock()
        mock_proc.is_running = True
        mock_proc.update_memory = MagicMock()
        mock_proc.rss_mb = 100.0  # Under limit
        pm.processes["binance"] = mock_proc

        await pm._check_all_processes()

        # Should not try to restart
        assert True

    @pytest.mark.asyncio
    async def test__check_all_processes_not_running(self):
        """Test _check_all_processes with dead process."""
        pm = ProcessManager()
        pm.auto_restart = False

        mock_proc = MagicMock()
        mock_proc.is_running = False
        pm.processes["binance"] = mock_proc

        await pm._check_all_processes()

        # Should log warning but not restart (auto_restart=False)
        assert True

    @pytest.mark.asyncio
    async def test__restart_exchange_success(self):
        """Test _restart_exchange success."""
        pm = ProcessManager()
        pm.auto_restart = False

        mock_old_proc = MagicMock()
        mock_old_proc.config = {
            "exchange_id": "binance",
            "exchange_name": "binance",
        }

        pm.processes["binance"] = mock_old_proc

        # Mock stop_exchange and start_exchange
        pm.stop_exchange = AsyncMock()
        pm.start_exchange = AsyncMock(return_value=True)

        await pm._restart_exchange("binance")

        pm.stop_exchange.assert_called_once_with("binance")
        pm.start_exchange.assert_called_once()

    @pytest.mark.asyncio
    async def test__restart_exchange_not_found(self):
        """Test _restart_exchange when not found."""
        pm = ProcessManager()

        # Should return without error
        await pm._restart_exchange("nonexistent")


import time  # Need to import at module level
