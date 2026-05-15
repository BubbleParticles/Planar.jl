"""Tests for API endpoints to improve coverage."""

import time
import json
from unittest.mock import MagicMock, patch, AsyncMock

import pytest
from fastapi.testclient import TestClient
from fastapi import FastAPI

from ccxt_gateway.main import app
from ccxt_gateway.core.protocol import create_request, parse_message


class TestRestAPIExtended:
    """Extended tests for REST API endpoints."""

    @pytest.fixture
    def setup(self):
        """Set up test client with mocked dependencies."""
        mock_broker = MagicMock()
        mock_process_manager = MagicMock()
        mock_update_checker = MagicMock()

        app.state.broker = mock_broker
        app.state.process_manager = mock_process_manager
        app.state.update_checker = mock_update_checker
        app.state.start_time = time.time()

        return TestClient(app), mock_broker, mock_process_manager

    def test_create_exchange_success(self, setup):
        """Test creating an exchange successfully."""
        client, mock_broker, mock_pm = setup

        mock_pm.start_exchange = AsyncMock(return_value=True)

        response = client.post("/exchanges/binance?exchange_name=binance")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "success"
        assert data["exchange_id"] == "binance"

    def test_create_exchange_failure(self, setup):
        """Test creating an exchange when it fails."""
        client, mock_broker, mock_pm = setup

        mock_pm.start_exchange = AsyncMock(return_value=False)

        response = client.post("/exchanges/binance?exchange_name=binance")
        assert response.status_code == 500

    def test_delete_exchange_success(self, setup):
        """Test deleting an exchange successfully."""
        client, mock_broker, mock_pm = setup

        mock_pm.processes = {"binance": MagicMock()}
        mock_pm.stop_exchange = AsyncMock()

        response = client.delete("/exchanges/binance")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "success"

    def test_delete_exchange_not_found(self, setup):
        """Test deleting non-existent exchange."""
        client, mock_broker, mock_pm = setup

        mock_pm.processes = {}

        response = client.delete("/exchanges/nonexistent")
        assert response.status_code == 404

    def test_get_exchange_status_success(self, setup):
        """Test getting exchange status."""
        client, mock_broker, mock_pm = setup

        mock_proc = MagicMock()
        mock_proc.is_running = True
        mock_proc.exchange_name = "binance"
        mock_proc.pid = 12345
        mock_proc.rss_mb = 100.0
        mock_proc.restart_count = 0
        mock_proc.started_at = time.time()
        mock_proc.update_memory = MagicMock()

        mock_pm.processes = {"binance": mock_proc}

        response = client.get("/exchanges/binance/status")
        assert response.status_code == 200

    def test_get_exchange_status_not_found(self, setup):
        """Test getting status of non-existent exchange."""
        client, mock_broker, mock_pm = setup

        mock_pm.processes = {}

        response = client.get("/exchanges/nonexistent/status")
        assert response.status_code == 404

    def test_call_exchange_method_get(self, setup):
        """Test calling exchange method via GET."""
        client, mock_broker, mock_pm = setup

        mock_pm.processes = {"binance": MagicMock()}

        # Mock broker response
        mock_response = json.dumps({
            "type": "response",
            "id": "test-id",
            "result": {"last": 50000}
        }).encode()
        mock_broker.send_request = AsyncMock(return_value=mock_response)
        mock_broker.exchange_identities = {"binance": b"identity"}

        response = client.get("/exchanges/binance/fetch_ticker?symbol=BTC/USDT")
        assert response.status_code == 200

    def test_call_exchange_method_post(self, setup):
        """Test calling exchange method via POST."""
        client, mock_broker, mock_pm = setup

        mock_pm.processes = {"binance": MagicMock()}

        # Mock broker response
        mock_response = json.dumps({
            "type": "response",
            "id": "test-id",
            "result": {"last": 50000}
        }).encode()
        mock_broker.send_request = AsyncMock(return_value=mock_response)
        mock_broker.exchange_identities = {"binance": b"identity"}

        response = client.post("/exchanges/binance/fetch_ticker", json={"symbol": "BTC/USDT"})
        assert response.status_code == 200

    def test_call_exchange_method_not_found(self, setup):
        """Test calling method on non-existent exchange."""
        client, mock_broker, mock_pm = setup

        mock_pm.processes = {}

        response = client.get("/exchanges/nonexistent/fetch_ticker")
        assert response.status_code == 404

    def test_call_exchange_method_error_response(self, setup):
        """Test when exchange returns error."""
        client, mock_broker, mock_pm = setup

        mock_pm.processes = {"binance": MagicMock()}

        # Mock broker response with error
        mock_response = json.dumps({
            "type": "response",
            "id": "test-id",
            "error": "Some error",
            "error_code": "SOME_ERROR"
        }).encode()
        mock_broker.send_request = AsyncMock(return_value=mock_response)
        mock_broker.exchange_identities = {"binance": b"identity"}

        response = client.get("/exchanges/binance/fetch_ticker")
        assert response.status_code == 500

    def test_call_exchange_process_dead_restart_and_retry(self, setup):
        """Test calling method on dead subprocess triggers restart and retries."""
        client, mock_broker, mock_pm = setup

        mock_proc = MagicMock()
        mock_proc.is_running = False
        mock_pm.processes = {"binance": mock_proc}
        mock_pm.restart_exchange = AsyncMock(return_value=True)

        mock_response = json.dumps({
            "type": "response",
            "id": "test-id",
            "result": {"last": 50000}
        }).encode()
        mock_broker.send_request = AsyncMock(return_value=mock_response)
        mock_broker.exchange_identities = {"binance": b"identity"}

        response = client.get("/exchanges/binance/fetch_ticker?symbol=BTC/USDT")
        assert response.status_code == 200
        mock_pm.restart_exchange.assert_awaited_once_with("binance")
        mock_broker.send_request.assert_awaited_once()

    def test_call_exchange_process_dead_restart_fails(self, setup):
        """Test calling method on dead subprocess when restart fails."""
        client, mock_broker, mock_pm = setup

        mock_proc = MagicMock()
        mock_proc.is_running = False
        mock_pm.processes = {"binance": mock_proc}
        mock_pm.restart_exchange = AsyncMock(return_value=False)

        response = client.get("/exchanges/binance/fetch_ticker")
        assert response.status_code == 503
        data = response.json()
        assert "restart" in data["detail"].lower()

    def test_call_exchange_process_alive_no_restart(self, setup):
        """Test calling method on healthy subprocess does NOT trigger restart."""
        client, mock_broker, mock_pm = setup

        mock_proc = MagicMock()
        mock_proc.is_running = True
        mock_pm.processes = {"binance": mock_proc}
        mock_pm.restart_exchange = AsyncMock(return_value=True)

        mock_response = json.dumps({
            "type": "response",
            "id": "test-id",
            "result": {"last": 50000}
        }).encode()
        mock_broker.send_request = AsyncMock(return_value=mock_response)
        mock_broker.exchange_identities = {"binance": b"identity"}

        response = client.get("/exchanges/binance/fetch_ticker")
        assert response.status_code == 200
        mock_pm.restart_exchange.assert_not_called()
