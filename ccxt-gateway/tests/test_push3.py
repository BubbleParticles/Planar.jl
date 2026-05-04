"""Test for websocket.py remaining lines."""
from unittest.mock import MagicMock
from fastapi.testclient import TestClient
from ccxt_gateway.main import app
from ccxt_gateway.api.websocket import set_broker_callback

class TestWebSocketPush:
    def test_set_broker_callback_no_method(self):
        mock_broker = MagicMock(spec=[])
        set_broker_callback(mock_broker)

    def test_websocket_json_error(self):
        mock_broker = MagicMock()
        app.state.broker = mock_broker
        client = TestClient(app)
        with client.websocket_connect("/ws") as websocket:
            websocket.send_text("not valid json")
            data = websocket.receive_json()
            assert data["type"] == "error"
            assert "json" in data["error"].lower()

    def test_websocket_exception(self):
        mock_broker = MagicMock()
        app.state.broker = mock_broker
        client = TestClient(app)
        with client.websocket_connect("/ws") as websocket:
            websocket.send_json({
                "type": "subscribe",
                "subscription_id": "test",
                "exchange_id": "nonexistent",
                "method": "watch_ticker"
            })
            data = websocket.receive_json()
            assert "error" in data["type"].lower() or "error" in str(data)
