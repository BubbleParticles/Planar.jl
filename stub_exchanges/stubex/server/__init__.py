"""Stub exchange server module.

This module provides a local HTTP server that serves stub data for ccxt exchanges.
Instead of patching every function in ccxt, we override the API URLs to point to
this local server, which returns deterministic stub data while preserving ccxt's
request/response logic.
"""

from .server import StubServer, get_stub_server, start_stub_server

__all__ = ['StubServer', 'get_stub_server', 'start_stub_server']
