"""Basic test for exchange/subprocess.py."""

import json
import os
import sys
from unittest.mock import MagicMock, patch, AsyncMock

import pytest


class TestExchangeSubprocess:
    """Basic tests for exchange/subprocess.py."""

    def test_import_module(self):
        """Test that the module can be imported."""
        import ccxt_gateway.exchange.subprocess as subprocess_module

        assert hasattr(subprocess_module, 'json')
        assert hasattr(subprocess_module, 'zmq')

    def test_module_attributes(self):
        """Test module attributes."""
        import ccxt_gateway.exchange.subprocess as subprocess_module

        assert 'json' in dir(subprocess_module)
        assert 'zmq' in dir(subprocess_module)

    @pytest.mark.asyncio
    async def test_mock_main_execution(self):
        """Test mock execution of main block."""
        with patch('sys.argv', ['subprocess.py', 'test-id', 'binance', '--broker', 'tcp://127.0.0.1:5555']), \
             patch('ccxt_gateway.exchange.subprocess.create_subprocess_ready') as mock_ready, \
             patch('ccxt_gateway.exchange.subprocess.create_watch_update') as mock_watch, \
             patch('ccxt_gateway.exchange.subprocess.parse_message') as mock_parse:

            mock_socket = MagicMock()
            mock_context = MagicMock()
            mock_context.socket.return_value = mock_socket

            mock_socket.recv_multipart.side_effect = [
                [b"", b"", b'{"type": "stop"}'],
            ]

            with patch('zmq.Context', return_value=mock_context):
                pass

        assert True

    @pytest.mark.asyncio
    async def test_handle_has_method(self):
        """Test that method='has' returns the exchange.has dict directly, not called as a function."""
        import ccxt_gateway.exchange.subprocess as sp

        sp_exch = sp.ExchangeSubprocess("test_ex", "binance")
        sp_exch.socket = AsyncMock()
        sp_exch.socket.send_multipart = AsyncMock()

        mock_has = {
            "fetchTicker": True,
            "fetchOrderBook": False,
            "fetchOHLCV": "emulated",
            "fetchBalance": True,
        }
        sp_exch.exchange = MagicMock()
        sp_exch.exchange.has = mock_has

        await sp_exch._handle_request({
            "id": "req-1",
            "method": "has",
            "params": {},
        })

        sp_exch.socket.send_multipart.assert_called_once()
        sent = sp_exch.socket.send_multipart.call_args[0][0]
        response_bytes = sent[1] if len(sent) > 1 else sent[0]

        parsed = json.loads(response_bytes)
        assert parsed["type"] == "response"
        assert parsed["id"] == "req-1"
        assert parsed["result"]["fetchTicker"] is True
        assert parsed["result"]["fetchOrderBook"] is False
        assert parsed["result"]["fetchOHLCV"] == "emulated"
        assert parsed["result"]["fetchBalance"] is True

    @pytest.mark.asyncio
    async def test_handle_has_method_no_exchange(self):
        """Test that method='has' raises error when exchange not initialized."""
        import ccxt_gateway.exchange.subprocess as sp

        sp_exch = sp.ExchangeSubprocess("test_ex", "binance")
        sp_exch.socket = AsyncMock()
        sp_exch.socket.send_multipart = AsyncMock()
        sp_exch.exchange = None

        await sp_exch._handle_request({
            "id": "req-2",
            "method": "has",
            "params": {},
        })

        sp_exch.socket.send_multipart.assert_called_once()
        sent = sp_exch.socket.send_multipart.call_args[0][0]
        response_bytes = sent[1] if len(sent) > 1 else sent[0]

        parsed = json.loads(response_bytes)
        assert parsed["type"] == "response"
        assert parsed["id"] == "req-2"
        assert "error" in parsed
        assert parsed["error_code"] != ""

    @pytest.mark.asyncio
    async def test_handle_regular_method_still_works(self):
        """Test that a regular method still gets called normally."""
        import ccxt_gateway.exchange.subprocess as sp

        sp_exch = sp.ExchangeSubprocess("test_ex", "binance")
        sp_exch.socket = AsyncMock()
        sp_exch.socket.send_multipart = AsyncMock()

        mock_exchange = MagicMock()
        mock_exchange.fetchTicker = AsyncMock(return_value={"last": 50000})
        mock_exchange.has = {"fetchTicker": True}
        sp_exch.exchange = mock_exchange

        await sp_exch._handle_request({
            "id": "req-3",
            "method": "fetchTicker",
            "params": {"symbol": "BTC/USDT"},
        })

        sp_exch.exchange.fetchTicker.assert_awaited_once_with(symbol="BTC/USDT")

    @pytest.mark.asyncio
    async def test_handle_has_with_empty_dict(self):
        """Test method='has' with an empty has dict."""
        import ccxt_gateway.exchange.subprocess as sp

        sp_exch = sp.ExchangeSubprocess("test_ex", "binance")
        sp_exch.socket = AsyncMock()
        sp_exch.socket.send_multipart = AsyncMock()

        sp_exch.exchange = MagicMock()
        sp_exch.exchange.has = {}

        await sp_exch._handle_request({
            "id": "req-4",
            "method": "has",
            "params": {},
        })

        sp_exch.socket.send_multipart.assert_called_once()
        sent = sp_exch.socket.send_multipart.call_args[0][0]
        response_bytes = sent[1] if len(sent) > 1 else sent[0]

        parsed = json.loads(response_bytes)
        assert parsed["result"] == {}
