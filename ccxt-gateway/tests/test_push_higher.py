"""Push coverage higher - WebSocket and ProcessManager gaps."""

import asyncio
import json
from unittest.mock import MagicMock, patch, AsyncMock

import pytest

from ccxt_gateway.api.websocket import (
    active_subscriptions, exchange_subscriptions,
    forward_watch_update, cleanup_websocket, set_broker_callback
)
from ccxt_gateway.core.process_manager import ProcessManager, ExchangeProcess
from ccxt_gateway.utils.updates import check_update, update_ccxt


class TestWebSocketLines:
    """Test websocket.py remaining 12 lines."""

    def test_set_broker_callback_no_broker(self):
        """Test line 27 - broker has no set_watch_update_callback."""
        mock_broker = MagicMock(spec=[])  # Empty spec
        # Should not raise
        set_broker_callback(mock_broker)

    def test_websocket_send_json(self):
        """Test lines 62-63 - JSON decode error."""
        from fastapi.testclient import TestClient
        from ccxt_gateway.main import app

        mock_broker = MagicMock()
        app.state.broker = mock_broker

        client = TestClient(app)
        with client.websocket_connect("/ws") as websocket:
            websocket.send_text("not valid json")

            data = websocket.receive_json()
            assert data["type"] == "error"
            assert "json" in data["error"].lower()

    def test_websocket_exception(self):
        """Test lines 69-71 - generic exception."""
        from fastapi.testclient import TestClient
        from ccxt_gateway.main import app

        mock_broker = MagicMock()
        app.state.broker = mock_broker

        client = TestClient(app)
        with client.websocket_connect("/ws") as websocket:
            # Send invalid message to trigger exception
            websocket.send_json({
                "type": "subscribe",
                "subscription_id": "test",
                "exchange_id": "nonexistent",  # Will cause error
                "method": "watch_ticker"
            })

            data = websocket.receive_json()
            assert "error" in data["type"].lower() or "error" in str(data)

    def test_forward_watch_update(self):
        """Test lines 161-169 - forward_watch_update."""
        active_subscriptions.clear()
        exchange_subscriptions.clear()

        mock_ws = MagicMock()
        active_subscriptions["sub-1"] = mock_ws

        with patch('asyncio.create_task') as mock_create:
            forward_watch_update("sub-1", {"price": 50000})
            mock_create.assert_called_once()

    def test_forward_watch_update_no_sub(self):
        """Test forward_watch_update when subscription not found."""
        active_subscriptions.clear()

        # Should not raise
        forward_watch_update("nonexistent", {"price": 50000})


class TestProcessManagerLines:
    """Test process_manager.py remaining 24 lines."""

    @pytest.mark.asyncio
    async def test_start_exchange_already_running(self):
        """Test line 129 - already running check."""
        pm = ProcessManager()
        pm.running = True

        mock_proc = MagicMock()
        pm.processes["binance"] = mock_proc()

        result = await pm.start_exchange("binance", "binance")
        assert result is False

    @pytest.mark.asyncio
    async def test_start_exchange_success(self):
        """Test lines 146-202 - successful start."""
        pm = ProcessManager()
        pm.running = True
        pm.startup_timeout = 5

        mock_process = MagicMock()
        mock_process.pid = 12345
        mock_process.stdout = MagicMock()
        mock_process.stderr = MagicMock()

        with patch('asyncio.create_subprocess_exec', new_callable=AsyncMock, return_value=mock_process), \
             patch.object(pm, '_wait_for_ready', new_callable=AsyncMock):

            result = await pm.start_exchange("binance", "binance")
            assert result is True

    @pytest.mark.asyncio
    async def test_stop_exchange_and_cleanup(self):
        """Test lines 248-263 - stop and cleanup."""
        pm = ProcessManager()

        mock_process = MagicMock()
        mock_process.pid = 12345
        mock_process.returncode = None
        mock_process.terminate = MagicMock()
        mock_process.wait = AsyncMock()

        proc = ExchangeProcess(
            exchange_id="binance",
            exchange_name="binance",
            process=mock_process,
            started_at=time.time(),
        )
        pm.processes["binance"] = proc

        await pm.stop_exchange("binance")

        assert "binance" not in pm.processes
        mock_process.terminate.assert_called_once()

    @pytest.mark.asyncio
    async def test_monitor_loop_running(self):
        """Test lines 273-280 - monitor loop."""
        pm = ProcessManager()
        pm.running = True
        pm.check_interval = 0.1

        call_count = 0

        async def mock_check():
            nonlocal call_count
            call_count += 1
            if call_count >= 3:
                pm.running = False

        pm._check_all_processes = mock_check

        await pm._monitor_loop()

        assert call_count == 3

    @pytest.mark.asyncio
    async def test_check_all_processes_ok(self):
        """Test lines 284-307 - check all processes."""
        pm = ProcessManager()
        pm.auto_restart = False

        mock_proc = MagicMock()
        mock_proc.is_running = True
        mock_proc.update_memory = MagicMock()
        mock_proc.rss_mb = 100.0  # Under limit
        pm.processes["binance"] = mock_proc

        await pm._check_all_processes()

        mock_proc.update_memory.assert_called_once()


import time  # Needed for ProcessManager tests
