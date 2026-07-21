"""Test for websocket.py lines 161-169 (unsubscribe)."""
from unittest.mock import MagicMock
from fastapi.testclient import TestClient
from ccxt_gateway.main import app

class TestWebSocketUnsubscribe:
    def test_unsubscribe_not_found(self):
        from ccxt_gateway.api.websocket import active_subscriptions, exchange_subscriptions
        mock_broker = MagicMock()
        app.state.broker = mock_broker
        
        client = TestClient(app)
        with client.websocket_connect("/ws") as websocket:
            # Try to unsubscribe non-existent
            websocket.send_json({
                "type": "unsubscribe",
                "subscription_id": "non-existent"
            })
            
            # Should receive error
            data = websocket.receive_json()
            assert data["type"] == "error"
            assert "not found" in data["error"].lower()

    def test_unsubscribe_no_id(self):
        mock_broker = MagicMock()
        app.state.broker = mock_broker
        
        client = TestClient(app)
        with client.websocket_connect("/ws") as websocket:
            # Unsubscribe with no id
            websocket.send_json({
                "type": "unsubscribe"
            })
            
            # Should receive error
            data = websocket.receive_json()
            assert data["type"] == "error"

    def test_unsubscribe_empty_id(self):
        mock_broker = MagicMock()
        app.state.broker = mock_broker
        
        client = TestClient(app)
        with client.websocket_connect("/ws") as websocket:
            # Unsubscribe with empty id
            websocket.send_json({
                "type": "unsubscribe",
                "subscription_id": ""
            })
            
            # Should receive error
            data = websocket.receive_json()
            assert data["type"] == "error"
