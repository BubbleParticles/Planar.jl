"""Pytest configuration: mock ZMQ to avoid port conflicts when gateway is running."""

from unittest.mock import MagicMock, AsyncMock

import pytest


@pytest.fixture(autouse=True)
def _mock_zmq():
    """Mock zmq.asyncio.Context so ZMQBroker doesn't bind real ports."""
    import zmq.asyncio

    mock_socket = MagicMock(spec=zmq.asyncio.Socket)
    mock_socket.send_multipart = AsyncMock()
    mock_socket.recv_multipart = AsyncMock()
    mock_socket.bind = MagicMock()
    mock_socket.close = MagicMock()
    mock_socket.setsockopt = MagicMock()

    mock_context = MagicMock(spec=zmq.asyncio.Context)
    mock_context.socket.return_value = mock_socket
    mock_context.term = MagicMock()

    original = zmq.asyncio.Context
    zmq.asyncio.Context = lambda *a, **kw: mock_context
    yield
    zmq.asyncio.Context = original
