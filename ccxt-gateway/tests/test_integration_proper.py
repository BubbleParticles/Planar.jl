"""Integration tests using actual ccxt_gateway classes."""
import pytest
import asyncio

from ccxt_gateway.core.zmq_broker import ZMQBroker
from ccxt_gateway.core.protocol import (
    create_request, create_response, create_subprocess_ready, parse_message
)


@pytest.mark.asyncio
async def test_zmq_broker_start_stop():
    """Test broker can start and stop."""
    broker = ZMQBroker()
    await broker.start()
    assert broker.running is True
    await broker.stop()
    assert broker.running is False


def test_protocol_functions():
    """Test protocol creation functions."""
    # Test create_request
    req = create_request("fetch_balance", {}, "binance")
    data = parse_message(req)
    assert data["type"] == "request"
    assert data["method"] == "fetch_balance"
    assert data["exchange_id"] == "binance"
    assert "id" in data
    
    # Test create_response
    resp = create_response("req-123", {"result": "ok"})
    data = parse_message(resp)
    assert data["type"] == "response"
    assert data["id"] == "req-123"
    assert data["result"] == {"result": "ok"}  # Uses "result", not "data"!
    
    # Test create_subprocess_ready
    ready = create_subprocess_ready("binance", 12345)
    data = parse_message(ready)
    assert data["type"] == "subprocess_ready"
    assert data["exchange_id"] == "binance"
    assert data["pid"] == 12345


def test_exchange_subprocess_class():
    """Test ExchangeSubprocess class."""
    from ccxt_gateway.exchange.subprocess import ExchangeSubprocess
    
    assert hasattr(ExchangeSubprocess, 'start')
    assert hasattr(ExchangeSubprocess, '_message_loop')
    assert hasattr(ExchangeSubprocess, '_handle_request')
    assert hasattr(ExchangeSubprocess, '_cleanup')


def test_zmq_broker_class():
    """Test ZMQBroker class."""
    from ccxt_gateway.core.zmq_broker import ZMQBroker
    
    assert hasattr(ZMQBroker, 'start')
    assert hasattr(ZMQBroker, 'stop')
    assert hasattr(ZMQBroker, 'send_request')
    assert hasattr(ZMQBroker, '_message_loop')
