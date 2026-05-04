"""Comprehensive tests for ccxt-gateway - aiming for 100% coverage."""

import asyncio
import json
import os
import time
from typing import Any, Dict
from unittest.mock import MagicMock, patch, AsyncMock

import pytest

# Import all modules to test
from ccxt_gateway.config import Settings, ServerConfig, ZMQConfig, ProcessManagerConfig
from ccxt_gateway.core.protocol import (
    create_request, create_response, create_subprocess_ready,
    create_heartbeat, create_watch_update, parse_message,
    CCXT_PUBLIC_METHODS, CCXT_PRIVATE_METHODS, CCXT_WATCH_METHODS,
)
from ccxt_gateway.core.zmq_broker import ZMQBroker
from ccxt_gateway.core.process_manager import ExchangeProcess, ProcessManager
from ccxt_gateway.exchange.methods import (
    get_ccxt_method, is_public_method, is_private_method,
    is_watch_method, get_supported_methods,
)
from ccxt_gateway.utils.updates import check_update, get_current_version, UpdateChecker


# ============================================
# TESTS FOR config.py
# ============================================

class TestServerConfig:
    """Tests for ServerConfig."""

    def test_default_values(self):
        """Test default values are set correctly."""
        config = ServerConfig()
        assert config.host == "0.0.0.0"
        assert config.port == 8000
        assert config.debug is False
        assert config.use_ssl is False
        assert config.use_granian is False


class TestZMQConfig:
    """Tests for ZMQConfig."""

    def test_default_values(self):
        """Test default values are set correctly."""
        config = ZMQConfig()
        assert config.broker_address == "tcp://127.0.0.1:5555"
        assert config.subprocess_connect == "tcp://127.0.0.1:5555"
        assert config.high_water_mark == 1000


class TestSettings:
    """Tests for Settings."""

    def test_init_without_yaml(self):
        """Test initialization without YAML file."""
        settings = Settings()
        assert settings.server.port == 8000
        assert settings.zmq.broker_address == "tcp://127.0.0.1:5555"

    def test_init_with_yaml(self, tmp_path):
        """Test initialization with YAML file."""
        yaml_content = """
server:
  port: 9000
zmq:
  broker_address: "tcp://127.0.0.1:5556"
"""
        yaml_file = tmp_path / "config.yaml"
        yaml_file.write_text(yaml_content)

        settings = Settings(str(yaml_file))
        assert settings.server.port == 9000
        assert settings.zmq.broker_address == "tcp://127.0.0.1:5556"


# ============================================
# TESTS FOR core/protocol.py
# ============================================

class TestCreateRequest:
    """Tests for create_request."""

    def test_basic(self):
        """Test creating a basic request."""
        result = create_request("fetch_ticker", {"symbol": "BTC/USDT"}, "my-binance")
        parsed = json.loads(result.decode("utf-8"))
        assert parsed["type"] == "request"
        assert parsed["method"] == "fetch_ticker"
        assert parsed["params"]["symbol"] == "BTC/USDT"
        assert parsed["exchange_id"] == "my-binance"
        assert "id" in parsed

    def test_with_auth(self):
        """Test request with API key and secret."""
        result = create_request(
            "fetch_balance", {}, "my-exchange",
            api_key="test-key", secret="test-secret"
        )
        parsed = json.loads(result.decode("utf-8"))
        assert parsed["api_key"] == "test-key"
        assert parsed["secret"] == "test-secret"


class TestCreateResponse:
    """Tests for create_response."""

    def test_success(self):
        """Test creating a success response."""
        result = create_response("req-123", result={"price": 50000})
        parsed = json.loads(result.decode("utf-8"))
        assert parsed["type"] == "response"
        assert parsed["id"] == "req-123"
        assert parsed["result"]["price"] == 50000

    def test_error(self):
        """Test creating an error response."""
        result = create_response(
            "req-456", error="Failed", error_code="ERR_CODE"
        )
        parsed = json.loads(result.decode("utf-8"))
        assert parsed["error"] == "Failed"
        assert parsed["error_code"] == "ERR_CODE"


class TestCreateSubprocessReady:
    """Tests for create_subprocess_ready."""

    def test_basic(self):
        """Test creating subprocess ready message."""
        result = create_subprocess_ready("my-binance", 12345)
        parsed = json.loads(result.decode("utf-8"))
        assert parsed["type"] == "subprocess_ready"
        assert parsed["exchange_id"] == "my-binance"
        assert parsed["pid"] == 12345


class TestCreateHeartbeat:
    """Tests for create_heartbeat."""

    def test_basic(self):
        """Test creating heartbeat message."""
        result = create_heartbeat()
        parsed = json.loads(result.decode("utf-8"))
        assert parsed["type"] == "heartbeat"
        assert "timestamp" in parsed


class TestCreateWatchUpdate:
    """Tests for create_watch_update."""

    def test_basic(self):
        """Test creating watch update message."""
        result = create_watch_update("sub-1", {"price": 50000})
        parsed = json.loads(result.decode("utf-8"))
        assert parsed["type"] == "watch_update"
        assert parsed["subscription_id"] == "sub-1"
        assert parsed["data"]["price"] == 50000


class TestParseMessage:
    """Tests for parse_message."""

    def test_valid_json(self):
        """Test parsing valid JSON."""
        data = b'{"type": "test", "id": "123"}'
        result = parse_message(data)
        assert result["type"] == "test"
        assert result["id"] == "123"

    def test_invalid_json(self):
        """Test parsing invalid JSON raises error."""
        data = b"not json"
        with pytest.raises(Exception):
            parse_message(data)


class TestMethodConstants:
    """Tests for method constants."""

    def test_public_methods(self):
        """Test public methods frozenset."""
        assert "fetch_ticker" in CCXT_PUBLIC_METHODS
        assert "fetch_markets" in CCXT_PUBLIC_METHODS

    def test_private_methods(self):
        """Test private methods frozenset."""
        assert "fetch_balance" in CCXT_PRIVATE_METHODS
        assert "create_order" in CCXT_PRIVATE_METHODS

    def test_watch_methods(self):
        """Test watch methods frozenset."""
        assert "watch_ticker" in CCXT_WATCH_METHODS
        assert "watch_order_book" in CCXT_WATCH_METHODS


# ============================================
# TESTS FOR core/zmq_broker.py
# ============================================

class TestZMQBroker:
    """Tests for ZMQBroker class."""

    def test_init(self):
        """Test initialization."""
        broker = ZMQBroker("tcp://127.0.0.1:15555")
        assert broker.broker_address == "tcp://127.0.0.1:15555"
        assert broker.running is False
        assert len(broker.pending_requests) == 0

    def test_register_unregister_exchange(self):
        """Test registering and unregistering exchanges."""
        broker = ZMQBroker()
        identity = b"test-identity"

        broker.register_exchange("ex1", identity)
        assert "ex1" in broker.exchange_identities
        assert broker.exchange_identities["ex1"] == identity

        broker.unregister_exchange("ex1")
        assert "ex1" not in broker.exchange_identities

    def test_register_subscription(self):
        """Test registering subscriptions."""
        broker = ZMQBroker()
        broker.register_subscription("sub-1", "ex1")
        assert "sub-1" in broker.subscriptions
        assert broker.subscriptions["sub-1"] == "ex1"

    def test_set_callback(self):
        """Test setting watch update callback."""
        broker = ZMQBroker()

        def dummy_callback(subscription_id, data):
            pass

        broker.set_watch_update_callback(dummy_callback)
        assert broker.watch_update_callback is not None


# ============================================
# TESTS FOR core/process_manager.py
# ============================================

class TestExchangeProcess:
    """Tests for ExchangeProcess class."""

    def test_init(self):
        """Test initialization."""
        proc = ExchangeProcess(
            exchange_id="test",
            exchange_name="binance",
            process=None,
            started_at=1000.0,
        )
        assert proc.exchange_id == "test"
        assert proc.exchange_name == "binance"
        assert proc.is_running is False
        assert proc.pid is None
        assert proc.restart_count == 0

    def test_pid_with_process(self):
        """Test pid property with valid process."""
        mock_process = MagicMock()
        mock_process.returncode = None
        mock_process.pid = 12345

        proc = ExchangeProcess(
            exchange_id="test",
            exchange_name="binance",
            process=mock_process,
            started_at=1000.0,
        )
        assert proc.pid == 12345

    def test_is_running_true(self):
        """Test is_running returns True when process running."""
        mock_process = MagicMock()
        mock_process.returncode = None

        proc = ExchangeProcess(
            exchange_id="test",
            exchange_name="binance",
            process=mock_process,
            started_at=1000.0,
        )
        assert proc.is_running is True

    def test_should_restart(self):
        """Test should_restart logic."""
        proc = ExchangeProcess(
            exchange_id="test",
            exchange_name="binance",
            process=None,
            started_at=1000.0,
        )
        proc.restart_count = 3
        assert proc.should_restart(5) is True

        # At limit but recent
        proc.restart_count = 5
        proc.last_restart = time.time()
        assert proc.should_restart(5) is False


class TestProcessManager:
    """Tests for ProcessManager class."""

    def test_init(self):
        """Test initialization."""
        pm = ProcessManager(max_rss_mb=256, check_interval=60)
        assert pm.max_rss_mb == 256
        assert pm.check_interval == 60
        assert pm.running is False


# ============================================
# TESTS FOR exchange/methods.py
# ============================================

class TestGetCcxtMethod:
    """Tests for get_ccxt_method."""

    def test_existing_method(self):
        """Test getting existing method."""
        import ccxt.async_support as ccxt
        exchange = ccxt.binance({"enableRateLimit": True})
        method = get_ccxt_method(exchange, "fetch_ticker")
        assert method is not None

    def test_nonexistent_method(self):
        """Test getting non-existent method."""
        import ccxt.async_support as ccxt
        exchange = ccxt.binance({"enableRateLimit": True})
        method = get_ccxt_method(exchange, "nonexistent_method")
        assert method is None


class TestIsPublicMethod:
    """Tests for is_public_method."""

    def test_public(self):
        """Test public method detection."""
        assert is_public_method("fetch_ticker") is True

    def test_not_public(self):
        """Test non-public method detection."""
        assert is_public_method("fetch_balance") is False


class TestIsPrivateMethod:
    """Tests for is_private_method."""

    def test_private(self):
        """Test private method detection."""
        assert is_private_method("fetch_balance") is True

    def test_not_private(self):
        """Test non-private method detection."""
        assert is_private_method("fetch_ticker") is False


class TestIsWatchMethod:
    """Tests for is_watch_method."""

    def test_watch(self):
        """Test watch method detection."""
        assert is_watch_method("watch_ticker") is True

    def test_not_watch(self):
        """Test non-watch method detection."""
        assert is_watch_method("fetch_ticker") is False


# ============================================
# TESTS FOR utils/updates.py
# ============================================

class TestUpdateChecker:
    """Tests for UpdateChecker."""

    def test_init(self):
        """Test initialization."""
        checker = UpdateChecker(check_interval_hours=12)
        assert checker.check_interval_hours == 12
        assert checker.auto_update is False
        assert checker.running is False


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
