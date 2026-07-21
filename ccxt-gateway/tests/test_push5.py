"""Test for rest.py line 138 (empty response)."""
from unittest.mock import MagicMock, AsyncMock
import json
from fastapi.testclient import TestClient
from ccxt_gateway.main import app

class TestRestLine138More:
    def test_no_response_from_exchange(self):
        mock_broker = MagicMock()
        mock_pm = MagicMock()
        app.state.broker = mock_broker
        app.state.process_manager = mock_pm
        app.state.start_time = 1000.0
        mock_pm.processes = {"binance": MagicMock()}
        # Return empty bytes to trigger line 138
        mock_broker.send_request = AsyncMock(return_value=b"")
        mock_broker.exchange_identities = {"binance": b"identity"}
        
        client = TestClient(app)
        response = client.get("/exchanges/binance/fetch_ticker")
        assert response.status_code == 504
        data = response.json()
        assert "detail" in data

    def test_none_response_from_exchange(self):
        mock_broker = MagicMock()
        mock_pm = MagicMock()
        app.state.broker = mock_broker
        app.state.process_manager = mock_pm
        app.state.start_time = 1000.0
        mock_pm.processes = {"binance": MagicMock()}
        # Return None to trigger line 138
        mock_broker.send_request = AsyncMock(return_value=None)
        mock_broker.exchange_identities = {"binance": b"identity"}
        
        client = TestClient(app)
        response = client.get("/exchanges/binance/fetch_ticker")
        assert response.status_code == 504
