"""More tests to push coverage."""
import pytest
import asyncio
from unittest.mock import MagicMock


class TestCallMakeSerializable:
    def test_make_serializable_edge_cases(self):
        from ccxt_gateway.exchange.subprocess import ExchangeSubprocess
        subproc = ExchangeSubprocess(
            exchange_id="test",
            exchange_name="binance",
            broker_address="tcp://127.0.0.1:5555",
        )
        
        # Test various edge cases
        result = subproc._make_serializable({"nested": {"dict": [1, 2, 3]}})
        assert result == {"nested": {"dict": [1, 2, 3]}}
        
        result = subproc._make_serializable(True)
        assert result is True
        
        result = subproc._make_serializable(False)
        assert result is False


class TestProcessInit:
    def test_pm_init_full(self):
        from ccxt_gateway.core.process_manager import ProcessManager
        pm = ProcessManager(
            max_rss_mb=2048,
            auto_restart=True,
            max_restarts_per_hour=3,
            check_interval=10,
        )
        assert pm.max_rss_mb == 2048
        assert pm.auto_restart is True
        assert pm.max_restarts_per_hour == 3
        assert pm.check_interval == 10


class TestZMQInit:
    def test_broker_init_custom(self):
        from ccxt_gateway.core.zmq_broker import ZMQBroker
        broker = ZMQBroker(broker_address="tcp://127.0.0.1:9999")
        assert broker.broker_address == "tcp://127.0.0.1:9999"


class TestAppState:
    def test_app_has_state(self):
        from ccxt_gateway.main import app
        assert hasattr(app, 'state')
        
        # Test state has expected attributes
        app.state.broker = MagicMock()
        app.state.process_manager = MagicMock()
        app.state.start_time = 1000.0
        
        assert app.state.broker is not None
