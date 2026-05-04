"""Simplified tests for ZMQ broker."""

import asyncio
import json
from unittest.mock import MagicMock, patch, AsyncMock

import pytest
import zmq.asyncio

from ccxt_gateway.core.zmq_broker import ZMQBroker
from ccxt_gateway.core.protocol import create_request, create_response


class TestZMQBrokerSimple:
    """Simplified tests for ZMQ broker."""

    def test_init(self):
        """Test initialization."""
        broker = ZMQBroker("tcp://127.0.0.1:16570")
        assert broker.broker_address == "tcp://127.0.0.1:16570"
        assert broker.running is False
        assert len(broker.pending_requests) == 0
        assert len(broker.exchange_identities) == 0
        assert len(broker.subscriptions) == 0

    def test_register_exchange(self):
        """Test register_exchange."""
        broker = ZMQBroker()
        broker.register_exchange("binance", b"identity123")
        assert "binance" in broker.exchange_identities
        assert broker.exchange_identities["binance"] == b"identity123"
        assert b"identity123" in broker.identity_exchanges
        assert broker.identity_exchanges[b"identity123"] == "binance"

    def test_unregister_exchange(self):
        """Test unregister_exchange."""
        broker = ZMQBroker()
        broker.register_exchange("binance", b"identity123")
        assert "binance" in broker.exchange_identities

        broker.unregister_exchange("binance")
        assert "binance" not in broker.exchange_identities
        assert b"identity123" not in broker.identity_exchanges

    def test_register_subscription(self):
        """Test register_subscription."""
        broker = ZMQBroker()
        broker.register_subscription("sub-1", "binance")
        assert "sub-1" in broker.subscriptions
        assert broker.subscriptions["sub-1"] == "binance"

    def test_set_callback(self):
        """Test set_watch_update_callback."""
        broker = ZMQBroker()

        def dummy_callback(sub_id, data):
            pass

        broker.set_watch_update_callback(dummy_callback)
        assert broker.watch_update_callback is not None

    @pytest.mark.asyncio
    async def test_start_stop(self):
        """Test start and stop."""
        broker = ZMQBroker("tcp://127.0.0.1:16571")
        await broker.start()
        assert broker.running is True
        await broker.stop()
        assert broker.running is False

    @pytest.mark.asyncio
    async def test_send_request_exchange_not_found(self):
        """Test send_request when exchange not found."""
        broker = ZMQBroker()

        request_msg = create_request("fetch_ticker", {"symbol": "BTC/USDT"}, "nonexistent")
        response = await broker.send_request("nonexistent", request_msg)

        assert response is not None
        parsed = json.loads(response)
        assert "error" in parsed
        assert parsed["error_code"] == "EXCHANGE_NOT_FOUND"


class TestZMQBrokerMocked:
    """Tests with mocked socket."""

    @pytest.mark.asyncio
    async def test_send_request_timeout(self):
        """Test send_request timeout."""
        broker = ZMQBroker("tcp://127.0.0.1:16572")
        broker.running = True

        # Register exchange
        broker.register_exchange("binance", b"identity")

        # Mock the socket
        mock_socket = MagicMock(spec=zmq.asyncio.Socket)

        # Mock send_multipart to succeed
        mock_socket.send_multipart = AsyncMock()

        # Mock recv_multipart to timeout
        async def mock_recv():
            raise asyncio.TimeoutError()
        mock_socket.recv_multipart = mock_recv

        broker.socket = mock_socket

        # Create request
        request_msg = create_request("fetch_ticker", {"symbol": "BTC/USDT"}, "binance")

        # Send request (should timeout)
        response = await broker.send_request("binance", request_msg, timeout=0.1)

        assert response is not None
        parsed = json.loads(response)
        assert parsed["error"] == "Request timeout"
        assert parsed["error_code"] == "TIMEOUT"

    @pytest.mark.asyncio
    async def test_send_request_error(self):
        """Test send_request when error occurs."""
        broker = ZMQBroker("tcp://127.0.0.1:16573")
        broker.running = True

        # Register exchange
        broker.register_exchange("binance", b"identity")

        # Mock the socket to raise an error
        mock_socket = MagicMock(spec=zmq.asyncio.Socket)

        async def mock_send(*args, **kwargs):
            raise Exception("Connection error")

        mock_socket.send_multipart = mock_send
        broker.socket = mock_socket

        # Create request
        request_msg = create_request("fetch_ticker", {"symbol": "BTC/USDT"}, "binance")

        # Send request (should get error response)
        response = await broker.send_request("binance", request_msg)

        assert response is not None
        parsed = json.loads(response)
        assert "error" in parsed
        assert parsed["error_code"] == "SEND_ERROR"
