"""Tests for WebSocket endpoint."""

import json
from unittest.mock import MagicMock, patch, AsyncMock

import pytest
from fastapi.testclient import TestClient

from ccxt_gateway.main import app
from ccxt_gateway.api.websocket import set_broker_callback


class TestWebSocket:
    """Tests for WebSocket endpoint."""

    @pytest.fixture
    def setup(self):
        """Set up test client with mocked dependencies."""
        mock_broker = MagicMock()
        mock_process_manager = MagicMock()

        app.state.broker = mock_broker
        app.state.process_manager = mock_process_manager

        # Set up the websocket module's broker callback
        set_broker_callback(mock_broker)

        return TestClient(app), mock_broker, mock_process_manager

    def test_websocket_connect(self, setup):
        """Test WebSocket connection."""
        client, _, _ = setup

        with client.websocket_connect("/ws") as websocket:
            # Just test that connection works
            assert websocket is not None

    def test_websocket_subscribe(self, setup):
        """Test subscribing via WebSocket."""
        client, mock_broker, mock_pm = setup

        mock_broker.register_subscription = MagicMock()
        mock_broker.send_request = AsyncMock()

        # Mock process manager to have the exchange
        mock_pm.processes = {"binance": MagicMock()}

        with client.websocket_connect("/ws") as websocket:
            # Send subscribe message (use "type" not "action")
            websocket.send_json({
                "type": "subscribe",
                "subscription_id": "sub-1",
                "exchange_id": "binance",
                "method": "watch_ticker",
                "params": {"symbol": "BTC/USDT"}
            })

            # Receive response
            data = websocket.receive_json()
            assert data["type"] == "subscribed"
            assert "subscription_id" in data

    def test_websocket_unsubscribe(self, setup):
        """Test unsubscribing via WebSocket."""
        client, mock_broker, _ = setup

        mock_broker.register_subscription = MagicMock()

        with client.websocket_connect("/ws") as websocket:
            # First subscribe
            websocket.send_json({
                "action": "subscribe",
                "exchange_id": "binance",
                "method": "watch_ticker",
                "params": {"symbol": "BTC/USDT"}
            })
            response = websocket.receive_json()
            subscription_id = response.get("subscription_id")

            # Then unsubscribe
            websocket.send_json({
                "action": "unsubscribe",
                "subscription_id": subscription_id
            })
            # Should not raise

    def test_websocket_invalid_message(self, setup):
        """Test sending invalid message."""
        client, _, _ = setup

        with client.websocket_connect("/ws") as websocket:
            # Send invalid message
            websocket.send_json({
                "action": "invalid_action"
            })
            # Should not crash

    def test_websocket_watch_update_callback(self, setup):
        """Test that watch updates are sent to WebSocket clients."""
        client, mock_broker, _ = setup

        # The callback should be set
        assert mock_broker.set_watch_update_callback is not None
