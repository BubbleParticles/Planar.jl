"""Test individual methods that don't require infinite loops."""
import pytest
import asyncio
from unittest.mock import MagicMock, AsyncMock
import time


class TestSubprocessMethods:
    def test_init(self):
        from ccxt_gateway.exchange.subprocess import ExchangeSubprocess
        subproc = ExchangeSubprocess(
            exchange_id="binance",
            exchange_name="binance",
            broker_address="tcp://127.0.0.1:5555",
            api_key="key",
        )
        assert subproc.exchange_id == "binance"
    
    @pytest.mark.asyncio
    async def test_send_ready(self):
        from ccxt_gateway.exchange.subprocess import ExchangeSubprocess
        subproc = ExchangeSubprocess(
            exchange_id="binance",
            exchange_name="binance", 
            broker_address="tcp://127.0.0.1:5555",
        )
        mock_socket = AsyncMock()
        subproc.socket = mock_socket
        await subproc._send_ready()
        mock_socket.send_multipart.assert_called_once()
    
    @pytest.mark.asyncio
    async def test_call_method(self):
        from ccxt_gateway.exchange.subprocess import ExchangeSubprocess
        subproc = ExchangeSubprocess(
            exchange_id="binance",
            exchange_name="binance",
            broker_address="tcp://127.0.0.1:5555",
        )
        mock_method = AsyncMock(return_value={"BTC": 1.0})
        result = await subproc._call_method(mock_method, {})
        assert result == {"BTC": 1.0}
    
    @pytest.mark.asyncio
    async def test_make_serializable(self):
        from ccxt_gateway.exchange.subprocess import ExchangeSubprocess
        subproc = ExchangeSubprocess(
            exchange_id="binance",
            exchange_name="binance",
            broker_address="tcp://127.0.0.1:5555",
        )
        assert subproc._make_serializable("str") == "str"
        assert subproc._make_serializable(None) is None
    
    @pytest.mark.asyncio
    async def test_cleanup(self):
        from ccxt_gateway.exchange.subprocess import ExchangeSubprocess
        subproc = ExchangeSubprocess(
            exchange_id="binance",
            exchange_name="binance",
            broker_address="tcp://127.0.0.1:5555",
        )
        mock_socket = MagicMock()
        mock_ctx = MagicMock()
        subproc.socket = mock_socket
        subproc.context = mock_ctx
        await subproc._cleanup()
        mock_socket.close.assert_called_once()


class TestProcessManagerMethods:
    def test_pm_init(self):
        from ccxt_gateway.core.process_manager import ProcessManager
        pm = ProcessManager(max_rss_mb=1000, auto_restart=True)
        assert pm.max_rss_mb == 1000
    
    def test_ep_init(self):
        from ccxt_gateway.core.process_manager import ExchangeProcess
        proc = ExchangeProcess(
            exchange_id="binance",
            exchange_name="binance",
            process=MagicMock(),
            started_at=time.time(),
            config={},
        )
        assert proc.exchange_id == "binance"
    
    @pytest.mark.asyncio
    async def test_cleanup_process(self):
        from ccxt_gateway.core.process_manager import ProcessManager, ExchangeProcess
        pm = ProcessManager(max_rss_mb=1000)
        proc = ExchangeProcess(
            exchange_id="test",
            exchange_name="binance",
            process=MagicMock(),
            started_at=time.time(),
            config={},
        )
        pm.processes["test"] = proc
        await pm._cleanup_process("test")
        assert "test" not in pm.processes


class TestZMQBrokerMethods:
    @pytest.mark.asyncio
    async def test_broker_init(self):
        from ccxt_gateway.core.zmq_broker import ZMQBroker
        broker = ZMQBroker()
        assert broker.broker_address == "tcp://127.0.0.1:5555"
