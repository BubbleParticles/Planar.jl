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
