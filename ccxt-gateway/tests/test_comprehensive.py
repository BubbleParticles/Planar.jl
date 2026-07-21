"""Comprehensive tests to achieve 100% coverage for ccxt-gateway."""

import asyncio
import json
import time
from unittest.mock import MagicMock, patch, AsyncMock
import psutil

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

# Import all modules to test
from ccxt_gateway.config import Settings, ServerConfig, ZMQConfig, ProcessManagerConfig
from ccxt_gateway.core.protocol import (
    create_request, create_response, create_subprocess_ready,
    create_heartbeat, create_watch_update, parse_message,
    CCXT_PUBLIC_METHODS, CCXT_PRIVATE_METHODS, CCXT_WATCH_METHODS,
)
from ccxt_gateway.core.zmq_broker import ZMQBroker
from ccxt_gateway.core.process_manager import ExchangeProcess, ProcessManager
from ccxt_gateway.exchange.methods import (
    get_ccxt_method, is_public_method, is_private_method,
    is_watch_method, get_supported_methods,
)
from ccxt_gateway.utils.updates import check_update, get_current_version, UpdateChecker


# ============================================
# TESTS FOR core/process_manager.py
# ============================================

class TestExchangeProcessExtended:
    """Extended tests for ExchangeProcess class."""

    def test_init_with_all_params(self):
        """Test initialization with all parameters."""
        mock_process = MagicMock()
        mock_process.pid = 12345
        mock_process.returncode = None

        proc = ExchangeProcess(
            exchange_id="test",
            exchange_name="binance",
            process=mock_process,
            started_at=1000.0,
        )
        proc.rss_mb = 100.0  # 100MB
        proc.restart_count = 2
        proc.last_restart = time.time() - 7200  # 2 hours ago

        assert proc.exchange_id == "test"
        assert proc.exchange_name == "binance"
        assert proc.pid == 12345
        assert proc.is_running is True
        assert proc.rss_mb == 100.0
        assert proc.restart_count == 2

    def test_pid_none_without_process(self):
        """Test pid returns None when no process."""
        proc = ExchangeProcess(
            exchange_id="test",
            exchange_name="binance",
            process=None,
            started_at=1000.0,
        )
        assert proc.pid is None

    def test_is_running_false_when_terminated(self):
        """Test is_running returns False when process terminated."""
        mock_process = MagicMock()
        mock_process.returncode = 1  # Process has exited

        proc = ExchangeProcess(
            exchange_id="test",
            exchange_name="binance",
            process=mock_process,
            started_at=1000.0,
        )
        assert proc.is_running is False

    def test_memory_mb_property(self):
        """Test rss_mb property."""
        proc = ExchangeProcess(
            exchange_id="test",
            exchange_name="binance",
            process=None,
            started_at=1000.0,
        )
        proc.rss_mb = 50.0
        assert proc.rss_mb == 50.0

    def test_update_memory_with_process(self):
        """Test update_memory with running process."""
        mock_process = MagicMock()
        mock_process.returncode = None
        mock_process.pid = 12345

        proc = ExchangeProcess(
            exchange_id="test",
            exchange_name="binance",
            process=mock_process,
            started_at=1000.0,
        )

        with patch('psutil.Process') as mock_psutil:
            mock_psutil_instance = MagicMock()
            mock_psutil_instance.memory_info.return_value = MagicMock(rss=1024 * 1024 * 75)
            mock_psutil.return_value = mock_psutil_instance

            proc.update_memory()
            assert proc.rss_mb == 75.0

    def test_update_memory_process_not_running(self):
        """Test update_memory when process not running."""
        mock_process = MagicMock()
        mock_process.returncode = 1  # Process exited

        proc = ExchangeProcess(
            exchange_id="test",
            exchange_name="binance",
            process=mock_process,
            started_at=1000.0,
        )

        proc.update_memory()
        assert proc.rss_mb == 0.0

    def test_update_memory_no_process(self):
        """Test update_memory with no process."""
        proc = ExchangeProcess(
            exchange_id="test",
            exchange_name="binance",
            process=None,
            started_at=1000.0,
        )

        proc.update_memory()
        assert proc.rss_mb == 0.0

    def test_should_restart_below_limit(self):
        """Test should_restart when below max restarts."""
        proc = ExchangeProcess(
            exchange_id="test",
            exchange_name="binance",
            process=None,
            started_at=1000.0,
        )
        proc.restart_count = 2
        assert proc.should_restart(5) is True

    def test_should_restart_at_limit_recent(self):
        """Test should_restart at limit with recent restart."""
        proc = ExchangeProcess(
            exchange_id="test",
            exchange_name="binance",
            process=None,
            started_at=1000.0,
        )
        proc.restart_count = 5
        proc.last_restart = time.time() - 100  # 100 seconds ago
        assert proc.should_restart(5) is False

    def test_should_restart_at_limit_old(self):
        """Test should_restart at limit with old restart (cooldown passed)."""
        proc = ExchangeProcess(
            exchange_id="test",
            exchange_name="binance",
            process=None,
            started_at=1000.0,
        )
        proc.restart_count = 5
        proc.last_restart = time.time() - 4000  # Over 1 hour ago
        assert proc.should_restart(5) is True
        assert proc.restart_count == 0  # Should have reset


class TestProcessManagerExtended:
    """Extended tests for ProcessManager class."""

    def test_init_defaults(self):
        """Test initialization with defaults."""
        pm = ProcessManager()
        assert pm.max_rss_mb == 512
        assert pm.check_interval == 30
        assert pm.running is False
        assert len(pm.processes) == 0
        assert pm.auto_restart is True
        assert pm.max_restarts_per_hour == 5

    def test_init_custom(self):
        """Test initialization with custom values."""
        pm = ProcessManager(max_rss_mb=256, check_interval=60, auto_restart=False)
        assert pm.max_rss_mb == 256
        assert pm.check_interval == 60
        assert pm.auto_restart is False


# ============================================
# TESTS FOR core/zmq_broker.py
# ============================================

class TestZMQBrokerExtended:
    """Extended tests for ZMQBroker class."""

    def test_init_with_address(self):
        """Test initialization with custom address."""
        broker = ZMQBroker("tcp://127.0.0.1:5555")
        assert broker.broker_address == "tcp://127.0.0.1:5555"

    def test_init_default(self):
        """Test initialization with default address."""
        broker = ZMQBroker()
        assert broker.broker_address == "tcp://127.0.0.1:5555"

    def test_register_unregister_exchange(self):
        """Test registering and unregistering exchanges."""
        broker = ZMQBroker()
        identity = b"test-identity"

        broker.register_exchange("ex1", identity)
        assert "ex1" in broker.exchange_identities
        assert broker.exchange_identities["ex1"] == identity

        broker.unregister_exchange("ex1")
        assert "ex1" not in broker.exchange_identities

    def test_unregister_nonexistent_exchange(self):
        """Test unregistering non-existent exchange does nothing."""
        broker = ZMQBroker()
        broker.unregister_exchange("nonexistent")  # Should not raise

    def test_register_subscription(self):
        """Test registering subscriptions."""
        broker = ZMQBroker()
        broker.register_subscription("sub-1", "ex1")
        assert "sub-1" in broker.subscriptions
        assert broker.subscriptions["sub-1"] == "ex1"

    def test_unregister_subscription(self):
        """Test subscriptions can be tracked."""
        broker = ZMQBroker()
        broker.register_subscription("sub-1", "ex1")
        assert "sub-1" in broker.subscriptions
        # Note: no unregister method, but we can delete directly
        del broker.subscriptions["sub-1"]
        assert "sub-1" not in broker.subscriptions

    def test_unregister_nonexistent_subscription(self):
        """Test accessing non-existent subscription."""
        broker = ZMQBroker()
        # Just verify it doesn't have the key
        assert "nonexistent" not in broker.subscriptions

    def test_set_callback(self):
        """Test setting watch update callback."""
        broker = ZMQBroker()

        def dummy_callback(subscription_id, data):
            pass

        broker.set_watch_update_callback(dummy_callback)
        assert broker.watch_update_callback is not None

    def test_send_request_no_broker(self):
        """Test send_request when exchange not registered."""
        broker = ZMQBroker()

        # Create a simple async test
        async def run_test():
            result = await broker.send_request("nonexistent", b"request")
            return result

        import asyncio
        response = asyncio.get_event_loop().run_until_complete(run_test())
        assert response is not None
        # Should return an error response
        import json
        parsed = json.loads(response)
        assert "error" in parsed

    def test_send_watch_update_no_broker(self):
        """Test watch update callback not set."""
        broker = ZMQBroker()
        # Without callback set, watch updates are just ignored
        # This tests that the broker handles missing callbacks gracefully
        assert broker.watch_update_callback is None


# ============================================
# TESTS FOR exchange/methods.py
# ============================================

class TestGetSupportedMethods:
    """Tests for get_supported_methods."""

    def test_returns_dict(self):
        """Test returns a dict of supported methods."""
        result = get_supported_methods("binance")
        assert isinstance(result, dict)

    def test_has_fetch_ticker(self):
        """Test binance has fetch_ticker."""
        result = get_supported_methods("binance")
        assert "fetchTicker" in result

    def test_invalid_exchange(self):
        """Test with invalid exchange name."""
        result = get_supported_methods("nonexistent_exchange_xyz")
        assert isinstance(result, dict)


# ============================================
# TESTS FOR utils/updates.py
# ============================================

class TestCheckUpdate:
    """Tests for check_update function."""

    @pytest.mark.asyncio
    async def test_check_update_newer_available(self):
        """Test check_update when newer version available."""
        with patch('httpx.AsyncClient.get') as mock_get:
            mock_response = MagicMock()
            mock_response.raise_for_status = MagicMock()
            mock_response.json.return_value = {"info": {"version": "999.0.0"}}
            mock_get.return_value = mock_response

            with patch('ccxt_gateway.utils.updates.get_current_version', return_value="1.0.0"):
                update_available, current, latest = await check_update()
                assert update_available is True
                assert latest == "999.0.0"

    @pytest.mark.asyncio
    async def test_check_update_no_update(self):
        """Test check_update when no update available."""
        with patch('httpx.AsyncClient.get') as mock_get:
            mock_response = MagicMock()
            mock_response.raise_for_status = MagicMock()
            mock_response.json.return_value = {"info": {"version": "1.0.0"}}
            mock_get.return_value = mock_response

            with patch('ccxt_gateway.utils.updates.get_current_version', return_value="1.0.0"):
                update_available, current, latest = await check_update()
                assert update_available is False

    @pytest.mark.asyncio
    async def test_check_update_error(self):
        """Test check_update when request fails."""
        with patch('httpx.AsyncClient.get', side_effect=Exception("Network error")):
            update_available, current, latest = await check_update()
            assert update_available is False


class TestGetCurrentVersion:
    """Tests for get_current_version function."""

    def test_returns_version(self):
        """Test returns a version string."""
        version = get_current_version()
        assert isinstance(version, str)
        assert len(version) > 0


class TestUpdateCheckerExtended:
    """Extended tests for UpdateChecker class."""

    def test_init_default(self):
        """Test initialization with defaults."""
        checker = UpdateChecker()
        assert checker.check_interval_hours == 24
        assert checker.auto_update is False
        assert checker.running is False

    def test_init_custom(self):
        """Test initialization with custom values."""
        checker = UpdateChecker(check_interval_hours=12, auto_update=True)
        assert checker.check_interval_hours == 12
        assert checker.auto_update is True


# ============================================
# TESTS FOR api/rest.py (mocking)
# ============================================

class TestRestAPI:
    """Tests for REST API endpoints."""

    def test_health_endpoint(self):
        """Test health endpoint returns correct structure."""
        from ccxt_gateway.main import app
        client = TestClient(app)

        # Mock the app.state components
        app.state.broker = MagicMock()
        app.state.process_manager = MagicMock()
        app.state.update_checker = MagicMock()
        app.state.start_time = time.time()

        with patch('ccxt_gateway.api.rest.get_broker', return_value=MagicMock()), \
             patch('ccxt_gateway.api.rest.get_process_manager', return_value=MagicMock()):
            response = client.get("/health")
            assert response.status_code == 200
            data = response.json()
            assert "status" in data
