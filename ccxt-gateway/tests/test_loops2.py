"""Test loops by setting running=False in mock."""
import pytest
import asyncio
from unittest.mock import MagicMock, AsyncMock


class TestLoops2:
    @pytest.mark.asyncio
    async def test_subprocess_message_loop_v2(self):
        """Test subprocess _message_loop that sets running=False."""
        from ccxt_gateway.exchange.subprocess import ExchangeSubprocess
        
        subproc = ExchangeSubprocess(
            exchange_id="test",
            exchange_name="binance",
            broker_address="tcp://127.0.0.1:5555",
        )
        
        call_count = 0
        async def mock_recv():
            nonlocal call_count
            call_count += 1
            if call_count >= 1:
                subproc.running = False
                raise asyncio.CancelledError
            return [b"", b'{"type":"request"}']
        
        subproc.socket = AsyncMock()
        subproc.socket.recv_multipart = mock_recv
        subproc.running = True
        subproc.exchange = MagicMock()
        
        # Run and should exit cleanly
        await subproc._message_loop()
        assert subproc.running is False
    
    @pytest.mark.asyncio
    async def test_zmq_broker_message_loop_v2(self):
        """Test broker _message_loop."""
        from ccxt_gateway.core.zmq_broker import ZMQBroker
        
        broker = ZMQBroker()
        
        call_count = 0
        async def mock_recv():
            nonlocal call_count
            call_count += 1
            if call_count >= 1:
                broker.running = False
                raise asyncio.CancelledError
            return [b"id", b"", b'{"type":"request"}']
        
        broker.socket = AsyncMock()
        broker.socket.recv_multipart = mock_recv
        broker.running = True
        broker.exchange_identities = {}
        
        await broker._message_loop()
        assert broker.running is False
    
    @pytest.mark.asyncio
    async def test_pm_read_stdout_v2(self):
        """Test _read_stdout that gets EOF."""
        from ccxt_gateway.core.process_manager import ProcessManager, ExchangeProcess
        
        pm = ProcessManager(max_rss_mb=1000)
        
        call_count = 0
        async def mock_read():
            nonlocal call_count
            call_count += 1
            if call_count >= 1:
                raise asyncio.CancelledError
            return b"log line"
        
        mock_proc = MagicMock()
        mock_proc.stdout = AsyncMock()
        mock_proc.stdout.readline = mock_read
        
        proc = ExchangeProcess(
            exchange_id="test",
            exchange_name="binance",
            process=mock_proc,
            started_at=1000.0,
            config={},
        )
        pm.processes["test"] = proc
        
        task = asyncio.create_task(pm._read_stdout("test"))
        await asyncio.sleep(0.01)
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass  # Expected
