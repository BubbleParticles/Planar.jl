"""Test for rest.py line 138."""
from unittest.mock import MagicMock, AsyncMock
import json
from fastapi.testclient import TestClient
from ccxt_gateway.main import app

class TestRestLine138:
    def test_error_response(self):
        mock_broker = MagicMock()
        mock_pm = MagicMock()
        app.state.broker = mock_broker
        app.state.process_manager = mock_pm
        app.state.start_time = 1000.0
        mock_pm.processes = {"binance": MagicMock()}
        error_response = json.dumps({
            "type": "response",
            "id": "test-id",
            "error": "Some error",
            "error_code": "SOME_ERROR"
        }).encode()
        mock_broker.send_request = AsyncMock(return_value=error_response)
        mock_broker.exchange_identities = {"binance": b"identity"}
        client = TestClient(app)
        response = client.get("/exchanges/binance/fetch_ticker")
        assert response.status_code == 500
        data = response.json()
        assert "detail" in data
