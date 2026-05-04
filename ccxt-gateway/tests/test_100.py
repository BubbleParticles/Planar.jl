"""Tests for 100% coverage."""

import pytest
from ccxt_gateway.config import Settings, ServerConfig

class TestConfig:
    def test_server_config(self):
        c = ServerConfig()
        assert c.host == "0.0.0.0"
        assert c.port == 8000

    def test_settings(self):
        s = Settings()
        assert s.server.port == 8000
