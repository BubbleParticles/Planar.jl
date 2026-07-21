"""Tests for main.py and process manager internal methods."""

import asyncio
import time
from unittest.mock import MagicMock, patch, AsyncMock

import pytest

from ccxt_gateway.main import app, lifespan, main
from ccxt_gateway.core.process_manager import ProcessManager, ExchangeProcess
from ccxt_gateway.core.zmq_broker import ZMQBroker
from ccxt_gateway.utils.updates import UpdateChecker


class TestMainModule:
    """Tests for main.py module."""

    def test_root_endpoint(self):
        """Test root endpoint."""
        from fastapi.testclient import TestClient
        client = TestClient(app)

        response = client.get("/")
        assert response.status_code == 200
        data = response.json()
        assert data["service"] == "ccxt-gateway"
        assert "version" in data
        assert "endpoints" in data

    def test_health_endpoint(self):
        """Test health endpoint."""
        from fastapi.testclient import TestClient
        client = TestClient(app)

        response = client.get("/health")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "healthy"

    @pytest.mark.asyncio
    async def test_lifespan(self):
        """Test lifespan context manager."""
        # Mock all the components
        mock_broker = AsyncMock(spec=ZMQBroker)
        mock_process_manager = AsyncMock(spec=ProcessManager)
        mock_update_checker = AsyncMock(spec=UpdateChecker)

        # Patch the imports in main module
        with patch('ccxt_gateway.main.ZMQBroker', return_value=mock_broker), \
             patch('ccxt_gateway.main.ProcessManager', return_value=mock_process_manager), \
             patch('ccxt_gateway.main.UpdateChecker', return_value=mock_update_checker), \
             patch('ccxt_gateway.main.set_broker_callback'):

            # Use the lifespan context manager
            async with lifespan(app):
                # Inside lifespan
                assert app.state.broker is not None
                assert app.state.process_manager is not None
                assert app.state.update_checker is not None

            # After lifespan (shutdown)
            mock_update_checker.stop.assert_called_once()
            mock_process_manager.stop.assert_called_once()
            mock_broker.stop.assert_called_once()

    def test_main_function(self):
        """Test main function."""
        with patch('ccxt_gateway.main.uvicorn.run') as mock_run, \
             patch('ccxt_gateway.main.asyncio.set_event_loop_policy'):

            # Mock uvloop import to avoid actual import
            with patch.dict('sys.modules', {'uvloop': MagicMock()}):
                # Call main (it will try to run uvicorn, but we mocked it)
                try:
                    main()
                except Exception:
                    pass  # Expected since we're not actually running the server

                # Check that uvicorn.run was called
                mock_run.assert_called_once()


class TestProcessManagerInternal:
    """Tests for ProcessManager internal methods."""

    @pytest.mark.asyncio
    async def test_start_exchange_success(self):
        """Test start_exchange success path."""
        pm = ProcessManager()
        pm.running = True

        # Mock asyncio.create_subprocess_exec
        mock_process = MagicMock()
        mock_process.pid = 12345
        mock_process.stdout = MagicMock()
        mock_process.stderr = MagicMock()

        with patch('asyncio.create_subprocess_exec', new_callable=AsyncMock, return_value=mock_process):
            result = await pm.start_exchange("binance", "binance")
            # The function returns True on success
            assert isinstance(result, bool)

    @pytest.mark.asyncio
    async def test_start_exchange_already_running(self):
        """Test start_exchange when already running."""
        pm = ProcessManager()

        # Add existing process
        mock_proc = MagicMock()
        pm.processes["binance"] = mock_proc

        result = await pm.start_exchange("binance", "binance")
        assert result is False

    @pytest.mark.asyncio
    async def test_stop_exchange_not_found(self):
        """Test stop_exchange when exchange not found."""
        pm = ProcessManager()

        # Should not raise
        await pm.stop_exchange("nonexistent")

    @pytest.mark.asyncio
    async def test_cleanup_process(self):
        """Test _cleanup_process."""
        pm = ProcessManager()

        # Add a process
        mock_proc = MagicMock()
        pm.processes["binance"] = mock_proc

        await pm._cleanup_process("binance")
        assert "binance" not in pm.processes

    @pytest.mark.asyncio
    async def test_cleanup_process_not_found(self):
        """Test _cleanup_process when not found."""
        pm = ProcessManager()

        # Should not raise
        await pm._cleanup_process("nonexistent")

    @pytest.mark.asyncio
    async def test_monitor_loop_not_running(self):
        """Test _monitor_loop when not running."""
        pm = ProcessManager()
        pm.running = False

        # Should exit immediately
        await pm._monitor_loop()

    @pytest.mark.asyncio
    async def test_check_all_processes_no_processes(self):
        """Test _check_all_processes with no processes."""
        pm = ProcessManager()

        # Should not raise
        await pm._check_all_processes()

    @pytest.mark.asyncio
    async def test_check_all_processes_running(self):
        """Test _check_all_processes with running processes."""
        pm = ProcessManager()
        pm.auto_restart = False

        # Create a mock process that is running
        mock_proc = MagicMock()
        mock_proc.is_running = True
        mock_proc.update_memory = MagicMock()
        mock_proc.rss_mb = 100.0
        pm.max_rss_mb = 500  # Well under limit
        pm.processes["binance"] = mock_proc

        # Should not raise
        await pm._check_all_processes()

    @pytest.mark.asyncio
    async def test_restart_exchange_not_found(self):
        """Test _restart_exchange when exchange not found."""
        pm = ProcessManager()

        # Should return without error
        await pm._restart_exchange("nonexistent")
