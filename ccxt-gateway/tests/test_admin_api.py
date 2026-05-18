"""Tests for Admin API endpoints."""

import time
from unittest.mock import MagicMock, patch, AsyncMock

import pytest
from fastapi.testclient import TestClient

from ccxt_gateway.main import app


class TestAdminAPIExtended:
    """Extended tests for Admin API endpoints."""

    @pytest.fixture
    def setup(self):
        """Set up test client with mocked dependencies."""
        mock_broker = MagicMock()
        mock_process_manager = MagicMock()
        mock_update_checker = MagicMock()

        app.state.broker = mock_broker
        app.state.process_manager = mock_process_manager
        app.state.update_checker = mock_update_checker

        return TestClient(app), mock_broker, mock_process_manager

    def test_list_exchanges(self, setup):
        """Test listing exchanges."""
        client, _, mock_pm = setup

        # Create mock processes
        mock_proc1 = MagicMock()
        mock_proc1.exchange_name = "binance"
        mock_proc1.pid = 12345
        mock_proc1.is_running = True
        mock_proc1.rss_mb = 100.0
        mock_proc1.restart_count = 0
        mock_proc1.started_at = time.time()
        mock_proc1.update_memory = MagicMock()

        mock_proc2 = MagicMock()
        mock_proc2.exchange_name = "coinbase"
        mock_proc2.pid = 12346
        mock_proc2.is_running = False
        mock_proc2.rss_mb = 0.0
        mock_proc2.restart_count = 1
        mock_proc2.started_at = time.time() - 3600
        mock_proc2.update_memory = MagicMock()

        mock_pm.processes = {"binance": mock_proc1, "coinbase": mock_proc2}

        response = client.get("/admin/exchanges")
        assert response.status_code == 200
        data = response.json()
        assert len(data) == 2

    def test_get_exchange_details(self, setup):
        """Test getting exchange details."""
        client, _, mock_pm = setup

        mock_proc = MagicMock()
        mock_proc.exchange_name = "binance"
        mock_proc.pid = 12345
        mock_proc.is_running = True
        mock_proc.rss_mb = 100.0
        mock_proc.restart_count = 0
        mock_proc.started_at = time.time()
        mock_proc.last_restart = None
        mock_proc.config = {}
        mock_proc.update_memory = MagicMock()

        mock_pm.processes = {"binance": mock_proc}

        response = client.get("/admin/exchanges/binance")
        assert response.status_code == 200
        data = response.json()
        assert data["exchange_id"] == "binance"

    def test_get_exchange_details_not_found(self, setup):
        """Test getting non-existent exchange details."""
        client, _, mock_pm = setup

        mock_pm.processes = {}

        response = client.get("/admin/exchanges/nonexistent")
        assert response.status_code == 404

    def test_restart_exchange(self, setup):
        """Test restarting an exchange."""
        client, _, mock_pm = setup

        mock_proc = MagicMock()
        mock_pm.processes = {"binance": mock_proc}
        mock_pm._restart_exchange = AsyncMock()

        response = client.post("/admin/exchanges/binance/restart")
        assert response.status_code == 200
        data = response.json()
        assert "restart" in data["status"].lower()

    def test_restart_exchange_not_found(self, setup):
        """Test restarting non-existent exchange."""
        client, _, mock_pm = setup

        mock_pm.processes = {}
        mock_pm._restart_exchange = AsyncMock()

        response = client.post("/admin/exchanges/nonexistent/restart")
        assert response.status_code == 404

    def test_get_stats(self, setup):
        """Test getting stats."""
        client, mock_broker, mock_pm = setup

        # Mock processes
        mock_proc1 = MagicMock()
        mock_proc1.is_running = True
        mock_proc1.rss_mb = 100.0

        mock_proc2 = MagicMock()
        mock_proc2.is_running = False
        mock_proc2.rss_mb = 0.0

        mock_pm.processes = {"binance": mock_proc1, "coinbase": mock_proc2}

        # Mock broker
        mock_broker.pending_requests = {}
        mock_broker.exchange_identities = {"binance": b"id1"}

        response = client.get("/admin/stats")
        assert response.status_code == 200
        data = response.json()
        assert "total_exchanges" in data
        assert data["total_exchanges"] == 2

    @pytest.mark.asyncio
    async def test_update_ccxt_no_update(self, setup):
        """Test CCXT update when no update available."""
        client, mock_broker, _ = setup

        # Patch at the source module
        with patch('ccxt_gateway.utils.updates.check_update', return_value=(False, "1.0.0", "1.0.0")):
            response = client.post("/admin/update/ccxt")
            assert response.status_code == 200
            data = response.json()
            assert "no update" in data["status"].lower()

    def test_check_update_available(self, setup):
        """Test checking for CCXT update."""
        client, mock_broker, _ = setup

        # Patch at the source module
        async def mock_check():
            return (True, "1.0.0", "2.0.0")

        with patch('ccxt_gateway.utils.updates.check_update', side_effect=mock_check):
            response = client.get("/admin/update/check")
            assert response.status_code == 200
            data = response.json()
            assert data["update_available"] is True

    def test_get_info(self, setup):
        """Test getting gateway info."""
        client, mock_broker, mock_pm = setup
        import time
        app.state.start_time = time.time()

        response = client.get("/admin/info")
        assert response.status_code == 200
        data = response.json()
        assert data["result"]["status"] == "running"
        assert "version" in data["result"]
        assert "uptime_seconds" in data["result"]

    def test_get_memory(self, setup):
        """Test getting memory usage."""
        client, _, mock_pm = setup

        mock_proc = MagicMock()
        mock_proc.rss_mb = 150.0
        mock_pm.processes = {"binance": mock_proc}

        response = client.get("/admin/memory")
        assert response.status_code == 200
        data = response.json()
        assert data["result"]["total_memory_mb"] == 150.0
        assert data["result"]["exchange_count"] == 1

    def test_get_memory_empty(self, setup):
        """Test getting memory when no exchanges."""
        client, _, mock_pm = setup
        mock_pm.processes = {}

        response = client.get("/admin/memory")
        assert response.status_code == 200
        data = response.json()
        assert data["result"]["total_memory_mb"] == 0.0
        assert data["result"]["exchange_count"] == 0

    def test_shutdown_endpoint_returns_accept(self, setup):
        """Test that /admin/shutdown returns 200 and schedules shutdown."""
        client, mock_broker, mock_pm = setup

        response = client.post("/admin/shutdown")
        assert response.status_code == 200
        data = response.json()
        assert "shutting_down" in data["status"].lower()


class TestCreateExchangeIdempotent:
    """Tests for idempotent exchange creation."""

    @pytest.fixture
    def setup(self):
        """Set up test client with mocked dependencies."""
        mock_broker = MagicMock()
        mock_process_manager = MagicMock()
        mock_update_checker = MagicMock()

        # Simulate an exchange already running
        mock_proc = MagicMock()
        mock_proc.exchange_name = "binance"
        mock_proc.pid = 12345
        mock_proc.is_running = True
        mock_proc.rss_mb = 100.0
        mock_proc.restart_count = 0
        mock_proc.started_at = time.time()
        mock_proc.update_memory = MagicMock()
        mock_process_manager.processes = {"binance": mock_proc}

        app.state.broker = mock_broker
        app.state.process_manager = mock_process_manager
        app.state.update_checker = mock_update_checker

        return TestClient(app), mock_process_manager

    def test_create_exchange_already_running(self, setup):
        """Test creating an exchange that already exists returns 200 (idempotent)."""
        client, mock_pm = setup

        response = client.post("/exchanges/binance?exchange_name=binance")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "already_started"
        assert data["exchange_id"] == "binance"

    def test_create_exchange_new_success(self, setup):
        """Test creating a new exchange succeeds."""
        client, mock_pm = setup

        mock_pm.start_exchange = AsyncMock(return_value=True)

        response = client.post("/exchanges/kraken?exchange_name=kraken")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "success"
        assert data["exchange_id"] == "kraken"

    def test_create_exchange_new_failure(self, setup):
        """Test creating a new exchange that fails returns 500."""
        client, mock_pm = setup

        mock_pm.start_exchange = AsyncMock(return_value=False)

        response = client.post("/exchanges/bitfinex?exchange_name=bitfinex")
        assert response.status_code == 500
        data = response.json()
        assert "detail" in data
