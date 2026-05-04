"""More tests to improve coverage."""

import asyncio
import time
from unittest.mock import MagicMock, patch, AsyncMock, PropertyMock
import psutil

import pytest

from ccxt_gateway.core.process_manager import ExchangeProcess, ProcessManager
from ccxt_gateway.core.zmq_broker import ZMQBroker
from ccxt_gateway.utils.updates import UpdateChecker, check_update, get_current_version, update_ccxt


class TestExchangeProcessMore:
    """More tests for ExchangeProcess."""

    def test_init_with_config(self):
        """Test initialization with config."""
        mock_process = MagicMock()
        mock_process.pid = 12345
        mock_process.returncode = None

        config = {"api_key": "test", "secret": "secret"}
        proc = ExchangeProcess(
            exchange_id="test",
            exchange_name="binance",
            process=mock_process,
            started_at=1000.0,
            config=config,
        )
        assert proc.config == config

    def test_init_without_config(self):
        """Test initialization without config."""
        mock_process = MagicMock()
        proc = ExchangeProcess(
            exchange_id="test",
            exchange_name="binance",
            process=mock_process,
            started_at=1000.0,
        )
        assert proc.config == {}

    def test_update_memory_psutil_no_such_process(self):
        """Test update_memory when process doesn't exist."""
        mock_process = MagicMock()
        mock_process.returncode = None
        mock_process.pid = 12345

        proc = ExchangeProcess(
            exchange_id="test",
            exchange_name="binance",
            process=mock_process,
            started_at=1000.0,
        )

        with patch('psutil.Process', side_effect=psutil.NoSuchProcess(12345)):
            proc.update_memory()
            assert proc.rss_mb == 0.0

    def test_update_memory_psutil_access_denied(self):
        """Test update_memory when access denied."""
        mock_process = MagicMock()
        mock_process.returncode = None
        mock_process.pid = 12345

        proc = ExchangeProcess(
            exchange_id="test",
            exchange_name="binance",
            process=mock_process,
            started_at=1000.0,
        )

        with patch('psutil.Process', side_effect=psutil.AccessDenied(12345)):
            proc.update_memory()
            assert proc.rss_mb == 0.0

    def test_should_restart_no_last_restart(self):
        """Test should_restart when last_restart is None."""
        proc = ExchangeProcess(
            exchange_id="test",
            exchange_name="binance",
            process=None,
            started_at=1000.0,
        )
        proc.restart_count = 3
        proc.last_restart = None
        assert proc.should_restart(5) is True


class TestProcessManagerAsync:
    """Tests for ProcessManager async methods."""

    @pytest.mark.asyncio
    async def test_start(self):
        """Test start method."""
        pm = ProcessManager()
        await pm.start()
        assert pm.running is True
        await pm.stop()

    @pytest.mark.asyncio
    async def test_stop(self):
        """Test stop method."""
        pm = ProcessManager()
        await pm.start()
        assert pm.running is True
        await pm.stop()
        assert pm.running is False

    @pytest.mark.asyncio
    async def test_stop_exchange(self):
        """Test stop_exchange method."""
        pm = ProcessManager()

        mock_process = MagicMock()
        mock_process.pid = 12345
        mock_process.returncode = None
        mock_process.terminate = MagicMock()
        mock_process.wait = AsyncMock()

        proc = ExchangeProcess(
            exchange_id="binance",
            exchange_name="binance",
            process=mock_process,
            started_at=time.time(),
        )
        pm.processes["binance"] = proc

        await pm.stop_exchange("binance")
        assert "binance" not in pm.processes
        mock_process.terminate.assert_called_once()


class TestZMQBrokerAsync:
    """Tests for ZMQBroker async methods."""

    @pytest.mark.asyncio
    async def test_start_stop(self):
        """Test start and stop."""
        broker = ZMQBroker("tcp://127.0.0.1:16555")
        await broker.start()
        assert broker.running is True
        await broker.stop()
        assert broker.running is False

    def test_register_unregister_exchange(self):
        """Test exchange registration."""
        broker = ZMQBroker()
        identity = b"test-identity"

        broker.register_exchange("ex1", identity)
        assert "ex1" in broker.exchange_identities

        broker.unregister_exchange("ex1")
        assert "ex1" not in broker.exchange_identities


class TestUpdateCheckerAsync:
    """Tests for UpdateChecker async methods."""

    @pytest.mark.asyncio
    async def test_start_stop(self):
        """Test start and stop."""
        checker = UpdateChecker(check_interval_hours=0)  # Disabled
        await checker.start()
        # With check_interval_hours=0, it shouldn't actually start
        await checker.stop()

    @pytest.mark.asyncio
    async def test_check_once_no_update(self):
        """Test _check_once when no update available."""
        checker = UpdateChecker()

        with patch('ccxt_gateway.utils.updates.check_update', return_value=(False, "1.0.0", "1.0.0")):
            await checker._check_once()  # Should not raise

    @pytest.mark.asyncio
    async def test_check_once_with_update_no_auto(self):
        """Test _check_once when update available but auto_update is False."""
        checker = UpdateChecker(auto_update=False)

        with patch('ccxt_gateway.utils.updates.check_update', return_value=(True, "1.0.0", "2.0.0")):
            await checker._check_once()  # Should not raise

    @pytest.mark.asyncio
    async def test_check_once_with_update_and_auto(self):
        """Test _check_once when update available and auto_update is True."""
        checker = UpdateChecker(auto_update=True)

        with patch('ccxt_gateway.utils.updates.check_update', return_value=(True, "1.0.0", "2.0.0")), \
             patch('ccxt_gateway.utils.updates.update_ccxt', return_value=(True, "Updated")):
            await checker._check_once()  # Should not raise


class TestUpdateFunctions:
    """Tests for update functions."""

    def test_get_current_version_success(self):
        """Test get_current_version when ccxt is available."""
        result = get_current_version()
        assert result is not None
        assert isinstance(result, str)

    @pytest.mark.asyncio
    async def test_update_ccxt_success(self):
        """Test update_ccxt when successful."""
        with patch('subprocess.run') as mock_run:
            mock_run.return_value = MagicMock(returncode=0, stderr="", stdout="Success")

            with patch('ccxt_gateway.utils.updates.get_latest_version', return_value="2.0.0"):
                success, msg = await update_ccxt()
                assert success is True

    @pytest.mark.asyncio
    async def test_update_ccxt_failure(self):
        """Test update_ccxt when it fails."""
        with patch('subprocess.run') as mock_run:
            mock_run.return_value = MagicMock(returncode=1, stderr="Error", stdout="")

            with patch('ccxt_gateway.utils.updates.get_latest_version', return_value="2.0.0"):
                success, msg = await update_ccxt()
                assert success is False
