"""Easy remaining gaps."""
import pytest
from unittest.mock import MagicMock, AsyncMock, patch
import json
from ccxt_gateway.core.protocol import create_response

class TestEasyGaps:
    def test_websocket_connect_error(self):
        from fastapi.testclient import TestClient
        from ccxt_gateway.main import app
        mock_broker = MagicMock()
        app.state.broker = mock_broker
        
        client = TestClient(app)
        with client.websocket_connect("/ws") as ws:
            pass
    
    def test_rest_missing_exchange(self):
        from fastapi.testclient import TestClient
        from ccxt_gateway.main import app
        
        mock_broker = MagicMock()
        mock_pm = MagicMock()
        app.state.broker = mock_broker
        app.state.process_manager = mock_pm
        app.state.start_time = 1000.0
        mock_pm.processes = {}
        
        client = TestClient(app)
        response = client.get("/exchanges/binance/fetch_ticker")
        assert response.status_code == 404
    
    def test_rest_error_response(self):
        from fastapi.testclient import TestClient
        from ccxt_gateway.main import app
        
        mock_broker = MagicMock()
        mock_pm = MagicMock()
        app.state.broker = mock_broker
        app.state.process_manager = mock_pm
        app.state.start_time = 1000.0
        mock_pm.processes = {"binance": MagicMock()}
        
        error_resp = create_response(request_id="test", error="Invalid method", error_code="INVALID")
        mock_broker.send_request = AsyncMock(return_value=error_resp)
        mock_broker.exchange_identities = {"binance": b"id"}
        
        client = TestClient(app)
        response = client.get("/exchanges/binance/fetch_ticker")
        assert response.status_code == 500
