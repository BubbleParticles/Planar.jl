"""Tests for remaining coverage gaps - utils and websocket."""

import asyncio
import json
from unittest.mock import MagicMock, patch, AsyncMock

import pytest

from ccxt_gateway.utils.updates import get_current_version, get_latest_version, check_update, update_ccxt
from ccxt_gateway.api.websocket import set_broker_callback


class TestUtilsMore:
    """More tests for utils/updates.py remaining 7 lines."""

    def test_get_current_version_import_error(self):
        """Test get_current_version when ccxt not installed (lines 37-39)."""
        # Mock __import__ to fail for ccxt
        import builtins
        original_import = builtins.__import__

        def mock_import(name, *args, **kwargs):
            if name == 'ccxt':
                raise ImportError("No module named 'ccxt'")
            return original_import(name, *args, **kwargs)

        with patch('builtins.__import__', side_effect=mock_import):
            result = get_current_version()
            assert result is None

    @pytest.mark.asyncio
    async def test_get_latest_version_exception(self):
        """Test get_latest_version when request fails (lines 25-27)."""
        with patch('httpx.AsyncClient.get', side_effect=Exception("Network error")):
            result = await get_latest_version()
            assert result is None

    @pytest.mark.asyncio
    async def test_check_update_no_current(self):
        """Test check_update when current is None (line 117)."""
        with patch('ccxt_gateway.utils.updates.get_current_version', return_value=None):
            update_available, current, latest = await check_update()
            assert update_available is False
            assert current is None

    @pytest.mark.asyncio
    async def test_check_update_no_latest(self):
        """Test check_update when latest is None (lines 109-111)."""
        with patch('ccxt_gateway.utils.updates.get_current_version', return_value="1.0.0"), \
             patch('ccxt_gateway.utils.updates.get_latest_version', return_value=None):
            update_available, current, latest = await check_update()
            assert update_available is False
            assert latest is None

    @pytest.mark.asyncio
    async def test_check_update_version_error(self):
        """Test check_update when version comparison fails (lines 127-131)."""
        with patch('ccxt_gateway.utils.updates.get_current_version', return_value="invalid"), \
             patch('ccxt_gateway.utils.updates.get_latest_version', return_value="2.0.0"), \
             patch('packaging.version.parse', side_effect=Exception("Invalid version")):
            update_available, current, latest = await check_update()
            assert update_available is False

    @pytest.mark.asyncio
    async def test_update_ccxt_no_latest(self):
        """Test update_ccxt when latest_version is None (lines 109-111)."""
        with patch('ccxt_gateway.utils.updates.get_latest_version', return_value=None):
            success, msg = await update_ccxt()
            assert success is False
            assert "Failed to get latest version" in msg


class TestWebSocketMore:
    """More tests for websocket.py remaining 12 lines."""

    def test_set_broker_callback_no_attr(self):
        """Test set_broker_callback when broker lacks method (line 27)."""
        mock_broker = MagicMock(spec=[])  # Empty spec - no attributes

        # Should not raise even if broker doesn't have the method
        set_broker_callback(mock_broker)

    def test_websocket_json_error(self):
        """Test WebSocket JSON decode error (lines 62-63)."""
        from fastapi.testclient import TestClient
        from ccxt_gateway.main import app

        mock_broker = MagicMock()
        app.state.broker = mock_broker

        client = TestClient(app)
        with client.websocket_connect("/ws") as websocket:
            # Send invalid JSON
            websocket.send_text("not valid json")

            data = websocket.receive_json()
            assert data["type"] == "error"
            assert "json" in data["error"].lower()

    def test_websocket_exception(self):
        """Test WebSocket generic exception (lines 69-71)."""
        from fastapi.testclient import TestClient
        from ccxt_gateway.main import app

        mock_broker = MagicMock()
        app.state.broker = mock_broker

        client = TestClient(app)
        with client.websocket_connect("/ws") as websocket:
            # Send a message that causes processing error
            websocket.send_json({
                "type": "subscribe",
                "subscription_id": "test",
                "exchange_id": "nonexistent",  # No such exchange
                "method": "watch_ticker",
            })

            # Should receive error
            data = websocket.receive_json()
            assert "error" in data["type"].lower() or "error" in str(data)
