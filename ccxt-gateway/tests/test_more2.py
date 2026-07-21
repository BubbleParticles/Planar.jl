"""More tests for WebSocket and process manager."""

import asyncio
import json
from unittest.mock import MagicMock, patch, AsyncMock

import pytest
from fastapi.testclient import TestClient

from ccxt_gateway.main import app
from ccxt_gateway.api.websocket import (
    active_subscriptions, exchange_subscriptions,
    forward_watch_update, cleanup_websocket
)
from ccxt_gateway.core.process_manager import ProcessManager


class TestWebSocketMore:
    """More tests for WebSocket endpoint."""

    @pytest.fixture
    def setup(self):
        """Set up test client with mocked dependencies."""
        mock_broker = MagicMock()
        mock_process_manager = MagicMock()

        app.state.broker = mock_broker
        app.state.process_manager = mock_process_manager

        return TestClient(app), mock_broker, mock_process_manager

    def test_subscribe_missing_fields(self, setup):
        """Test subscribe with missing fields."""
        client, _, _ = setup

        with client.websocket_connect("/ws") as websocket:
            websocket.send_json({
                "type": "subscribe",
                # Missing subscription_id, exchange_id, method
            })

            data = websocket.receive_json()
            assert data["type"] == "error"
            assert "Missing required fields" in data["error"]

    def test_subscribe_exchange_not_found(self, setup):
        """Test subscribe when exchange not found."""
        client, _, mock_pm = setup

        mock_pm.processes = {}  # No exchanges

        with client.websocket_connect("/ws") as websocket:
            websocket.send_json({
                "type": "subscribe",
                "subscription_id": "sub-1",
                "exchange_id": "nonexistent",
                "method": "watch_ticker",
            })

            data = websocket.receive_json()
            assert data["type"] == "error"
            assert "not found" in data["error"].lower()

    def test_subscribe_broker_not_available(self, setup):
        """Test subscribe when broker not available."""
        client, _, mock_pm = setup

        # Remove broker from app state
        app.state.broker = None

        mock_pm.processes = {"binance": MagicMock()}

        with client.websocket_connect("/ws") as websocket:
            websocket.send_json({
                "type": "subscribe",
                "subscription_id": "sub-1",
                "exchange_id": "binance",
                "method": "watch_ticker",
            })

            data = websocket.receive_json()
            assert data["type"] == "error"
            assert "broker" in data["error"].lower()

        # Restore broker
        app.state.broker = MagicMock()

    def test_unsubscribe_not_found(self, setup):
        """Test unsubscribe when subscription not found."""
        client, _, _ = setup

        with client.websocket_connect("/ws") as websocket:
            websocket.send_json({
                "type": "unsubscribe",
                "subscription_id": "nonexistent",
            })

            data = websocket.receive_json()
            assert data["type"] == "error"
            assert "not found" in data["error"].lower()

    def test_invalid_json(self, setup):
        """Test sending invalid JSON."""
        client, _, _ = setup

        with client.websocket_connect("/ws") as websocket:
            # Send raw text that's not JSON
            websocket.send_text("not json")

            data = websocket.receive_json()
            assert data["type"] == "error"
            assert "json" in data["error"].lower()

    def test_forward_watch_update(self, setup):
        """Test forward_watch_update function."""
        # Clear any existing subscriptions
        active_subscriptions.clear()
        exchange_subscriptions.clear()

        # Create a mock websocket
        mock_ws = MagicMock()
        active_subscriptions["sub-1"] = mock_ws

        # Mock asyncio.create_task to avoid needing a running loop
        with patch('asyncio.create_task') as mock_create_task:
            forward_watch_update("sub-1", {"price": 50000})

            # Check that create_task was called
            mock_create_task.assert_called_once()

    def test_cleanup_websocket(self, setup):
        """Test cleanup_websocket function."""
        # Clear and set up test data
        active_subscriptions.clear()
        exchange_subscriptions.clear()

        # Create a mock websocket
        mock_ws = MagicMock()
        active_subscriptions["sub-1"] = mock_ws
        active_subscriptions["sub-2"] = mock_ws
        exchange_subscriptions["binance"] = ["sub-1", "sub-2"]

        # Clean up (need to run in async context)
        import asyncio
        asyncio.get_event_loop().run_until_complete(cleanup_websocket(mock_ws))

        # Check that subscriptions were removed
        assert "sub-1" not in active_subscriptions
        assert "sub-2" not in active_subscriptions


class TestProcessManagerMore:
    """More tests for ProcessManager."""

    @pytest.mark.asyncio
    async def test_start_exchange_timeout(self):
        """Test start_exchange when subprocess times out."""
        pm = ProcessManager()
        pm.running = True
        pm.startup_timeout = 1  # Short timeout

        # Mock asyncio.create_subprocess_exec to return a process
        mock_process = MagicMock()
        mock_process.pid = 12345
        mock_process.stdout = MagicMock()
        mock_process.stderr = MagicMock()

        with patch('asyncio.create_subprocess_exec', new_callable=AsyncMock, return_value=mock_process):
            # Mock _wait_for_ready to raise TimeoutError
            pm._wait_for_ready = AsyncMock(side_effect=asyncio.TimeoutError())

            result = await pm.start_exchange("binance", "binance")
            assert result is False

    @pytest.mark.asyncio
    async def test_start_exchange_exception(self):
        """Test start_exchange when exception occurs."""
        pm = ProcessManager()

        # Mock asyncio.create_subprocess_exec to raise an exception
        with patch('asyncio.create_subprocess_exec', side_effect=Exception("Failed")):
            result = await pm.start_exchange("binance", "binance")
            assert result is False

    @pytest.mark.asyncio
    async def test_stop_exchange_with_timeout(self):
        """Test stop_exchange when process takes too long to terminate."""
        pm = ProcessManager()

        mock_process = MagicMock()
        mock_process.pid = 12345
        mock_process.returncode = None  # Still running
        mock_process.terminate = MagicMock()

        # Mock wait to raise TimeoutError
        async def mock_wait(*args, **kwargs):
            raise asyncio.TimeoutError()

        mock_process.wait = mock_wait

        mock_proc = MagicMock()
        mock_proc.process = mock_process

        pm.processes["binance"] = mock_proc

        await pm.stop_exchange("binance")

        # Should have called terminate and then kill
        mock_process.terminate.assert_called_once()
        mock_process.kill.assert_called_once()

    @pytest.mark.asyncio
    async def test_monitor_loop_with_process_check(self):
        """Test _monitor_loop checks processes."""
        pm = ProcessManager()
        pm.running = True
        pm.check_interval = 0.1  # Short interval for testing

        # Create a mock process that is running
        mock_proc = MagicMock()
        mock_proc.is_running = True
        mock_proc.update_memory = MagicMock()
        mock_proc.rss_mb = 100.0  # Under limit
        pm.processes["binance"] = mock_proc

        # Run the loop for a short time then stop
        async def run_and_stop():
            task = asyncio.create_task(pm._monitor_loop())
            await asyncio.sleep(0.2)
            pm.running = False
            await task

        await run_and_stop()

        # Check that update_memory was called
        mock_proc.update_memory.assert_called()
