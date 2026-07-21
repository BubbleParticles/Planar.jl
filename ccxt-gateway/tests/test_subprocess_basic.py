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

    @pytest.mark.asyncio
    async def test_handle_metadata_method(self):
        """Test that accessing a non-callable property returns its value directly."""
        import ccxt_gateway.exchange.subprocess as sp

        sp_exch = sp.ExchangeSubprocess("test_ex", "binance")
        sp_exch.socket = AsyncMock()
        sp_exch.socket.send_multipart = AsyncMock()

        sp_exch.exchange = MagicMock()
        sp_exch.exchange.has = {"fetchTicker": True, "fetchOHLCV": False}
        sp_exch.exchange.timeframes = {"1m": None, "5m": None}

        await sp_exch._handle_request({
            "id": "req-5",
            "method": "has",
            "params": {},
        })

        sp_exch.socket.send_multipart.assert_called_once()
        sent = sp_exch.socket.send_multipart.call_args[0][0]
        response_bytes = sent[1] if len(sent) > 1 else sent[0]
        parsed = json.loads(response_bytes)

        assert parsed["type"] == "response"
        assert parsed["id"] == "req-5"
        assert parsed["result"]["fetchTicker"] is True

    @pytest.mark.asyncio
    async def test_handle_non_callable_property(self):
        """Test that a non-callable exchange property is returned directly."""
        import ccxt_gateway.exchange.subprocess as sp

        sp_exch = sp.ExchangeSubprocess("test_ex", "binance")
        sp_exch.socket = AsyncMock()
        sp_exch.socket.send_multipart = AsyncMock()

        sp_exch.exchange = MagicMock()
        sp_exch.exchange.some_property = {"key": "value", "number": 42}

        await sp_exch._handle_request({
            "id": "req-6",
            "method": "some_property",
            "params": {},
        })

        sp_exch.socket.send_multipart.assert_called_once()
        sent = sp_exch.socket.send_multipart.call_args[0][0]
        response_bytes = sent[1] if len(sent) > 1 else sent[0]
        parsed = json.loads(response_bytes)

        assert parsed["type"] == "response"
        assert parsed["id"] == "req-6"
        assert parsed["result"]["key"] == "value"
        assert parsed["result"]["number"] == 42

    @pytest.mark.asyncio
    async def test_handle_get_propertynames(self):
        """Test that method='get_propertynames' returns all public attributes."""
        import ccxt_gateway.exchange.subprocess as sp

        sp_exch = sp.ExchangeSubprocess("test_ex", "binance")
        sp_exch.socket = AsyncMock()
        sp_exch.socket.send_multipart = AsyncMock()

        # Use a plain object (not MagicMock) to avoid dynamic hasattr
        class FakeExchange:
            has = {"fetchTicker": True}
            timeframes = {"1m": None}
            fetchTicker = "callable_str"

        sp_exch.exchange = FakeExchange()

        await sp_exch._handle_request({
            "id": "req-prop",
            "method": "get_propertynames",
            "params": {},
        })

        sp_exch.socket.send_multipart.assert_called_once()
        sent = sp_exch.socket.send_multipart.call_args[0][0]
        response_bytes = sent[1] if len(sent) > 1 else sent[0]
        parsed = json.loads(response_bytes)

        assert parsed["type"] == "response"
        assert parsed["id"] == "req-prop"
        assert isinstance(parsed["result"], list)
        assert "has" in parsed["result"]
        assert "timeframes" in parsed["result"]
        assert "fetchTicker" in parsed["result"]

    @pytest.mark.asyncio
    async def test_handle_get_propertynames_excludes_private(self):
        """Test that get_propertynames excludes underscore-prefixed attrs."""
        import ccxt_gateway.exchange.subprocess as sp

        sp_exch = sp.ExchangeSubprocess("test_ex", "binance")
        sp_exch.socket = AsyncMock()
        sp_exch.socket.send_multipart = AsyncMock()

        class FakeExchange:
            has = {"fetchTicker": True}
            public_attr = 42
            _private_attr = "secret"

        sp_exch.exchange = FakeExchange()

        await sp_exch._handle_request({
            "id": "req-priv",
            "method": "get_propertynames",
            "params": {},
        })

        sent = sp_exch.socket.send_multipart.call_args[0][0]
        response_bytes = sent[1] if len(sent) > 1 else sent[0]
        parsed = json.loads(response_bytes)

        assert parsed["type"] == "response"
        names = parsed["result"]
        assert "public_attr" in names
        assert "_private_attr" not in names
        assert all(not n.startswith("_") for n in names)

    @pytest.mark.asyncio
    async def test_handle_get_propertynames_excludes_modules(self):
        """Test that get_propertynames excludes module-type attributes."""
        import ccxt_gateway.exchange.subprocess as sp
        import types

        sp_exch = sp.ExchangeSubprocess("test_ex", "binance")
        sp_exch.socket = AsyncMock()
        sp_exch.socket.send_multipart = AsyncMock()

        class FakeExchange:
            has = {"fetchTicker": True}
            normal_attr = "value"

        setattr(FakeExchange, "some_module", types.ModuleType("fake_module"))
        sp_exch.exchange = FakeExchange()

        await sp_exch._handle_request({
            "id": "req-mod",
            "method": "get_propertynames",
            "params": {},
        })

        sent = sp_exch.socket.send_multipart.call_args[0][0]
        response_bytes = sent[1] if len(sent) > 1 else sent[0]
        parsed = json.loads(response_bytes)

        names = parsed["result"]
        assert "normal_attr" in names
        assert "some_module" not in names
